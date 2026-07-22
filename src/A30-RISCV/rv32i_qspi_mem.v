// rv32i_qspi_mem.v
// CPU-facing QSPI memory wrapper — extracted verbatim from the combined
// Makerchip file, now a standalone module for external instantiation.
// Instantiates qspi_controller internally (must be compiled alongside
// qspi_controller.v).
// Source: silicon-vlsi/tt10-tinyQV repository.

module rv32i_qspi_mem (
    input  wire        clk,
    input  wire        rstn,
    input  wire [23:0] i_addr,
    input  wire        i_req,
    output wire [31:0] i_rdata,
    output reg         i_ready,
    input  wire [24:0] d_addr,
    input  wire        d_req,
    input  wire        d_we,
    input  wire  [3:0] d_wstrb,
    input  wire [31:0] d_wdata,
    output wire [31:0] d_rdata,
    output reg         d_ready,
    input  wire  [3:0] spi_data_in,
    output wire  [3:0] spi_data_out,
    output wire  [3:0] spi_data_oe,
    output wire        spi_clk_out,
    output wire        spi_flash_select,
    output wire        spi_ram_a_select,
    output wire        spi_ram_b_select
);
    localparam ST_IDLE       = 2'd0;
    localparam ST_INSTR_WAIT = 2'd1;
    localparam ST_DATA_WAIT  = 2'd2;
    reg [1:0] state;
    reg [2:0] byte_cnt;
    reg [2:0] byte_total;
    reg [1:0] first_byte;
    reg       op_is_write;
    reg [31:0] i_rdata_r;
    reg [31:0] d_rdata_r;
    assign i_rdata = i_rdata_r;
    assign d_rdata = d_rdata_r;
    wire [7:0] qspi_dout;
    wire       qspi_data_req;
    wire       qspi_data_ready;
    wire       qspi_busy;
    reg  [24:0] qspi_addr;
    reg  [7:0]  qspi_din;
    reg         qspi_start_read;
    reg         qspi_start_write;
    reg         qspi_stop;
    wire [1:0] d_first_byte =
        d_wstrb[0] ? 2'd0 :
        d_wstrb[1] ? 2'd1 :
        d_wstrb[2] ? 2'd2 : 2'd3;
/* verilator lint_off WIDTH */
    wire [2:0] d_byte_count = {2'd0, d_wstrb[0]} + {2'd0, d_wstrb[1]}
                            + {2'd0, d_wstrb[2]} + {2'd0, d_wstrb[3]};
/* verilator lint_on WIDTH */
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
    wire [1:0] wr_ptr = first_byte + byte_cnt[1:0]
                        + (qspi_data_req ? 2'd1 : 2'd0);
    always @(*) begin
        qspi_start_read  = 1'b0;
        qspi_start_write = 1'b0;
        qspi_stop        = 1'b0;
        qspi_addr        = 25'd0;
        qspi_din         = 8'hFF;
        case (state)
            ST_IDLE: begin
                if (data_can_start) begin
                    qspi_addr        = d_addr + {3'd0, d_first_byte};
                    qspi_start_read  = ~d_we;
                    qspi_start_write =  d_we;
                end else if (i_req && !qspi_busy) begin
                    qspi_addr       = {1'b0, i_addr};
                    qspi_start_read = 1'b1;
                end
            end
            ST_INSTR_WAIT: begin
                if (qspi_data_ready && (byte_cnt == byte_total - 3'd1))
                    qspi_stop = 1'b1;
            end
            ST_DATA_WAIT: begin
                if (op_is_write) begin
                    qspi_din = d_wdata[{wr_ptr, 3'b000} +: 8];
                    if (qspi_data_req && (byte_cnt == byte_total - 3'd1))
                        qspi_stop = 1'b1;
                end else begin
                    if (qspi_data_ready && (byte_cnt == byte_total - 3'd1))
                        qspi_stop = 1'b1;
                end
            end
            default: ;
        endcase
    end
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
            i_ready            <= 1'b0;
            d_write_completing <= 1'b0;
            d_ready <= d_write_completing;
            case (state)
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
                        byte_total  <= 3'd4;
                        op_is_write <= 1'b0;
                    end
                end
                ST_INSTR_WAIT: begin
                    if (qspi_data_ready) begin
                        i_rdata_r[{byte_cnt[1:0], 3'b000} +: 8] <= qspi_dout;
                        if (byte_cnt == byte_total - 3'd1) begin
                            state   <= ST_IDLE;
                            i_ready <= 1'b1;
                        end else
                            byte_cnt <= byte_cnt + 3'd1;
                    end
                end
                ST_DATA_WAIT: begin
                    if (!op_is_write) begin
                        if (qspi_data_ready) begin
                            d_rdata_r[{byte_cnt[1:0], 3'b000} +: 8] <= qspi_dout;
                            if (byte_cnt == byte_total - 3'd1) begin
                                state   <= ST_IDLE;
                                d_ready <= 1'b1;
                            end else
                                byte_cnt <= byte_cnt + 3'd1;
                        end
                    end else begin
                        if (qspi_data_req) begin
                            if (byte_cnt == byte_total - 3'd1) begin
                                state              <= ST_IDLE;
                                d_write_completing <= 1'b1;
                            end else
                                byte_cnt <= byte_cnt + 3'd1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
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
