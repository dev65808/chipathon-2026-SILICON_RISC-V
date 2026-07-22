// qspi_controller.v
// Low-level QSPI protocol engine — extracted verbatim from the combined
// Makerchip file, now a standalone module for external instantiation.
// Source: silicon-vlsi/tt10-tinyQV repository.

module qspi_controller (
    input clk,
    input rstn,
    input      [3:0] spi_data_in,
    output reg [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output           spi_clk_out,
    output reg       spi_flash_select,
    output reg       spi_ram_a_select,
    output reg       spi_ram_b_select,
    input [24:0] addr_in,
    input  [7:0] data_in,
    input        start_read,
    input        start_write,
    input        stall_txn,
    input        stop_txn,
    output [7:0] data_out,
    output reg   data_req,
    output reg   data_ready,
    output       busy
);
`define max(a, b) ((a > b) ? a : b)
    localparam ADDR_BITS = 24;
    localparam DATA_WIDTH_BITS = 8;
    localparam FSM_IDLE = 0;
    localparam FSM_CMD  = 1;
    localparam FSM_ADDR = 2;
    localparam FSM_DUMMY1 = 3;
    localparam FSM_DUMMY2 = 4;
    localparam FSM_DATA = 5;
    localparam FSM_STALLED = 6;
    localparam FSM_STALL_RECOVER = 7;
    reg [2:0] fsm_state;
    reg       is_writing;
    reg [ADDR_BITS-1:0]       addr;
    reg [DATA_WIDTH_BITS-1:0] data;
    reg [2:0] nibbles_remaining;
    reg [1:0] delay_cycles_cfg;
    reg       spi_clk_use_neg;
    reg       spi_clk_pos;
    reg       spi_clk_neg;
    reg [3:0] spi_in_buffer;
    assign data_out = data;
    assign busy = fsm_state != FSM_IDLE;
    reg stop_txn_reg;
    wire stop_txn_now = stop_txn_reg || (stop_txn && (!is_writing || spi_clk_pos));
    always @(posedge clk) begin
        if (!rstn) stop_txn_reg <= 0;
        else stop_txn_reg <= stop_txn && !stop_txn_now;
    end
    reg [1:0] read_cycles_count;
    reg last_ram_a_sel;
    reg last_ram_b_sel;
    wire ram_a_block = (last_ram_a_sel == 0) && addr_in[24:23] == 2'b10;
    wire ram_b_block = (last_ram_b_sel == 0) && addr_in[24:23] == 2'b11;
    always @(posedge clk) begin
        if (!rstn) begin
            delay_cycles_cfg <= spi_data_in[1:0];
            spi_clk_use_neg <= spi_data_in[2];
        end
    end
/* verilator lint_off WIDTH */
    always @(posedge clk) begin
        if (!rstn || stop_txn_now) begin
            fsm_state <= FSM_IDLE;
            is_writing <= 0;
            nibbles_remaining <= 0;
            data_ready <= 0;
            spi_clk_pos <= 0;
            spi_data_oe <= 4'b0000;
            spi_flash_select <= 1;
            spi_ram_a_select <= 1;
            spi_ram_b_select <= 1;
            data_req <= 0;
            read_cycles_count <= 0;
        end else begin
            data_ready <= 0;
            data_req <= 0;
            if (fsm_state == FSM_IDLE) begin
                if ((start_read || start_write) && !ram_a_block && !ram_b_block) begin
                    fsm_state <= addr_in[24] ? FSM_CMD : FSM_ADDR;
                    is_writing <= !start_read && addr_in[24];
                    nibbles_remaining <= addr_in[24] ? 2-1 : 6-1;
                    spi_data_oe <= 4'b1111;
                    spi_clk_pos <= 0;
                    spi_flash_select <= addr_in[24];
                    spi_ram_a_select <= addr_in[24:23] != 2'b10;
                    spi_ram_b_select <= addr_in[24:23] != 2'b11;
                end
            end else begin
                if (read_cycles_count == 0) read_cycles_count <= 2'b01;
                else read_cycles_count <= read_cycles_count - 2'b01;
                if (fsm_state == FSM_STALLED) begin
                    spi_clk_pos <= 0;
                    if (!stall_txn && !read_cycles_count[1]) begin
                        data_ready <= !is_writing;
                        if (is_writing) begin
                            fsm_state <= FSM_DATA;
                            read_cycles_count <= 2'b00;
                        end else begin
                            fsm_state <= (delay_cycles_cfg[1] == 0) ? FSM_DATA : FSM_STALL_RECOVER;
                            read_cycles_count <= {1'b0, delay_cycles_cfg[0]};
                        end
                    end
                end else begin
                    spi_clk_pos <= !spi_clk_pos;
                    if (((fsm_state == FSM_DATA && !is_writing) || fsm_state == FSM_STALL_RECOVER) ? (read_cycles_count == 0) : spi_clk_pos) begin
                        if (nibbles_remaining == 0) begin
                            if (fsm_state == FSM_DATA || fsm_state == FSM_STALL_RECOVER) begin
                                data_ready <= !is_writing && !stall_txn;
                                nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                if (stall_txn) begin
                                    fsm_state <= FSM_STALLED;
                                    read_cycles_count <= delay_cycles_cfg | 2'b01;
                                end else begin
                                    fsm_state <= FSM_DATA;
                                end
                            end else begin
                                fsm_state <= fsm_state + 1;
                                if (fsm_state == FSM_CMD) begin
                                    nibbles_remaining <= (ADDR_BITS >> 2)-1;
                                end
                                else if (fsm_state == FSM_ADDR) begin
                                    if (is_writing) begin
                                        fsm_state <= FSM_DATA;
                                        nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                    end else if (spi_flash_select) begin
                                        fsm_state <= FSM_DUMMY2;
                                        spi_data_oe <= 4'b0000;
                                        nibbles_remaining <= 4-1;
                                    end else begin
                                        nibbles_remaining <= 2-1;
                                    end
                                end
                                else if (fsm_state == FSM_DUMMY1) begin
                                    spi_data_oe <= 4'b0000;
                                    nibbles_remaining <= 4-1;
                                end
                                else if (fsm_state == FSM_DUMMY2) begin
                                    nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                    read_cycles_count <= delay_cycles_cfg;
                                end
                            end
                        end else begin
                            if (fsm_state == FSM_STALL_RECOVER) fsm_state <= FSM_DATA;
                            nibbles_remaining <= nibbles_remaining - 1;
                        end
                    end else begin
                        data_req <= is_writing && (fsm_state == FSM_DATA) && nibbles_remaining == 0;
                    end
                end
            end
        end
    end
/* verilator lint_on WIDTH */
    always @(posedge clk) begin
        if (fsm_state == FSM_IDLE && (start_read || start_write)) begin
            addr <= addr_in[23:0];
        end else if (fsm_state == FSM_ADDR && spi_clk_pos) begin
            addr <= {addr[ADDR_BITS-5:0], 4'b0000};
        end
    end
    always @(posedge clk) begin
        if (is_writing) begin
            if (fsm_state == FSM_STALLED) begin
                data <= data_in;
            end else if (spi_clk_pos) begin
                if (nibbles_remaining == 0) begin
                    data <= data_in;
                end else if (fsm_state == FSM_DATA) begin
                    data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
                end
            end
        end else if (read_cycles_count == 0 && fsm_state == FSM_DATA) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
        end else if (read_cycles_count == 0 && fsm_state == FSM_STALL_RECOVER) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_in_buffer};
        end else if (read_cycles_count == 2'b10 && fsm_state == FSM_STALLED) begin
            spi_in_buffer <= spi_data_in;
        end
    end
    always @(*) begin
        case (fsm_state)
            FSM_CMD: begin
                if (is_writing) begin
                    if (nibbles_remaining[0]) spi_data_out = 4'b0000;
                    else spi_data_out = 4'b0010;
                end else begin
                    if (nibbles_remaining[0]) spi_data_out = 4'b0000;
                    else spi_data_out = 4'b1011;
                end
            end
            FSM_ADDR:   spi_data_out = addr[ADDR_BITS-1:ADDR_BITS-4];
            FSM_DUMMY1: spi_data_out = 4'b1010;
            FSM_DATA:   spi_data_out = is_writing ? data[DATA_WIDTH_BITS-1:DATA_WIDTH_BITS-4] : 4'b1111;
            default:    spi_data_out = 4'b1010;
        endcase
    end
    always @(posedge clk) begin
        if (!rstn) begin
            last_ram_a_sel <= 1;
            last_ram_b_sel <= 1;
        end else begin
            last_ram_a_sel <= spi_ram_a_select;
            last_ram_b_sel <= spi_ram_b_select;
        end
    end
    always @(negedge clk) spi_clk_neg <= spi_clk_pos;
    assign spi_clk_out = spi_clk_use_neg ? spi_clk_neg : spi_clk_pos;
endmodule
