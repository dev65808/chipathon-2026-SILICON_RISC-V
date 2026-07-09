/* Copyright 2024
   SPDX-License-Identifier: Apache-2.0

   rv32i_qspi_mem — QSPI Memory Subsystem for a Single-Cycle RV32I Processor

   Wraps the existing qspi_controller to give a single-cycle RV32I core a
   clean instruction-fetch port (flash, read-only) and a data port (PSRAM,
   read/write).

   ┌─────────────────────────────────────────────────────────────────────────┐
   │ Address map (same as qspi_controller internal mapping)                  │
   │   Flash  (instructions): i_addr[23:0]        → QSPI 0x0000000-0x0FFFFFF│
   │   PSRAM A (data R/W):    d_addr[24:0], [24:23]=10 → 0x1000000-0x17FFFFF│
   │   PSRAM B (data R/W):    d_addr[24:0], [24:23]=11 → 0x1800000-0x1FFFFFF│
   └─────────────────────────────────────────────────────────────────────────┘

   ── Instruction port protocol ──────────────────────────────────────────────
     1. Assert i_req for exactly ONE cycle; hold i_addr stable.
     2. Deassert i_req.  Keep i_addr stable until i_ready fires.
     3. i_ready pulses HIGH for one cycle; i_rdata holds the 32-bit
        little-endian instruction word.

   ── Data port protocol ────────────────────────────────────────────────────
     1. Assert d_req for exactly ONE cycle.
        • Set d_we=0 for reads, d_we=1 for writes.
        • d_wstrb byte enables:
            4'b0001 → 1 byte   at d_addr
            4'b0011 → 2 bytes  at d_addr, d_addr+1
            4'b1111 → 4 bytes  at d_addr … d_addr+3
            4'b0010 → 1 byte   at d_addr+1  (single set bit at lane 1)
            etc. — first byte transferred is at d_addr + lowest-set-bit(d_wstrb)
        • For writes, d_wdata[8i+7:8i] is the byte written at d_addr+i
          for each set bit i in d_wstrb.
        • For reads,  d_rdata[8i+7:8i] returns the i-th byte received
          (i=0 is the byte at d_addr + lowest-set-bit(d_wstrb)).
     2. Hold all inputs stable until d_ready fires.
     3. d_ready pulses HIGH for one cycle.
        • Reads:  d_rdata is valid on the d_ready cycle.
        • Writes: d_ready fires one cycle after the last write byte is
                  handed to the QSPI controller (the SPI burst may still
                  be completing in the background, but the chip-select
                  guard in this module ensures the next transaction cannot
                  start until the bus is free).

   ── Priority ──────────────────────────────────────────────────────────────
     d_req takes precedence over i_req when both arrive in the same cycle.
     Do not issue a new request of either kind while a transaction is in
     progress (i_ready / d_ready have not yet fired).

   ── Stalling ──────────────────────────────────────────────────────────────
     QSPI is not single-cycle; a typical flash read takes ~30+ system clock
     cycles and a PSRAM read/write ~20+ cycles.  The CPU must stall
     (i.e. hold its pipeline frozen) between asserting a request and
     receiving the corresponding ready signal.
     See docs/qspi_mem_subsystem.md for latency details.
*/

