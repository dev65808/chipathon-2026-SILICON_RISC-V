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
    output wire        spi_ram_b_select
);

    
    // Wires connecting the core to the QSPI memory controller
    
    wire [23:0] i_addr_w;
    wire        i_req_w;
    wire [31:0] i_rdata_w;
    wire        i_ready_w;

    wire [24:0] d_addr_w;
    wire        d_req_w;
    wire        d_we_w;
    wire  [3:0] d_wstrb_w;
    wire [31:0] d_wdata_w;
    wire [31:0] d_rdata_w;
    wire        d_ready_w;

   
    // The RV32I core
    
    rv32i_core core_inst (
        .clk     (clk),
        .reset   (reset),
        .cyc_cnt (cyc_cnt),
        .passed  (passed),
        .failed  (failed),

        .i_addr  (i_addr_w),
        .i_req   (i_req_w),
        .i_rdata (i_rdata_w),
        .i_ready (i_ready_w),

        .d_addr  (d_addr_w),
        .d_req   (d_req_w),
        .d_we    (d_we_w),
        .d_wstrb (d_wstrb_w),
        .d_wdata (d_wdata_w),
        .d_rdata (d_rdata_w),
        .d_ready (d_ready_w)
    );

    
    // The QSPI memory controller (instantiates qspi_controller internally)
    
    rv32i_qspi_mem qspi_mem_inst (
        .clk              (clk),
        .rstn             (!reset),
        .i_addr           (i_addr_w),
        .i_req            (i_req_w),
        .i_rdata          (i_rdata_w),
        .i_ready          (i_ready_w),
        .d_addr           (d_addr_w),
        .d_req            (d_req_w),
        .d_we             (d_we_w),
        .d_wstrb          (d_wstrb_w),
        .d_wdata          (d_wdata_w),
        .d_rdata          (d_rdata_w),
        .d_ready          (d_ready_w),
        .spi_data_in      (spi_data_in),
        .spi_data_out     (spi_data_out),
        .spi_data_oe      (spi_data_oe),
        .spi_clk_out      (spi_clk_out),
        .spi_flash_select (spi_flash_select),
        .spi_ram_a_select (spi_ram_a_select),
        .spi_ram_b_select (spi_ram_b_select)
    );

endmodule
