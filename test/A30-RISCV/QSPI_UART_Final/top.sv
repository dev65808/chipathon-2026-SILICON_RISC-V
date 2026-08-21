`line 2 "top.tlv" 0
//_\SV
   // Included URL: "https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv"// Included URL: "https://raw.githubusercontent.com/stevehoover/warp-v_includes/1d1023ccf8e7b0a8cf8e8fc4f0a823ebb61008e3/risc-v_defs.tlv"
   // Inst #0: BGE,x0,x0,0
   `define READONLY_MEM(ADDR, DATA) logic [31:0] instrs [0:1-1]; assign DATA = instrs[ADDR[$clog2($size(instrs)) + 1 : 2]]; assign instrs = '{{1'b0, 6'b000000, 5'd0, 5'd0, 3'b101, 4'b0000, 1'b0, 7'b1100011}};
   
   //---------------------------------------------------------------------------------
//_\SV
   // Layer 1 — definitions only, nothing instantiated here. rv32i_qspi_mem
   // and uart_riscv_if both get instantiated externally, in qspi_chip_top.sv.
   `include "qspi_controller.v"
   `include "rv32i_qspi_mem.v"
   `include "uart_riscv_if.v"
//_\SV
   module top(input wire clk, input wire reset, input wire [31:0] cyc_cnt, output wire passed, output wire failed);    /* verilator lint_save */ /* verilator lint_off UNOPTFLAT */  bit [256:0] RW_rand_raw; bit [256+63:0] RW_rand_vect; pseudo_rand #(.WIDTH(257)) pseudo_rand (clk, reset, RW_rand_raw[256:0]); assign RW_rand_vect[256+63:0] = {RW_rand_raw[62:0], RW_rand_raw};  /* verilator lint_restore */  /* verilator lint_off WIDTH */ /* verilator lint_off UNOPTFLAT */
//_\SV
   // Layer 2 — intentionally empty. mem_i_rdata / mem_i_ready /
   // mem_d_rdata / mem_d_ready (QSPI) and reg_rdata / tx_irq / rx_irq
   // (UART) are all supplied externally, by rv32i_core.sv, before it
   // `include`s the compiled output of this file's \TLV block.
`include "top_gen.sv" //_\TLV
   // ================================================================
   // Core logic. Decode/ALU/branch/register-file sections are UNCHANGED
   // from the verified QSPI-only core. Everything marked NEW below is
   // the FSM extension + UART wiring.
   // ================================================================

   assign L0_reset_a0 = reset;
   assign L0_start_a0 = !L0_reset_a0;                              // NEW — IDLE waits for this before leaving reset

   // ----------------------------------------------------------------
   // MEMORY-ACCESS FSM — 10 states now (was 4). $state widened 2->4 bits.
   // IDLE=0, FETCH_REQ=1, FETCH_WAIT=2, DATA_MEM_READ=3, DATA_MEM_WRITE=4,
   // DATA_MEM_WAIT=5, UART_READ=6, UART_READ_BUSY=7, UART_WRITE=8,
   // UART_WRITE_BUSY=9
   // ----------------------------------------------------------------
   assign L0_state_a0[3:0] = L0_reset_a0 ? 4'd0 : (L0_reset_a1 ? 4'd0 : L0_next_state_a1);   // CHANGED — targets IDLE, not old FETCH encoding

   assign L0_next_state_a0[3:0] =                                                   // CHANGED — full rewrite for 10 states
      (L0_state_a0 == 4'd0) ? (L0_start_a0 ? 4'd1 : 4'd0) :                                  // IDLE: wait for $start
      (L0_state_a0 == 4'd1) ? 4'd2 :                                                    // FETCH_REQ: unconditional
      (L0_state_a0 == 4'd2) ? (!mem_i_ready                       ? 4'd2 :              // FETCH_WAIT: wait for i_ready
                           (L0_is_load_a0  && L0_peri_sel_a0==2'b00)    ? 4'd3 :              //   load + QSPI  -> DATA_MEM_READ
                           (L0_is_store_a0 && L0_peri_sel_a0==2'b00)    ? 4'd4 :              //   store + QSPI -> DATA_MEM_WRITE
                           (L0_is_load_a0  && L0_peri_sel_a0==2'b01)    ? 4'd6 :              //   load + UART  -> UART_READ
                           (L0_is_store_a0 && L0_peri_sel_a0==2'b01)    ? 4'd8 :              //   store + UART -> UART_WRITE
                                                                 4'd1) :            //   neither       -> FETCH_REQ
      (L0_state_a0 == 4'd3) ? 4'd5 :                                                    // DATA_MEM_READ -> DATA_MEM_WAIT
      (L0_state_a0 == 4'd4) ? 4'd5 :                                                    // DATA_MEM_WRITE -> DATA_MEM_WAIT
      (L0_state_a0 == 4'd5) ? (mem_d_ready ? 4'd1 : 4'd5) :                             // DATA_MEM_WAIT: wait for d_ready
      (L0_state_a0 == 4'd6) ? 4'd7 :                                                    // FIXED — UART_READ: unconditional (reg_rdata is combinational; waiting on rx_irq here deadlocked STATUS/CTRL/BAUD_DIV reads)
      (L0_state_a0 == 4'd7) ? 4'd1 :                                                    // UART_READ_BUSY: unconditional
      (L0_state_a0 == 4'd8) ? 4'd9 :                                                    // FIXED — UART_WRITE: unconditional (waiting on tx_irq here deadlocked CTRL, since tx_irq depends on CTRL being written first)
      (L0_state_a0 == 4'd9) ? (tx_irq ? 4'd1 : 4'd9) :                                  // UART_WRITE_BUSY: wait for tx_irq high again
                          4'd0;

   assign L0_i_req_a0 = (L0_state_a0 == 4'd1) && !L0_reset_a0;                                // CHANGED — FETCH_REQ is now state 1
   assign L0_d_req_a0 = ((L0_state_a0 == 4'd3) || (L0_state_a0 == 4'd4)) && !L0_reset_a0;          // CHANGED — covers both QSPI read AND write states now

   assign L0_instr_a0[31:0] = L0_reset_a0 ? 32'b0 :
                  ((L0_state_a0 == 4'd2) && mem_i_ready) ? mem_i_rdata :      // CHANGED — FETCH_WAIT is now state 2
                  L0_instr_a1;

   assign L0_is_mem_op_a0 = L0_is_load_a0 || L0_is_store_a0;

   assign L0_commit_a0 = ((L0_state_a0 == 4'd2) && mem_i_ready && !L0_is_mem_op_a0) ||        // non-mem instr done in FETCH_WAIT
             ((L0_state_a0 == 4'd5) && mem_d_ready)                  ||      // QSPI load/store done in DATA_MEM_WAIT
             (L0_state_a0 == 4'd7)                                   ||      // NEW — UART read done in UART_READ_BUSY
             ((L0_state_a0 == 4'd9) && tx_irq);                              // NEW — UART write done in UART_WRITE_BUSY

   assign L0_pc_a0[31:0] = L0_reset_a0 ? 32'b0 :
               (L0_reset_a1 ? 32'b0 :
               (L0_commit_a1 ? L0_next_pc_a1 : L0_pc_a1));

   assign L0_next_pc_a0[31:0] = L0_is_trap_a0 ? L0_pc_a0 :
                           L0_taken_br_a0 ? L0_br_tgt_pc_a0 :
                           L0_is_jal_a0  ? L0_br_tgt_pc_a0 :
                           L0_is_jalr_a0 ? L0_jalr_tgt_pc_a0 :
                                      (L0_pc_a0 + 32'd4);

   assign L0_i_addr_a0[23:0] = L0_pc_a0[23:0];

   // ---- DECODE (unchanged) ----
   assign L0_is_u_instr_a0 = L0_instr_a0[6:2] ==? 5'b0x101;
   assign L0_is_i_instr_a0 = L0_instr_a0[6:2] ==? 5'b0000x ||
                 L0_instr_a0[6:2] ==? 5'b001x0 ||
                 L0_instr_a0[6:2] ==? 5'b11001;
   assign L0_is_r_instr_a0 = L0_instr_a0[6:2] ==? 5'b011x0;
   assign L0_is_s_instr_a0 = L0_instr_a0[6:2] ==? 5'b0100x;
   assign L0_is_b_instr_a0 = L0_instr_a0[6:2] ==? 5'b11000;
   assign L0_is_j_instr_a0 = L0_instr_a0[6:2] ==? 5'b11011;

   assign L0_opcode_a0[6:0] = L0_instr_a0[6:0];
   assign L0_rd_a0[4:0] = L0_instr_a0[11:7];
   assign L0_funct3_a0[2:0] = L0_instr_a0[14:12];
   assign L0_rs1_a0[4:0] = L0_instr_a0[19:15];
   assign L0_rs2_a0[4:0] = L0_instr_a0[24:20];

   assign L0_rd_valid_a0 = L0_is_r_instr_a0 || L0_is_i_instr_a0 || L0_is_u_instr_a0 || L0_is_j_instr_a0 || L0_is_csr_a0;
   assign L0_funct3_valid_a0 = L0_is_r_instr_a0 || L0_is_i_instr_a0 || L0_is_s_instr_a0 || L0_is_b_instr_a0;
   assign L0_rs1_valid_a0 = L0_is_r_instr_a0 || L0_is_i_instr_a0 || L0_is_s_instr_a0 || L0_is_b_instr_a0 || L0_is_csr_a0;
   assign L0_rs2_valid_a0 = L0_is_r_instr_a0 || L0_is_s_instr_a0 || L0_is_b_instr_a0;
   assign L0_imm_valid_a0 = L0_is_i_instr_a0 || L0_is_s_instr_a0 || L0_is_b_instr_a0 || L0_is_u_instr_a0 || L0_is_j_instr_a0;

   assign L0_imm_a0[31:0] = L0_is_i_instr_a0 ? {{21{L0_instr_a0[31]}}, L0_instr_a0[30:20]} :
                L0_is_s_instr_a0 ? {{21{L0_instr_a0[31]}}, L0_instr_a0[30:25], L0_instr_a0[11:7]} :   // FIXED — was backwards (instr[11:7] and instr[30:25] swapped), invisible with offset 0
                L0_is_b_instr_a0 ? {{20{L0_instr_a0[31]}}, L0_instr_a0[7], L0_instr_a0[30:25], L0_instr_a0[11:8], 1'b0} :
                L0_is_u_instr_a0 ? {L0_instr_a0[31], L0_instr_a0[30:12], 12'b0} :
                L0_is_j_instr_a0 ? {{12{L0_instr_a0[31]}}, L0_instr_a0[19:12], L0_instr_a0[20], L0_instr_a0[30:21], 1'b0} :
                32'b0;

   assign L0_dec_bits_a0[10:0] = {L0_instr_a0[30], L0_funct3_a0, L0_opcode_a0};
   assign L0_is_addi_a0 = L0_dec_bits_a0 ==? 11'bx_000_0010011;
   assign L0_is_add_a0  = L0_dec_bits_a0 ==? 11'b0_000_0110011;
   assign L0_is_beq_a0  = L0_dec_bits_a0 ==? 11'bx_000_1100011;
   assign L0_is_bne_a0  = L0_dec_bits_a0 ==? 11'bx_001_1100011;
   assign L0_is_blt_a0  = L0_dec_bits_a0 ==? 11'bx_100_1100011;
   assign L0_is_bge_a0  = L0_dec_bits_a0 ==? 11'bx_101_1100011;
   assign L0_is_bltu_a0 = L0_dec_bits_a0 ==? 11'bx_110_1100011;
   assign L0_is_bgeu_a0 = L0_dec_bits_a0 ==? 11'bx_111_1100011;

   assign L0_is_sub_a0  = L0_dec_bits_a0 ==? 11'b1_000_0110011;
   assign L0_is_sll_a0  = L0_dec_bits_a0 ==? 11'b0_001_0110011;
   assign L0_is_slt_a0  = L0_dec_bits_a0 ==? 11'b0_010_0110011;
   assign L0_is_sltu_a0 = L0_dec_bits_a0 ==? 11'b0_011_0110011;
   assign L0_is_xor_a0  = L0_dec_bits_a0 ==? 11'b0_100_0110011;
   assign L0_is_srl_a0  = L0_dec_bits_a0 ==? 11'b0_101_0110011;
   assign L0_is_sra_a0  = L0_dec_bits_a0 ==? 11'b1_101_0110011;
   assign L0_is_or_a0   = L0_dec_bits_a0 ==? 11'b0_110_0110011;
   assign L0_is_and_a0  = L0_dec_bits_a0 ==? 11'b0_111_0110011;

   assign L0_is_slti_a0  = L0_dec_bits_a0 ==? 11'bx_010_0010011;
   assign L0_is_sltiu_a0 = L0_dec_bits_a0 ==? 11'bx_011_0010011;
   assign L0_is_xori_a0  = L0_dec_bits_a0 ==? 11'bx_100_0010011;
   assign L0_is_ori_a0   = L0_dec_bits_a0 ==? 11'bx_110_0010011;
   assign L0_is_andi_a0  = L0_dec_bits_a0 ==? 11'bx_111_0010011;
   assign L0_is_slli_a0  = L0_dec_bits_a0 ==? 11'b0_001_0010011;
   assign L0_is_srli_a0  = L0_dec_bits_a0 ==? 11'b0_101_0010011;
   assign L0_is_srai_a0  = L0_dec_bits_a0 ==? 11'b1_101_0010011;

   assign L0_is_lb_a0  = L0_dec_bits_a0 ==? 11'bx_000_0000011;
   assign L0_is_lh_a0  = L0_dec_bits_a0 ==? 11'bx_001_0000011;
   assign L0_is_lw_a0  = L0_dec_bits_a0 ==? 11'bx_010_0000011;
   assign L0_is_lbu_a0 = L0_dec_bits_a0 ==? 11'bx_100_0000011;
   assign L0_is_lhu_a0 = L0_dec_bits_a0 ==? 11'bx_101_0000011;
   assign L0_is_load_a0 = L0_is_lb_a0 || L0_is_lh_a0 || L0_is_lw_a0 || L0_is_lbu_a0 || L0_is_lhu_a0;

   assign L0_is_sb_a0 = L0_dec_bits_a0 ==? 11'bx_000_0100011;
   assign L0_is_sh_a0 = L0_dec_bits_a0 ==? 11'bx_001_0100011;
   assign L0_is_sw_a0 = L0_dec_bits_a0 ==? 11'bx_010_0100011;
   assign L0_is_store_a0 = L0_is_sb_a0 || L0_is_sh_a0 || L0_is_sw_a0;

   assign L0_is_lui_a0   = L0_opcode_a0 ==? 7'b0110111;
   assign L0_is_auipc_a0 = L0_opcode_a0 ==? 7'b0010111;

   assign L0_is_jal_a0  = L0_opcode_a0 ==? 7'b1101111;
   assign L0_is_jalr_a0 = (L0_opcode_a0 ==? 7'b1100111) && (L0_funct3_a0 == 3'b000);
   assign L0_jalr_tgt_pc_a0[31:0] = (L0_src1_value_a0 + L0_imm_a0) & 32'hFFFFFFFE;

   assign L0_is_system_a0 = L0_opcode_a0 ==? 7'b1110011;
   assign L0_is_ecall_a0  = L0_is_system_a0 && (L0_funct3_a0==3'b000) && (L0_instr_a0[31:20]==12'b0);
   assign L0_is_ebreak_a0 = L0_is_system_a0 && (L0_funct3_a0==3'b000) && (L0_instr_a0[31:20]==12'b1);
   assign L0_is_csrrw_a0  = L0_is_system_a0 && (L0_funct3_a0==3'b001);
   assign L0_is_csrrs_a0  = L0_is_system_a0 && (L0_funct3_a0==3'b010);
   assign L0_is_csrrc_a0  = L0_is_system_a0 && (L0_funct3_a0==3'b011);
   assign L0_is_csrrwi_a0 = L0_is_system_a0 && (L0_funct3_a0==3'b101);
   assign L0_is_csrrsi_a0 = L0_is_system_a0 && (L0_funct3_a0==3'b110);
   assign L0_is_csrrci_a0 = L0_is_system_a0 && (L0_funct3_a0==3'b111);
   assign L0_is_csr_a0    = L0_is_csrrw_a0 || L0_is_csrrs_a0 || L0_is_csrrc_a0 || L0_is_csrrwi_a0 || L0_is_csrrsi_a0 || L0_is_csrrci_a0;
   assign L0_is_fence_a0  = L0_opcode_a0 ==? 7'b0001111;
   assign L0_is_trap_a0   = L0_is_ecall_a0 || L0_is_ebreak_a0;

   assign L0_csr_addr_a0[4:0] = L0_instr_a0[24:20];
   assign L0_csr_operand_a0[31:0] = (L0_is_csrrwi_a0 || L0_is_csrrsi_a0 || L0_is_csrrci_a0) ? {27'b0, L0_rs1_a0[4:0]} : L0_src1_value_a0;
   assign L0_csr_new_value_a0[31:0] = (L0_is_csrrw_a0 || L0_is_csrrwi_a0) ? L0_csr_operand_a0 :
                           (L0_is_csrrs_a0 || L0_is_csrrsi_a0) ? (L0_csr_old_value_a0 | L0_csr_operand_a0) :
                                                        (L0_csr_old_value_a0 & ~L0_csr_operand_a0);

   // ---- QSPI data-side wiring (unchanged — $d_addr stays 25 bits) ----
   assign L0_ld_st_addr_a0[31:0] = L0_src1_value_a0 + L0_imm_a0;
   assign L0_byte_offset_a0[1:0] = L0_ld_st_addr_a0[1:0];

   assign L0_d_addr_a0[24:0] = L0_ld_st_addr_a0[24:0];
   assign L0_d_we_a0 = L0_is_store_a0;

   assign L0_d_wstrb_a0[3:0] =
      (L0_is_lb_a0 || L0_is_lbu_a0 || L0_is_sb_a0) ? (4'b0001 << L0_byte_offset_a0) :
      (L0_is_lh_a0 || L0_is_lhu_a0 || L0_is_sh_a0) ? (4'b0011 << {L0_byte_offset_a0[1], 1'b0}) :
      (L0_is_lw_a0 || L0_is_sw_a0)            ? 4'b1111 :
                                       4'b0000;

   assign L0_d_wdata_a0[31:0] = L0_is_sb_a0 ? {4{L0_src2_value_a0[7:0]}} :
                     L0_is_sh_a0 ? {2{L0_src2_value_a0[15:0]}} :
                              L0_src2_value_a0;

   // ---- UART wiring — NEW ----
   // $ld_st_addr is already a full 32-bit sum, so we can slice the
   // device-select bits straight from it without touching $d_addr at all
   // (rv32i_qspi_mem's d_addr port is fixed at 25 bits, so widening
   // $d_addr itself would create a port-width mismatch).
   assign L0_peri_sel_a0[1:0]  = L0_ld_st_addr_a0[27:26];             // NEW — 00=QSPI, 01=UART
   assign L0_reg_addr_a0[1:0]  = L0_ld_st_addr_a0[3:2];                // NEW — selects DATA/STATUS/CTRL/BAUD_DIV
   assign L0_reg_we_a0         = (L0_state_a0 == 4'd8);                // FIXED — pulses for the one cycle spent in UART_WRITE (no tx_irq gate, or CTRL could never be written to enable tx_irq in the first place)
   assign L0_reg_re_a0         = (L0_state_a0 == 4'd6);                // FIXED — pulses for the one cycle spent in UART_READ (no rx_irq gate — reg_rdata is combinational, STATUS/CTRL/BAUD_DIV need no wait)
   assign L0_reg_wdata_a0[31:0] = L0_src2_value_a0;                    // NEW — same source as a QSPI store's $d_wdata

   // ALU
   assign L0_result_a0[31:0] = L0_is_addi_a0 ? L0_src1_value_a0 + L0_imm_a0 :
                   L0_is_add_a0  ? L0_src1_value_a0 + L0_src2_value_a0 :
                   L0_is_sub_a0  ? L0_src1_value_a0 - L0_src2_value_a0 :
                   L0_is_sll_a0  ? L0_src1_value_a0 << L0_src2_value_a0[4:0] :
                   L0_is_slt_a0  ? {31'b0, (L0_src1_value_a0[31] != L0_src2_value_a0[31]) ? L0_src1_value_a0[31] : (L0_src1_value_a0 < L0_src2_value_a0)} :
                   L0_is_sltu_a0 ? {31'b0, L0_src1_value_a0 < L0_src2_value_a0} :
                   L0_is_xor_a0  ? L0_src1_value_a0 ^ L0_src2_value_a0 :
                   L0_is_srl_a0  ? L0_src1_value_a0 >> L0_src2_value_a0[4:0] :
                   L0_is_sra_a0  ? (L0_src1_value_a0[31] ? ~((~L0_src1_value_a0) >> L0_src2_value_a0[4:0]) : (L0_src1_value_a0 >> L0_src2_value_a0[4:0])) :
                   L0_is_or_a0   ? L0_src1_value_a0 | L0_src2_value_a0 :
                   L0_is_and_a0  ? L0_src1_value_a0 & L0_src2_value_a0 :
                   L0_is_slti_a0  ? {31'b0, (L0_src1_value_a0[31] != L0_imm_a0[31]) ? L0_src1_value_a0[31] : (L0_src1_value_a0 < L0_imm_a0)} :
                   L0_is_sltiu_a0 ? {31'b0, L0_src1_value_a0 < L0_imm_a0} :
                   L0_is_xori_a0  ? L0_src1_value_a0 ^ L0_imm_a0 :
                   L0_is_ori_a0   ? L0_src1_value_a0 | L0_imm_a0 :
                   L0_is_andi_a0  ? L0_src1_value_a0 & L0_imm_a0 :
                   L0_is_slli_a0  ? L0_src1_value_a0 << L0_imm_a0[4:0] :
                   L0_is_srli_a0  ? L0_src1_value_a0 >> L0_imm_a0[4:0] :
                   L0_is_srai_a0  ? (L0_src1_value_a0[31] ? ~((~L0_src1_value_a0) >> L0_imm_a0[4:0]) : (L0_src1_value_a0 >> L0_imm_a0[4:0])) :
                   L0_is_lui_a0   ? L0_imm_a0 :
                   L0_is_auipc_a0 ? L0_pc_a0 + L0_imm_a0 :
                   (L0_is_lw_a0 && (L0_peri_sel_a0 == 2'b01)) ? reg_rdata :               // NEW — UART word load
                   L0_is_lw_a0    ? mem_d_rdata :
                   L0_is_lb_a0    ? {{24{mem_d_rdata[7]}}, mem_d_rdata[7:0]} :
                   L0_is_lbu_a0   ? {24'b0, mem_d_rdata[7:0]} :
                   L0_is_lh_a0    ? {{16{mem_d_rdata[15]}}, mem_d_rdata[15:0]} :
                   L0_is_lhu_a0   ? {16'b0, mem_d_rdata[15:0]} :
                   L0_is_jal_a0   ? L0_pc_a0 + 32'd4 :
                   L0_is_jalr_a0  ? L0_pc_a0 + 32'd4 :
                   L0_is_csr_a0   ? L0_csr_old_value_a0 :
                   32'b0;

   // Register File Write — unchanged formula. It only depends on
   // instruction TYPE and $commit, never on $state directly — since a
   // UART load decodes as $is_i_instr (I-type) exactly like a QSPI load,
   // this already works correctly for UART reads for free, as long as
   // $commit fires at the right moment (which it now does, via the new
   // UART_READ_BUSY condition above).
   assign L0_wr_index_a0[4:0] = L0_rd_a0;
   assign L0_wr_data_a0[31:0] = L0_result_a0;
   assign L0_wr_en_a0 = (L0_is_r_instr_a0 ||
            L0_is_i_instr_a0 ||
            L0_is_u_instr_a0 ||
            L0_is_j_instr_a0 ||
            L0_is_csr_a0)
        && (L0_rd_a0 != 5'd0)
        && L0_commit_a0;

   // Branch Logic (unchanged)
   assign L0_taken_br_a0 = L0_is_beq_a0 ? (L0_src1_value_a0 == L0_src2_value_a0) :
               L0_is_bne_a0 ? (L0_src1_value_a0 != L0_src2_value_a0) :
               L0_is_blt_a0 ? (L0_src1_value_a0 < L0_src2_value_a0) :
               L0_is_bge_a0 ? (L0_src1_value_a0 >= L0_src2_value_a0) :
               L0_is_bltu_a0 ? (L0_src1_value_a0 <  L0_src2_value_a0) :
               L0_is_bgeu_a0 ? (L0_src1_value_a0 >= L0_src2_value_a0) :
                          1'b0;
   assign L0_br_tgt_pc_a0[31:0] = L0_pc_a0 + L0_imm_a0;

   // CSR register bank (unchanged)
   assign L0_csr_wr_en_a0 = L0_is_csr_a0 && !L0_reset_a0 && L0_commit_a0;
   for (csr = 0; csr <= 31; csr++) begin : L1_Csr logic L1_csr_wr_a0; //_/csr
      assign L1_csr_wr_a0 = L0_csr_wr_en_a0 && (L0_csr_addr_a0 == csr);
      assign Csr_value_n1[csr][31:0] = L0_reset_a0 ? 32'b0 : (L1_csr_wr_a0 ? L0_csr_new_value_a0 : Csr_value_a0[csr][31:0]); end
   assign L0_csr_old_value_a0[31:0] = Csr_value_a0[L0_csr_addr_a0];

   `BOGUS_USE(L0_is_store_a0 L0_rd_valid_a0 L0_funct3_valid_a0 L0_imm_valid_a0 L0_is_fence_a0 L0_is_ebreak_a0)

   `line 733 "/raw.githubusercontent.com/stevehoover/LFBuildingaRISCVCPUCore/main/lib/riscvshelllib.tlv" 1
      assign L0_passed_cond_a0 = (Xreg_value_a0[30] == 32'b1) &&
                     (! L0_reset_a0 && L0_next_pc_a0[31:0] == L0_pc_a0[31:0]);
      assign passed = L0_passed_cond_a2;
   //_\end_source
   `line 276 "top.tlv" 2
   assign failed = cyc_cnt > 500;

   `line 125 "/raw.githubusercontent.com/stevehoover/LFBuildingaRISCVCPUCore/main/lib/riscvshelllib.tlv" 1
      assign L0_rf1_wr_en_a0 = L0_wr_en_a0;
      assign L0_rf1_wr_index_a0[$clog2(32)-1:0]  = L0_wr_index_a0[4:0];
      assign L0_rf1_wr_data_a0[32-1:0] = L0_wr_data_a0[31:0];
      
      assign L0_rf1_rd_en1_a0 = L0_rs1_valid_a0;
      assign L0_rf1_rd_index1_a0[$clog2(32)-1:0] = L0_rs1_a0[4:0];
      
      assign L0_rf1_rd_en2_a0 = L0_rs2_valid_a0;
      assign L0_rf1_rd_index2_a0[$clog2(32)-1:0] = L0_rs2_a0[4:0];
      
      for (xreg = 0; xreg <= 31; xreg++) begin : L1_Xreg logic L1_wr_a0; //_/xreg
         assign L1_wr_a0 = L0_rf1_wr_en_a0 && (L0_rf1_wr_index_a0 == xreg);
         assign Xreg_value_n1[xreg][32-1:0] = L0_reset_a0 ? xreg              :
                                    L1_wr_a0      ? L0_rf1_wr_data_a0 :
                                               Xreg_value_a0[xreg][32-1:0]; end
      
      assign L0_src1_value_a0[32-1:0]  =  L0_rf1_rd_en1_a0 ? Xreg_value_a0[L0_rf1_rd_index1_a0] : 'X;
      assign L0_src2_value_a0[32-1:0]  =  L0_rf1_rd_en2_a0 ? Xreg_value_a0[L0_rf1_rd_index2_a0] : 'X;
      
      for (xreg = 0; xreg <= 31; xreg++) begin : L1b_Xreg //_/xreg
         /* Viz omitted here */





































         end
            
   //_\end_source
   `line 279 "top.tlv" 2
   `line 241 "/raw.githubusercontent.com/stevehoover/LFBuildingaRISCVCPUCore/main/lib/riscvshelllib.tlv" 1
      // String representations of the instructions for debug.
      /*SV_plus*/
         // A default signal for ones that are not found.
         logic sticky_zero;
         assign sticky_zero = 0;
         // Instruction strings from the assembler.
         logic [40*8-1:0] instr_strs [0:1];
         assign instr_strs = '{ "(B) BGE x0,x0,0                         ",  "END                                     "};
      
      /* Viz omitted here */














































































































































































































































































































































































































































         
      for (imem = 0; imem <= 0; imem++) begin : L1_Imem //_/imem
         /* Viz omitted here */














































         end
         
   //_\end_source
   `line 280 "top.tlv" 2
/*SV_plus*/
   // QSPI bridges — unchanged.
   assign i_addr  = L0_i_addr_a0;
   assign i_req   = L0_i_req_a0;
   assign d_addr  = L0_d_addr_a0;
   assign d_req   = L0_d_req_a0;
   assign d_we    = L0_d_we_a0;
   assign d_wstrb = L0_d_wstrb_a0;
   assign d_wdata = L0_d_wdata_a0;
   // UART bridges — NEW. These become rv32i_core.sv's new output ports.
   assign reg_addr  = L0_reg_addr_a0;
   assign reg_we    = L0_reg_we_a0;
   assign reg_re    = L0_reg_re_a0;
   assign reg_wdata = L0_reg_wdata_a0;
//_\SV
   endmodule


// Undefine macros defined by SandPiper (in "top_gen.sv").
`undef BOGUS_USE
