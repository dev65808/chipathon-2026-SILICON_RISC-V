
`default_nettype none

module spi_riscv_if (
    input  wire         clk,
    input  wire         resetn,

    // Memory-mapped register bus
    // reg_addr[1:0] selects one of four 32-bit word registers.
    // For a byte-addressed bus, connect addr[3:2] here through the core. 

    input  wire [1:0]   reg_addr,
    input  wire [31:0]  reg_wdata,
    input  wire         reg_we,     // write-enable (1-cycle pulse)
    input  wire         reg_re,     // read-enable  (1-cycle pulse)
    output reg  [31:0]  reg_rdata,  // combinational read data

    // Physical SPI pins
   input  wire         spi_miso,
   output wire         spi_select,
   output wire         spi_clk_out,
   output wire         spi_mosi,
   output wire         spi_dc,

    // Completion signal (same as tx_irq in uart_riscv_if.v)

    output wire         spi_done
);


// Address decode constants

localparam ADDR_DATA   = 2'b00;
localparam ADDR_STATUS = 2'b01;
localparam ADDR_CTRL   = 2'b10;
localparam ADDR_CONFIG = 2'b11;


// CTRL register — dc / end_txn latched here

reg [1:0] ctrl_reg;   // [0]=dc, [1]=end_txn

always @(posedge clk) begin
    if (!resetn) begin
        ctrl_reg <= 2'b00;
    end else if (reg_we && reg_addr == ADDR_CTRL) begin
        ctrl_reg <= reg_wdata[1:0];
    end
end

// CONFIG register — divider / read_latency, plus a set_config pulse

reg [3:0] divider_reg;
reg       read_latency_reg;

always @(posedge clk) begin
    if (!resetn) begin
        divider_reg      <= 4'd0;
        read_latency_reg <= 1'b0;
    end else if (reg_we && reg_addr == ADDR_CONFIG) begin
        divider_reg      <= reg_wdata[3:0];
        read_latency_reg <= reg_wdata[4];
    end
end

wire set_config = reg_we && (reg_addr == ADDR_CONFIG);


// Internal spi_ctrl handshake signals

wire       spi_busy;
wire [7:0] spi_data_out;

// Start pulse: one cycle when writing DATA

wire spi_start = reg_we && (reg_addr == ADDR_DATA);


// spi_ctrl.v module instance

spi_ctrl i_spi_ctrl (
    .clk            (clk),
    .rstn           (resetn),

    .spi_miso       (spi_miso),
    .spi_select     (spi_select),
    .spi_clk_out    (spi_clk_out),
    .spi_mosi       (spi_mosi),
    .spi_dc         (spi_dc),

    .dc_in          (ctrl_reg[0]),
    .end_txn        (ctrl_reg[1]),
    .data_in        (reg_wdata[7:0]),
    .start          (spi_start),
    .data_out       (spi_data_out),
    .busy           (spi_busy),

    .set_config     (set_config),
    .divider_in     (divider_reg),
    .read_latency_in(read_latency_reg)
);


// Register read (combinational)

always @(*) begin
    case (reg_addr)
        ADDR_DATA:   reg_rdata = {24'h0, spi_data_out};
        ADDR_STATUS: reg_rdata = {31'h0, spi_busy};
        ADDR_CTRL:   reg_rdata = {30'h0, ctrl_reg};
        ADDR_CONFIG: reg_rdata = {27'h0, read_latency_reg, divider_reg};
        default:     reg_rdata = 32'hFFFF_FFFF;
    endcase
end


// Completion signal (level-based, sane as tx_irq's "!busy" pattern)

assign spi_done = !spi_busy;

endmodule