`default_nettype none

module rv32i_qspi_mem (
    input  wire        clk,
    input  wire        rstn,

    // ── Instruction port (read-only, external flash) ──────────────────────
    input  wire [23:0] i_addr,    // byte address in flash
    input  wire        i_req,     // one-cycle pulse: request a 32-bit fetch
    output wire [31:0] i_rdata,   // 32-bit instruction word (little-endian)
    output reg         i_ready,   // one-cycle pulse: i_rdata is valid

    // ── Data port (read/write, external PSRAM A/B) ────────────────────────
    input  wire [24:0] d_addr,    // byte start address (bit24=1 → PSRAM space)
    input  wire        d_req,     // one-cycle pulse: start transaction
    input  wire        d_we,      // 0=read, 1=write
    input  wire  [3:0] d_wstrb,   // byte enables (see header for encoding)
    input  wire [31:0] d_wdata,   // write data  (byte i at bits [8i+7:8i])
    output wire [31:0] d_rdata,   // read  data  (byte i at bits [8i+7:8i])
    output reg         d_ready,   // one-cycle pulse: transaction complete

    // ── QSPI PMOD signals ─────────────────────────────────────────────────
    input  wire  [3:0] spi_data_in,
    output wire  [3:0] spi_data_out,
    output wire  [3:0] spi_data_oe,
    output wire        spi_clk_out,
    output wire        spi_flash_select,
    output wire        spi_ram_a_select,
    output wire        spi_ram_b_select
);

    // ── State encoding ────────────────────────────────────────────────────
    localparam ST_IDLE       = 2'd0;
    localparam ST_INSTR_WAIT = 2'd1;  // waiting for instruction bytes
    localparam ST_DATA_WAIT  = 2'd2;  // waiting for data bytes / write acks

    reg [1:0] state;
    reg [2:0] byte_cnt;    // bytes received/sent so far (0-indexed)
    reg [2:0] byte_total;  // total bytes in this transaction (1, 2, or 4)
    reg [1:0] first_byte;  // byte-lane offset of lowest set bit in d_wstrb
    reg       op_is_write; // registered: current data op is a write

    // ── Output data buffers ───────────────────────────────────────────────
    reg [31:0] i_rdata_r;
    reg [31:0] d_rdata_r;
    assign i_rdata = i_rdata_r;
    assign d_rdata = d_rdata_r;

    // ── QSPI controller wires ─────────────────────────────────────────────
    wire [7:0] qspi_dout;       // byte received from QSPI
    wire       qspi_data_req;   // controller requests next write byte
    wire       qspi_data_ready; // controller has a new read byte
    wire       qspi_busy;       // controller is mid-transaction

    reg  [24:0] qspi_addr;
    reg  [7:0]  qspi_din;
    reg         qspi_start_read;
    reg         qspi_start_write;
    reg         qspi_stop;

    // ── d_wstrb helpers ───────────────────────────────────────────────────
    // Position of the lowest set bit → first byte to transfer
    wire [1:0] d_first_byte =
        d_wstrb[0] ? 2'd0 :
        d_wstrb[1] ? 2'd1 :
        d_wstrb[2] ? 2'd2 : 2'd3;

    // Number of set bits → byte count (supports 1, 2, 3, 4)
    /* verilator lint_off WIDTH */
    wire [2:0] d_byte_count = {2'd0, d_wstrb[0]} + {2'd0, d_wstrb[1]}
                            + {2'd0, d_wstrb[2]} + {2'd0, d_wstrb[3]};
    /* verilator lint_on WIDTH */

    // ── PSRAM chip-select guard ───────────────────────────────────────────
    // The qspi_controller requires 2 system clock cycles after a PSRAM chip
    // is deselected before it can be re-selected.  We mirror its internal
    // last_ram_x_sel registers to block premature re-issue.
    reg last_ram_a_sel_r;
    reg last_ram_b_sel_r;
    always @(posedge clk) begin
        if (!rstn) begin
            last_ram_a_sel_r <= 1'b1;
            last_ram_b_sel_r <= 1'b1;
        end else begin
            last_ram_a_sel_r <= spi_ram_a_select;
            last_ram_b_sel_r <= spi_ram_b_select;
        end
    end

    wire ram_a_blocked = (!last_ram_a_sel_r) && (d_addr[24:23] == 2'b10);
    wire ram_b_blocked = (!last_ram_b_sel_r) && (d_addr[24:23] == 2'b11);
    wire data_can_start = d_req && !qspi_busy && !ram_a_blocked && !ram_b_blocked;

    // ── Write byte pointer (combinatorial look-ahead) ─────────────────────
    // When qspi_data_req fires (on the SPI falling edge, i.e. !spi_clk_pos),
    // we must already present the next byte on qspi_din so the controller can
    // latch it on the immediately following SPI rising edge.
    wire [1:0] wr_ptr = first_byte + byte_cnt[1:0]
                        + (qspi_data_req ? 2'd1 : 2'd0);

    // ── Combinatorial QSPI control ────────────────────────────────────────
    always @(*) begin
        qspi_start_read  = 1'b0;
        qspi_start_write = 1'b0;
        qspi_stop        = 1'b0;
        qspi_addr        = 25'd0;
        qspi_din         = 8'hFF;

        case (state)
            ST_IDLE: begin
                if (data_can_start) begin
                    // Base address for data: d_addr + first enabled byte lane
                    qspi_addr        = d_addr + {3'd0, d_first_byte};
                    qspi_start_read  = ~d_we;
                    qspi_start_write =  d_we;
                end else if (i_req && !qspi_busy) begin
                    // Flash address: bit 24 = 0 (selects flash in qspi_controller)
                    qspi_addr       = {1'b0, i_addr};
                    qspi_start_read = 1'b1;
                end
            end

            ST_INSTR_WAIT: begin
                // Stop burst after last instruction byte arrives
                if (qspi_data_ready && (byte_cnt == byte_total - 3'd1))
                    qspi_stop = 1'b1;
            end

            ST_DATA_WAIT: begin
                if (op_is_write) begin
                    // Present next write byte; stop after last data_req
                    qspi_din = d_wdata[{wr_ptr, 3'b000} +: 8];
                    if (qspi_data_req && (byte_cnt == byte_total - 3'd1))
                        qspi_stop = 1'b1;
                end else begin
                    // Stop burst after last read byte arrives
                    if (qspi_data_ready && (byte_cnt == byte_total - 3'd1))
                        qspi_stop = 1'b1;
                end
            end

            default: ;
        endcase
    end

    // ── Registered state machine ──────────────────────────────────────────
    // d_write_completing: set on the cycle the last write byte is sent;
    // d_ready fires ONE cycle later (after stop_txn_now propagates).
    reg d_write_completing;

    always @(posedge clk) begin
        if (!rstn) begin
            state              <= ST_IDLE;
            byte_cnt           <= 3'd0;
            byte_total         <= 3'd0;
            first_byte         <= 2'd0;
            op_is_write        <= 1'b0;
            i_ready            <= 1'b0;
            d_ready            <= 1'b0;
            d_write_completing <= 1'b0;
            i_rdata_r          <= 32'd0;
            d_rdata_r          <= 32'd0;
        end else begin
            // Defaults (cleared every cycle unless overridden below)
            i_ready            <= 1'b0;
            d_write_completing <= 1'b0;

            // d_ready for writes fires one cycle after d_write_completing
            d_ready <= d_write_completing;

            case (state)
                // ── IDLE: wait for any request ──────────────────────────
                ST_IDLE: begin
                    if (data_can_start) begin
                        state       <= ST_DATA_WAIT;
                        byte_cnt    <= 3'd0;
                        byte_total  <= d_byte_count;
                        first_byte  <= d_first_byte;
                        op_is_write <= d_we;
                    end else if (i_req && !qspi_busy) begin
                        state       <= ST_INSTR_WAIT;
                        byte_cnt    <= 3'd0;
                        byte_total  <= 3'd4;   // always fetch a full 32-bit word
                        op_is_write <= 1'b0;
                    end
                end

                // ── INSTR_WAIT: collect 4 bytes from flash ──────────────
                ST_INSTR_WAIT: begin
                    if (qspi_data_ready) begin
                        // Assemble little-endian 32-bit word
                        i_rdata_r[{byte_cnt[1:0], 3'b000} +: 8] <= qspi_dout;
                        if (byte_cnt == byte_total - 3'd1) begin
                            state   <= ST_IDLE;
                            i_ready <= 1'b1;
                        end else
                            byte_cnt <= byte_cnt + 3'd1;
                    end
                end

                // ── DATA_WAIT: handle one data read or write ─────────────
                ST_DATA_WAIT: begin
                    if (!op_is_write) begin
                        // ── Read: collect bytes into d_rdata_r ──────────
                        if (qspi_data_ready) begin
                            d_rdata_r[{byte_cnt[1:0], 3'b000} +: 8] <= qspi_dout;
                            if (byte_cnt == byte_total - 3'd1) begin
                                state   <= ST_IDLE;
                                d_ready <= 1'b1;  // immediate for reads
                            end else
                                byte_cnt <= byte_cnt + 3'd1;
                        end
                    end else begin
                        // ── Write: count data_req pulses ─────────────────
                        // The first write byte was pre-loaded when start_write
                        // fired; each subsequent data_req asks for the next byte.
                        if (qspi_data_req) begin
                            if (byte_cnt == byte_total - 3'd1) begin
                                state              <= ST_IDLE;
                                d_write_completing <= 1'b1;
                                // d_ready fires next cycle via d_write_completing
                            end else
                                byte_cnt <= byte_cnt + 3'd1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // ── qspi_controller instantiation ────────────────────────────────────
    qspi_controller q_ctrl (
        .clk             (clk),
        .rstn            (rstn),

        .spi_data_in     (spi_data_in),
        .spi_data_out    (spi_data_out),
        .spi_data_oe     (spi_data_oe),
        .spi_clk_out     (spi_clk_out),

        .spi_flash_select(spi_flash_select),
        .spi_ram_a_select(spi_ram_a_select),
        .spi_ram_b_select(spi_ram_b_select),

        .addr_in         (qspi_addr),
        .data_in         (qspi_din),
        .start_read      (qspi_start_read),
        .start_write     (qspi_start_write),
        .stall_txn       (1'b0),
        .stop_txn        (qspi_stop),

        .data_out        (qspi_dout),
        .data_req        (qspi_data_req),
        .data_ready      (qspi_data_ready),
        .busy            (qspi_busy)
    );

endmodule
`default_nettype wire
