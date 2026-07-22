/* Copyright 2024
   SPDX-License-Identifier: Apache-2.0

   tb_rv32i_qspi — Testbench for rv32i_qspi_mem
   Instantiates the DUT and the sim_qspi_pmod memory model.
*/
`default_nettype none
`timescale 1ns / 100ps

module tb_rv32i_qspi ();

    // ── Clock / reset ──────────────────────────────────────────────────────
    reg clk;
    reg rstn;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // ── DUT ports ──────────────────────────────────────────────────────────
    reg  [23:0] i_addr;
    reg         i_req;
    wire [31:0] i_rdata;
    wire        i_ready;

    reg  [24:0] d_addr;
    reg         d_req;
    reg         d_we;
    reg  [3:0]  d_wstrb;
    reg  [31:0] d_wdata;
    wire [31:0] d_rdata;
    wire        d_ready;

    // ── QSPI bus ────────────────────────────────────────────────────────────
    wire [3:0] spi_data_out;
    wire [3:0] spi_data_oe;
    wire       spi_clk_out;
    wire       spi_flash_select;
    wire       spi_ram_a_select;
    wire       spi_ram_b_select;

    // PMOD model output (buffered to simulate propagation)
    wire [3:0] pmod_data_out;

    // During reset, drive spi_data_in[1:0] = 2'b01 to configure
    // qspi_controller delay_cycles_cfg = 1 (one read-delay cycle, no neg-clk).
    // After reset, connect the PMOD model's output.
    wire [3:0] spi_data_in = rstn ? pmod_data_out : 4'b0001;

    // ── DUT instantiation ──────────────────────────────────────────────────
    rv32i_qspi_mem dut (
        .clk             (clk),
        .rstn            (rstn),
        .i_addr          (i_addr),
        .i_req           (i_req),
        .i_rdata         (i_rdata),
        .i_ready         (i_ready),
        .d_addr          (d_addr),
        .d_req           (d_req),
        .d_we            (d_we),
        .d_wstrb         (d_wstrb),
        .d_wdata         (d_wdata),
        .d_rdata         (d_rdata),
        .d_ready         (d_ready),
        .spi_data_in     (spi_data_in),
        .spi_data_out    (spi_data_out),
        .spi_data_oe     (spi_data_oe),
        .spi_clk_out     (spi_clk_out),
        .spi_flash_select(spi_flash_select),
        .spi_ram_a_select(spi_ram_a_select),
        .spi_ram_b_select(spi_ram_b_select)
    );

    // ── QSPI PMOD model ────────────────────────────────────────────────────
    // Only data driven by the DUT reaches the PMOD (masked by output-enable).
    sim_qspi_pmod pmod (
        .qspi_data_in    (spi_data_out & spi_data_oe),
        .qspi_data_out   (pmod_data_out),
        .qspi_clk        (spi_clk_out),
        .qspi_flash_select(spi_flash_select),
        .qspi_ram_a_select(spi_ram_a_select),
        .qspi_ram_b_select(spi_ram_b_select),
        .debug_clk       (1'b0),
        .debug_addr      (25'd0)
    );

    // Pre-load ROM with known test pattern via INIT_FILE
    defparam pmod.INIT_FILE = `INIT_FILE;

endmodule
`default_nettype wire
