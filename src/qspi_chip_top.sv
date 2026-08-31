// qspi_chip_top.sv
// Chip-level top module: instantiates the RV32I core (rv32i_core.sv) and
// the QSPI memory controller (rv32i_qspi_mem.v, which internally
// instantiates qspi_controller.v)
//
// The QSPI bus signals (spi_data_in/out/oe, spi_clk_out, the 3 chip-selects)
// are exposed as this module's own top-level ports. The simulated flash/
// PSRAM chip (sim_qspi_pmod.v) is NOT instantiated here —
// on real hardware those are external physical chips on the board, not
// part of the chip itself, so the simulation model for them only belongs
// in the testbench, not in this chip-level module.
//
// Pad-config signals (CS, SL, IE, OE, PU, PD, PDRV0, PDRV1) added directly
// in this module (per A30_A.def / A30_A_pad_map.yaml) so this file, on its
// own, has one port for every pin the organizers' reference DEF expects --
// no separate wrapper module needed.

`default_nettype none

module qspi_chip_top (

    input  wire        clk,
    output wire         clk_PU,
    output wire         clk_PD,

    input  wire        reset,
    output wire         reset_PU,
    output wire         reset_PD,

    // ---- uart_rx : input-only signal on a bidirectional pad (W15) ----
    input  wire        uart_rx_IN,
    output wire        uart_rx_OUT,
    output wire        uart_rx_OE,
    output wire        uart_rx_CS,
    output wire        uart_rx_SL,
    output wire        uart_rx_IE,
    output wire        uart_rx_PU,
    output wire        uart_rx_PD,
    output wire        uart_rx_PDRV0,
    output wire        uart_rx_PDRV1,

    // ---- spi_miso : input-only signal on a bidirectional pad (W16) ----
    input  wire        spi_miso_IN,
    output wire        spi_miso_OUT,
    output wire        spi_miso_OE,
    output wire        spi_miso_CS,
    output wire        spi_miso_SL,
    output wire        spi_miso_IE,
    output wire        spi_miso_PU,
    output wire        spi_miso_PD,
    output wire        spi_miso_PDRV0,
    output wire        spi_miso_PDRV1,

    // ---- spi_data0..3 : true bidirectional (W17-W20) ----
    input  wire        spi_data0_IN, spi_data1_IN, spi_data2_IN, spi_data3_IN,
    output wire        spi_data0_OUT, spi_data1_OUT, spi_data2_OUT, spi_data3_OUT,
    output wire        spi_data0_OE,  spi_data1_OE,  spi_data2_OE,  spi_data3_OE,
    output wire        spi_data0_CS, spi_data1_CS, spi_data2_CS, spi_data3_CS,
    output wire        spi_data0_SL, spi_data1_SL, spi_data2_SL, spi_data3_SL,
    output wire        spi_data0_IE, spi_data1_IE, spi_data2_IE, spi_data3_IE,
    output wire        spi_data0_PU, spi_data1_PU, spi_data2_PU, spi_data3_PU,
    output wire        spi_data0_PD, spi_data1_PD, spi_data2_PD, spi_data3_PD,

    // ---- output-only signals on bidirectional pads (W21,W22,N01-N06) ----
    output wire        spi_clk_out_OUT,      output wire spi_clk_out_OE,
    output wire        spi_clk_out_CS,       output wire spi_clk_out_SL,
    output wire        spi_clk_out_IE,       output wire spi_clk_out_PU,
    output wire        spi_clk_out_PD,       input  wire spi_clk_out_IN,

    output wire        spi_flash_select_OUT, output wire spi_flash_select_OE,
    output wire        spi_flash_select_CS,  output wire spi_flash_select_SL,
    output wire        spi_flash_select_IE,  output wire spi_flash_select_PU,
    output wire        spi_flash_select_PD,  input  wire spi_flash_select_IN,

    output wire        spi_ram_a_select_OUT, output wire spi_ram_a_select_OE,
    output wire        spi_ram_a_select_CS,  output wire spi_ram_a_select_SL,
    output wire        spi_ram_a_select_IE,  output wire spi_ram_a_select_PU,
    output wire        spi_ram_a_select_PD,  input  wire spi_ram_a_select_IN,

    output wire        uart_tx_OUT,          output wire uart_tx_OE,
    output wire        uart_tx_CS,           output wire uart_tx_SL,
    output wire        uart_tx_IE,           output wire uart_tx_PU,
    output wire        uart_tx_PD,           input  wire uart_tx_IN,

    output wire        spi_select_OUT,       output wire spi_select_OE,
    output wire        spi_select_CS,        output wire spi_select_SL,
    output wire        spi_select_IE,        output wire spi_select_PU,
    output wire        spi_select_PD,        input  wire spi_select_IN,

    output wire        disp_spi_clk_out_OUT, output wire disp_spi_clk_out_OE,
    output wire        disp_spi_clk_out_CS,  output wire disp_spi_clk_out_SL,
    output wire        disp_spi_clk_out_IE,  output wire disp_spi_clk_out_PU,
    output wire        disp_spi_clk_out_PD,  input  wire disp_spi_clk_out_IN,

    output wire        spi_mosi_OUT,         output wire spi_mosi_OE,
    output wire        spi_mosi_CS,          output wire spi_mosi_SL,
    output wire        spi_mosi_IE,          output wire spi_mosi_PU,
    output wire        spi_mosi_PD,          input  wire spi_mosi_IN,

    output wire        spi_dc_OUT,           output wire spi_dc_OE,
    output wire        spi_dc_CS,            output wire spi_dc_SL,
    output wire        spi_dc_IE,            output wire spi_dc_PU,
    output wire        spi_dc_PD,            input  wire spi_dc_IN
);

    // ---- Pad configuration tie-offs (all pads) ----
    assign clk_PU = 1'b0;              assign clk_PD = 1'b0;
    assign reset_PU = 1'b0;            assign reset_PD = 1'b0;

    assign uart_rx_CS = 1'b0;   assign uart_rx_SL = 1'b0;   assign uart_rx_PU = 1'b0;   assign uart_rx_PD = 1'b0;
    assign uart_rx_OE = 1'b0;   assign uart_rx_IE = ~uart_rx_OE;
    assign uart_rx_PDRV0 = 1'b0; assign uart_rx_PDRV1 = 1'b0;
    assign uart_rx_OUT = 1'b0;  // unused, never driven out

    assign spi_miso_CS = 1'b0;  assign spi_miso_SL = 1'b0;  assign spi_miso_PU = 1'b0;  assign spi_miso_PD = 1'b0;
    assign spi_miso_OE = 1'b0;  assign spi_miso_IE = ~spi_miso_OE;
    assign spi_miso_PDRV0 = 1'b0; assign spi_miso_PDRV1 = 1'b0;
    assign spi_miso_OUT = 1'b0;

    assign spi_data0_CS = 1'b0; assign spi_data0_SL = 1'b0; assign spi_data0_PU = 1'b0; assign spi_data0_PD = 1'b0;
    assign spi_data0_IE = ~spi_data0_OE;
    assign spi_data1_CS = 1'b0; assign spi_data1_SL = 1'b0; assign spi_data1_PU = 1'b0; assign spi_data1_PD = 1'b0;
    assign spi_data1_IE = ~spi_data1_OE;
    assign spi_data2_CS = 1'b0; assign spi_data2_SL = 1'b0; assign spi_data2_PU = 1'b0; assign spi_data2_PD = 1'b0;
    assign spi_data2_IE = ~spi_data2_OE;
    assign spi_data3_CS = 1'b0; assign spi_data3_SL = 1'b0; assign spi_data3_PU = 1'b0; assign spi_data3_PD = 1'b0;
    assign spi_data3_IE = ~spi_data3_OE;

    // Output-only signals on bidirectional pads: OE permanently 1, IE permanently 0
    assign spi_clk_out_OE = 1'b1;       assign spi_clk_out_CS = 1'b0; assign spi_clk_out_SL = 1'b0;
    assign spi_clk_out_IE = 1'b0;       assign spi_clk_out_PU = 1'b0; assign spi_clk_out_PD = 1'b0;

    assign spi_flash_select_OE = 1'b1;  assign spi_flash_select_CS = 1'b0; assign spi_flash_select_SL = 1'b0;
    assign spi_flash_select_IE = 1'b0;  assign spi_flash_select_PU = 1'b0; assign spi_flash_select_PD = 1'b0;

    assign spi_ram_a_select_OE = 1'b1;  assign spi_ram_a_select_CS = 1'b0; assign spi_ram_a_select_SL = 1'b0;
    assign spi_ram_a_select_IE = 1'b0;  assign spi_ram_a_select_PU = 1'b0; assign spi_ram_a_select_PD = 1'b0;

    assign uart_tx_OE = 1'b1;           assign uart_tx_CS = 1'b0; assign uart_tx_SL = 1'b0;
    assign uart_tx_IE = 1'b0;           assign uart_tx_PU = 1'b0; assign uart_tx_PD = 1'b0;

    assign spi_select_OE = 1'b1;        assign spi_select_CS = 1'b0; assign spi_select_SL = 1'b0;
    assign spi_select_IE = 1'b0;        assign spi_select_PU = 1'b0; assign spi_select_PD = 1'b0;

    assign disp_spi_clk_out_OE = 1'b1;  assign disp_spi_clk_out_CS = 1'b0; assign disp_spi_clk_out_SL = 1'b0;
    assign disp_spi_clk_out_IE = 1'b0;  assign disp_spi_clk_out_PU = 1'b0; assign disp_spi_clk_out_PD = 1'b0;

    assign spi_mosi_OE = 1'b1;          assign spi_mosi_CS = 1'b0; assign spi_mosi_SL = 1'b0;
    assign spi_mosi_IE = 1'b0;          assign spi_mosi_PU = 1'b0; assign spi_mosi_PD = 1'b0;

    assign spi_dc_OE = 1'b1;            assign spi_dc_CS = 1'b0; assign spi_dc_SL = 1'b0;
    assign spi_dc_IE = 1'b0;            assign spi_dc_PU = 1'b0; assign spi_dc_PD = 1'b0;

    // Unused input-side signals on output-only pads (Y reads, not needed)
    wire _unused = &{1'b0,
        spi_clk_out_IN, spi_flash_select_IN, spi_ram_a_select_IN, uart_tx_IN,
        spi_select_IN, disp_spi_clk_out_IN, spi_mosi_IN, spi_dc_IN};

    // Pins compatible with gds report

    wire [3:0] spi_data_in  = {spi_data3_IN, spi_data2_IN, spi_data1_IN, spi_data0_IN};
    wire [3:0] spi_data_out;
    wire [3:0] spi_data_oe;
    assign {spi_data3_OUT, spi_data2_OUT, spi_data1_OUT, spi_data0_OUT} = spi_data_out;
    assign {spi_data3_OE,  spi_data2_OE,  spi_data1_OE,  spi_data0_OE}  = spi_data_oe;


    // Wires connecting the core to the QSPI memory controller

    wire [23:0] i_addr;
    wire        i_req;
    wire [31:0] i_rdata;
    wire        i_ready;

    wire [24:0] d_addr;
    wire        d_req;
    wire        d_we;
    wire  [3:0] d_wstrb;
    wire [31:0] d_wdata;
    wire [31:0] d_rdata;
    wire        d_ready;

    // Wires connecting the core to the UART interface

    wire [1:0]  reg_addr;
    wire [31:0] reg_wdata;
    wire        reg_we;
    wire        reg_re;
    wire [31:0] reg_rdata;
    wire        tx_irq;
    wire        rx_irq;

    // Wires connecting the core to the SPI interface

    wire [1:0]  spi_reg_addr;
    wire [31:0] spi_reg_wdata;
    wire        spi_reg_we;
    wire        spi_reg_re;
    wire [31:0] spi_reg_rdata;
    wire        spi_done;

    // PSRAM B chip-select is generated internally but not routed to a pad
    // (not part of the real 16-pin budget) -- left unconnected on purpose.
    wire        spi_ram_b_select_unused;

    // cyc_cnt/passed/failed -- simulation-only, tied off internally
    reg [31:0] cyc_cnt_unused;
    always @(posedge clk) cyc_cnt_unused <= cyc_cnt_unused + 1;

    wire        passed_unused;
    wire        failed_unused;

    // The RV32I core

    rv32i_core core_inst (
        .clk     (clk),
        .reset   (reset),
        .cyc_cnt (cyc_cnt_unused),
        .passed  (passed_unused),
        .failed  (failed_unused),

        .i_addr  (i_addr),
        .i_req   (i_req),
        .i_rdata (i_rdata),
        .i_ready (i_ready),

        .d_addr  (d_addr),
        .d_req   (d_req),
        .d_we    (d_we),
        .d_wstrb (d_wstrb),
        .d_wdata (d_wdata),
        .d_rdata (d_rdata),
        .d_ready (d_ready),

        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_rdata (reg_rdata),
        .tx_irq    (tx_irq),
        .rx_irq    (rx_irq),

        .spi_reg_addr  (spi_reg_addr),
        .spi_reg_we    (spi_reg_we),
        .spi_reg_re    (spi_reg_re),
        .spi_reg_wdata (spi_reg_wdata),
        .spi_reg_rdata (spi_reg_rdata),
        .spi_done      (spi_done)
    );


    // The QSPI memory controller (instantiates qspi_controller internally)

    rv32i_qspi_mem qspi_mem_inst (
        .clk              (clk),
        .rstn             (!reset),
        .i_addr           (i_addr),
        .i_req            (i_req),
        .i_rdata          (i_rdata),
        .i_ready          (i_ready),
        .d_addr           (d_addr),
        .d_req            (d_req),
        .d_we             (d_we),
        .d_wstrb          (d_wstrb),
        .d_wdata          (d_wdata),
        .d_rdata          (d_rdata),
        .d_ready          (d_ready),
        .spi_data_in      (spi_data_in),
        .spi_data_out     (spi_data_out),
        .spi_data_oe      (spi_data_oe),
        .spi_clk_out      (spi_clk_out_OUT),
        .spi_flash_select (spi_flash_select_OUT),
        .spi_ram_a_select (spi_ram_a_select_OUT),
        .spi_ram_b_select (spi_ram_b_select_unused)
    );

    // The UART interface

    uart_riscv_if uart_inst (
        .clk       (clk),
        .resetn    (!reset),

        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_rdata (reg_rdata),

        .uart_tx   (uart_tx_OUT),
        .uart_rx   (uart_rx_IN),

        .tx_irq    (tx_irq),
        .rx_irq    (rx_irq)
    );

    // The SPI interface

    spi_riscv_if spi_inst (
        .clk       (clk),
        .resetn    (!reset),

        .reg_addr  (spi_reg_addr),
        .reg_wdata (spi_reg_wdata),
        .reg_we    (spi_reg_we),
        .reg_re    (spi_reg_re),
        .reg_rdata (spi_reg_rdata),

        .spi_miso    (spi_miso_IN),
        .spi_select  (spi_select_OUT),
        .spi_clk_out (disp_spi_clk_out_OUT),
        .spi_mosi    (spi_mosi_OUT),
        .spi_dc      (spi_dc_OUT),

        .spi_done    (spi_done)
    );

endmodule

`default_nettype wire