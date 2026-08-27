/* Testbench for qspi_chip_top (core + QSPI controller, no memory model
   inside). This testbench instantiates qspi_chip_top AND sim_qspi_pmod
   as two separate modules, and wires them together itself —
   mirroring exactly how the real tb_rv32i_qspi.v wires rv32i_qspi_mem
   and sim_qspi_pmod together).
*/
`default_nettype none
`timescale 1ns / 100ps

module tb_qspi_chip_top ();

// Waveform dump for GTKWave
initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_qspi_chip_top);
end

    //  Clock / reset 
    reg clk;
    reg reset;
    reg [31:0] cyc_cnt;
    wire passed, failed;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz
    always @(posedge clk) cyc_cnt <= cyc_cnt + 1;

    //  QSPI bus, between qspi_chip_top and sim_qspi_pmod 

    wire [3:0] spi_data_out;
    wire [3:0] spi_data_oe;
    wire       spi_clk_out;
    wire       spi_flash_select;
    wire       spi_ram_a_select;
    //wire       spi_ram_b_select;
    wire       spi_ram_b_select = 1'b1;  // permanently deselected -- PSRAM B unused

    wire [3:0] pmod_data_out;

    
    wire [3:0] spi_data_in = reset ? 4'b0001 : pmod_data_out;

    wire uart_tx;
    reg  uart_rx;

       // SPI peripheral pins (display SPI)

    wire spi_select;
    wire disp_spi_clk_out;
    wire spi_mosi;
    wire spi_dc;
    reg  spi_miso;

    // Chip-level top: core + QSPI controller 
    qspi_chip_top chip_inst (
        .clk              (clk),
        .reset            (reset),
       // .cyc_cnt          (cyc_cnt),
       // .passed           (passed),
       // .failed           (failed),
        .spi_data0_IN     (spi_data_in[0]),
        .spi_data1_IN     (spi_data_in[1]),
        .spi_data2_IN     (spi_data_in[2]),
        .spi_data3_IN     (spi_data_in[3]),
        .spi_data0_OUT    (spi_data_out[0]),
        .spi_data1_OUT    (spi_data_out[1]),
        .spi_data2_OUT    (spi_data_out[2]),
        .spi_data3_OUT    (spi_data_out[3]),
        .spi_data0_OE     (spi_data_oe[0]),
        .spi_data1_OE     (spi_data_oe[1]),
        .spi_data2_OE     (spi_data_oe[2]),
        .spi_data3_OE     (spi_data_oe[3]),
        .spi_clk_out      (spi_clk_out),
        .spi_flash_select (spi_flash_select),
        .spi_ram_a_select (spi_ram_a_select),
       // .spi_ram_b_select (spi_ram_b_select),
        .uart_tx          (uart_tx),
        .uart_rx          (uart_rx),
        .spi_miso         (spi_miso),
        .spi_select       (spi_select),
        .disp_spi_clk_out (disp_spi_clk_out),
        .spi_mosi         (spi_mosi),
        .spi_dc           (spi_dc)
    );

    // ── Simulated flash + PSRAM A + PSRAM B — ONLY instantiated here

    sim_qspi_pmod pmod (
        
        .qspi_data_in      (spi_data_out & spi_data_oe),
        .qspi_data_out     (pmod_data_out),
        .qspi_clk          (spi_clk_out),
        .qspi_flash_select (spi_flash_select),
        .qspi_ram_a_select (spi_ram_a_select),
        .qspi_ram_b_select (spi_ram_b_select),
        .debug_clk         (1'b0),
        .debug_addr        (25'd0)
    );

    // Pre-load ROM with the test program via INIT_FILE 
    
    defparam pmod.INIT_FILE = `INIT_FILE;

    // Release reset on a NEGEDGE, 10 cycles in - avoids racing with the
    // design's own posedge-triggered logic.
    
    initial begin
        reset = 1;
    end
    initial begin
        repeat (10) @(negedge clk);
        reset = 0;
    end
initial begin
    uart_rx = 1'b1;  // idle-high before any transmission starts
end
initial begin
    spi_miso = 1'b0;  // defined idle value before any transfer starts
end

endmodule
`default_nettype wire
