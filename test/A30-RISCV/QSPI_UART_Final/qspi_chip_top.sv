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

module qspi_chip_top (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] cyc_cnt,
    output wire         passed,
    output wire         failed,

    // The physical QSPI bus — connects to an external flash/PSRAM chip
    // (or, in simulation, to sim_qspi_pmod instantiated in the testbench).

    input  wire  [3:0] spi_data_in,
    output wire  [3:0] spi_data_out,
    output wire  [3:0] spi_data_oe,
    output wire        spi_clk_out,
    output wire        spi_flash_select,
    output wire        spi_ram_a_select,
    output wire        spi_ram_b_select,

     // new // UART serial pins — external chip pins
    output wire        uart_tx,
    input  wire        uart_rx
);


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


    // The RV32I core

    rv32i_core core_inst (
        .clk     (clk),
        .reset   (reset),
        .cyc_cnt (cyc_cnt),
        .passed  (passed),
        .failed  (failed),

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

        //new for uart

        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_rdata (reg_rdata),
        .tx_irq    (tx_irq),
        .rx_irq    (rx_irq)


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
        .spi_clk_out      (spi_clk_out),
        .spi_flash_select (spi_flash_select),
        .spi_ram_a_select (spi_ram_a_select),
        .spi_ram_b_select (spi_ram_b_select)
    );

    // new // The UART interface

    uart_riscv_if uart_inst (
        .clk       (clk),
        .resetn    (!reset),

        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_rdata (reg_rdata),

        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx),

        .tx_irq    (tx_irq),
        .rx_irq    (rx_irq)
    );

endmodule