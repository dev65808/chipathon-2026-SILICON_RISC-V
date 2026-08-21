// Copyright (c) 2021 Ben Marshall (uart_tx.v, uart_rx.v)
// Changes Copyright (c) 2023 Michael Bell (uart_tx.v, uart_rx.v)
// Wrapper Copyright (c) 2024 silicon-vlsi
// MIT License
//
// Module: uart_riscv_if
//
// Memory-mapped UART interface wrapper for single-cycle RISC-V cores.
//
// Register map (word-addressed, reg_addr[1:0]):
//
//   Offset  Name      Access  Description
//   ------  --------  ------  ---------------------------------------------------
//   2'b00   DATA      R/W     [7:0] Write: queues TX byte (ignored when tx_busy).
//                             Read: returns latest RX byte; pulses uart_rx_read.
//   2'b01   STATUS    RO      [0] tx_busy — TX serialiser is active.
//                             [1] rx_valid — RX byte is waiting to be read.
//   2'b10   CTRL      R/W     [0] rx_irq_en — enable rx_irq output.
//                             [1] tx_irq_en — enable tx_irq output.
//   2'b11   BAUD_DIV  RO      [15:0] Computed baud divisor: (CLK_HZ-1)/BIT_RATE.
//
// Byte offsets (for byte-addressed buses shift reg_addr left by 2):
//   DATA = 0x00, STATUS = 0x04, CTRL = 0x08, BAUD_DIV = 0x0C
//
// Interrupts (level-based, gated by CTRL):
//   rx_irq = rx_valid  && ctrl[0]  — stays high until DATA is read
//   tx_irq = !tx_busy  && ctrl[1]  — stays high while TX is idle
//

`default_nettype none

module uart_riscv_if #(parameter
    CLK_HZ       = 50_000_000,  // System clock frequency in Hz
    BIT_RATE     = 115_200,     // UART baud rate in bps
    PAYLOAD_BITS = 8,           // Data bits per UART frame (typically 8)
    STOP_BITS    = 1            // Stop bits per UART frame (typically 1)
) (
    input  wire                   clk,
    input  wire                   resetn,

    // Memory-mapped register bus
    // reg_addr[1:0] selects one of four 32-bit word registers.
    // For a byte-addressed bus, connect addr[3:2] here.
    input  wire [1:0]             reg_addr,
    input  wire [31:0]            reg_wdata,
    input  wire                   reg_we,     // write-enable (1-cycle pulse)
    input  wire                   reg_re,     // read-enable  (1-cycle pulse)
    output reg  [31:0]            reg_rdata,  // combinational read data

    // UART serial pins
    output wire                   uart_tx,    // UART transmit (idle-high)
    input  wire                   uart_rx,    // UART receive  (idle-high)

    // Level-based interrupt outputs (gated by CTRL register)
    output wire                   tx_irq,     // TX serialiser idle (if tx_irq_en)
    output wire                   rx_irq      // RX byte available  (if rx_irq_en)
);

// ---------------------------------------------------------------------------
// Address decode constants
// ---------------------------------------------------------------------------
localparam ADDR_DATA    = 2'b00;
localparam ADDR_STATUS  = 2'b01;
localparam ADDR_CTRL    = 2'b10;
localparam ADDR_BAUD_DIV= 2'b11;

// ---------------------------------------------------------------------------
// CTRL register
// ---------------------------------------------------------------------------
reg [1:0] ctrl_reg;

always @(posedge clk) begin
    if (!resetn) begin
        ctrl_reg <= 2'b00;
    end else if (reg_we && reg_addr == ADDR_CTRL) begin
        ctrl_reg <= reg_wdata[1:0];
    end
end

// ---------------------------------------------------------------------------
// Internal UART signals
// ---------------------------------------------------------------------------
wire uart_tx_busy;
wire uart_rx_valid;
wire [PAYLOAD_BITS-1:0] uart_rx_data;

// TX enable: one-cycle pulse when writing the DATA register
wire uart_tx_en   = reg_we && (reg_addr == ADDR_DATA);

// RX read-ack: one-cycle pulse when reading the DATA register (clears rx_valid)
wire uart_rx_read = reg_re && (reg_addr == ADDR_DATA);

// ---------------------------------------------------------------------------
// UART TX instance
// ---------------------------------------------------------------------------
uart_tx #(
    .CLK_HZ      (CLK_HZ),
    .BIT_RATE    (BIT_RATE),
    .PAYLOAD_BITS(PAYLOAD_BITS),
    .STOP_BITS   (STOP_BITS)
) i_uart_tx (
    .clk         (clk),
    .resetn      (resetn),
    .uart_txd    (uart_tx),
    .uart_tx_busy(uart_tx_busy),
    .uart_tx_en  (uart_tx_en),
    .uart_tx_data(reg_wdata[PAYLOAD_BITS-1:0])
);

// ---------------------------------------------------------------------------
// UART RX instance
// ---------------------------------------------------------------------------
wire uart_rts_unused;   // RTS output not used by this wrapper

uart_rx #(
    .CLK_HZ      (CLK_HZ),
    .BIT_RATE    (BIT_RATE),
    .PAYLOAD_BITS(PAYLOAD_BITS),
    .STOP_BITS   (STOP_BITS)
) i_uart_rx (
    .clk          (clk),
    .resetn       (resetn),
    .uart_rxd     (uart_rx),
    .uart_rts     (uart_rts_unused),
    .uart_rx_read (uart_rx_read),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_data (uart_rx_data)
);

// ---------------------------------------------------------------------------
// Register read (combinational)
// ---------------------------------------------------------------------------
localparam [15:0] BAUD_DIV_VAL = (CLK_HZ - 1) / BIT_RATE;

always @(*) begin
    case (reg_addr)
        ADDR_DATA:    reg_rdata = {{(32-PAYLOAD_BITS){1'b0}}, uart_rx_data};
        ADDR_STATUS:  reg_rdata = {30'h0, uart_rx_valid, uart_tx_busy};
        ADDR_CTRL:    reg_rdata = {30'h0, ctrl_reg};
        ADDR_BAUD_DIV:reg_rdata = {16'h0, BAUD_DIV_VAL};
        default:      reg_rdata = 32'hFFFF_FFFF;
    endcase
end

// ---------------------------------------------------------------------------
// Interrupt outputs (level-based)
// ---------------------------------------------------------------------------
assign rx_irq = uart_rx_valid && ctrl_reg[0];
assign tx_irq = !uart_tx_busy && ctrl_reg[1];

endmodule
