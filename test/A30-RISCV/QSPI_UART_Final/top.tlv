\m4_TLV_version 1d: tl-x.org
\SV
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv'])
   m4_asm(BGE, x0, x0, 0)
   m4_asm_end()
   m4_define(['M4_MAX_CYC'], 500)
   //---------------------------------------------------------------------------------
\SV
   // Layer 1 — definitions only, nothing instantiated here. rv32i_qspi_mem
   // and uart_riscv_if both get instantiated externally, in qspi_chip_top.sv.
   `include "qspi_controller.v"
   `include "rv32i_qspi_mem.v"
   `include "uart_riscv_if.v"
\SV
   m4_makerchip_module
\SV
   // Layer 2 — intentionally empty. mem_i_rdata / mem_i_ready /
   // mem_d_rdata / mem_d_ready (QSPI) and reg_rdata / tx_irq / rx_irq
   // (UART) are all supplied externally, by rv32i_core.sv, before it
   // `include`s the compiled output of this file's \TLV block.
\TLV
   // ================================================================
   // Core logic. Decode/ALU/branch/register-file sections are UNCHANGED
   // from the verified QSPI-only core. Everything marked NEW below is
   // the FSM extension + UART wiring.
   // ================================================================

   $reset = *reset;
   $start = !$reset;                              // NEW — IDLE waits for this before leaving reset

   // ----------------------------------------------------------------
   // MEMORY-ACCESS FSM — 10 states now (was 4). $state widened 2->4 bits.
   // IDLE=0, FETCH_REQ=1, FETCH_WAIT=2, DATA_MEM_READ=3, DATA_MEM_WRITE=4,
   // DATA_MEM_WAIT=5, UART_READ=6, UART_READ_BUSY=7, UART_WRITE=8,
   // UART_WRITE_BUSY=9
   // ----------------------------------------------------------------
   $state[3:0] = $reset ? 4'd0 : (>>1$reset ? 4'd0 : >>1$next_state);   // CHANGED — targets IDLE, not old FETCH encoding

   $next_state[3:0] =                                                   // CHANGED — full rewrite for 10 states
      ($state == 4'd0) ? ($start ? 4'd1 : 4'd0) :                                  // IDLE: wait for $start
      ($state == 4'd1) ? 4'd2 :                                                    // FETCH_REQ: unconditional
      ($state == 4'd2) ? (!mem_i_ready                       ? 4'd2 :              // FETCH_WAIT: wait for i_ready
                           ($is_load  && $peri_sel==2'b00)    ? 4'd3 :              //   load + QSPI  -> DATA_MEM_READ
                           ($is_store && $peri_sel==2'b00)    ? 4'd4 :              //   store + QSPI -> DATA_MEM_WRITE
                           ($is_load  && $peri_sel==2'b01)    ? 4'd6 :              //   load + UART  -> UART_READ
                           ($is_store && $peri_sel==2'b01)    ? 4'd8 :              //   store + UART -> UART_WRITE
                                                                 4'd1) :            //   neither       -> FETCH_REQ
      ($state == 4'd3) ? 4'd5 :                                                    // DATA_MEM_READ -> DATA_MEM_WAIT
      ($state == 4'd4) ? 4'd5 :                                                    // DATA_MEM_WRITE -> DATA_MEM_WAIT
      ($state == 4'd5) ? (mem_d_ready ? 4'd1 : 4'd5) :                             // DATA_MEM_WAIT: wait for d_ready
      ($state == 4'd6) ? 4'd7 :                                                    // FIXED — UART_READ: unconditional (reg_rdata is combinational; waiting on rx_irq here deadlocked STATUS/CTRL/BAUD_DIV reads)
      ($state == 4'd7) ? 4'd1 :                                                    // UART_READ_BUSY: unconditional
      ($state == 4'd8) ? 4'd9 :                                                    // FIXED — UART_WRITE: unconditional (waiting on tx_irq here deadlocked CTRL, since tx_irq depends on CTRL being written first)
      ($state == 4'd9) ? (tx_irq ? 4'd1 : 4'd9) :                                  // UART_WRITE_BUSY: wait for tx_irq high again
                          4'd0;

   $i_req = ($state == 4'd1) && !$reset;                                // CHANGED — FETCH_REQ is now state 1
   $d_req = (($state == 4'd3) || ($state == 4'd4)) && !$reset;          // CHANGED — covers both QSPI read AND write states now

   $instr[31:0] = $reset ? 32'b0 :
                  (($state == 4'd2) && mem_i_ready) ? mem_i_rdata :      // CHANGED — FETCH_WAIT is now state 2
                  >>1$instr;

   $is_mem_op = $is_load || $is_store;

   $commit = (($state == 4'd2) && mem_i_ready && !$is_mem_op) ||        // non-mem instr done in FETCH_WAIT
             (($state == 4'd5) && mem_d_ready)                  ||      // QSPI load/store done in DATA_MEM_WAIT
             ($state == 4'd7)                                   ||      // NEW — UART read done in UART_READ_BUSY
             (($state == 4'd9) && tx_irq);                              // NEW — UART write done in UART_WRITE_BUSY

   $pc[31:0] = $reset ? 32'b0 :
               (>>1$reset ? 32'b0 :
               (>>1$commit ? >>1$next_pc : >>1$pc));

   $next_pc[31:0] = $is_trap ? $pc :
                           $taken_br ? $br_tgt_pc :
                           $is_jal  ? $br_tgt_pc :
                           $is_jalr ? $jalr_tgt_pc :
                                      ($pc + 32'd4);

   $i_addr[23:0] = $pc[23:0];

   // ---- DECODE (unchanged) ----
   $is_u_instr = $instr[6:2] ==? 5'b0x101;
   $is_i_instr = $instr[6:2] ==? 5'b0000x ||
                 $instr[6:2] ==? 5'b001x0 ||
                 $instr[6:2] ==? 5'b11001;
   $is_r_instr = $instr[6:2] ==? 5'b011x0;
   $is_s_instr = $instr[6:2] ==? 5'b0100x;
   $is_b_instr = $instr[6:2] ==? 5'b11000;
   $is_j_instr = $instr[6:2] ==? 5'b11011;

   $opcode[6:0] = $instr[6:0];
   $rd[4:0] = $instr[11:7];
   $funct3[2:0] = $instr[14:12];
   $rs1[4:0] = $instr[19:15];
   $rs2[4:0] = $instr[24:20];

   $rd_valid = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr || $is_csr;
   $funct3_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
   $rs1_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr || $is_csr;
   $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
   $imm_valid = $is_i_instr || $is_s_instr || $is_b_instr || $is_u_instr || $is_j_instr;

   $imm[31:0] = $is_i_instr ? {{21{$instr[31]}}, $instr[30:20]} :
                $is_s_instr ? {{21{$instr[31]}}, $instr[30:25], $instr[11:7]} :   // FIXED — was backwards (instr[11:7] and instr[30:25] swapped), invisible with offset 0
                $is_b_instr ? {{20{$instr[31]}}, $instr[7], $instr[30:25], $instr[11:8], 1'b0} :
                $is_u_instr ? {$instr[31], $instr[30:12], 12'b0} :
                $is_j_instr ? {{12{$instr[31]}}, $instr[19:12], $instr[20], $instr[30:21], 1'b0} :
                32'b0;

   $dec_bits[10:0] = {$instr[30], $funct3, $opcode};
   $is_addi = $dec_bits ==? 11'bx_000_0010011;
   $is_add  = $dec_bits ==? 11'b0_000_0110011;
   $is_beq  = $dec_bits ==? 11'bx_000_1100011;
   $is_bne  = $dec_bits ==? 11'bx_001_1100011;
   $is_blt  = $dec_bits ==? 11'bx_100_1100011;
   $is_bge  = $dec_bits ==? 11'bx_101_1100011;
   $is_bltu = $dec_bits ==? 11'bx_110_1100011;
   $is_bgeu = $dec_bits ==? 11'bx_111_1100011;

   $is_sub  = $dec_bits ==? 11'b1_000_0110011;
   $is_sll  = $dec_bits ==? 11'b0_001_0110011;
   $is_slt  = $dec_bits ==? 11'b0_010_0110011;
   $is_sltu = $dec_bits ==? 11'b0_011_0110011;
   $is_xor  = $dec_bits ==? 11'b0_100_0110011;
   $is_srl  = $dec_bits ==? 11'b0_101_0110011;
   $is_sra  = $dec_bits ==? 11'b1_101_0110011;
   $is_or   = $dec_bits ==? 11'b0_110_0110011;
   $is_and  = $dec_bits ==? 11'b0_111_0110011;

   $is_slti  = $dec_bits ==? 11'bx_010_0010011;
   $is_sltiu = $dec_bits ==? 11'bx_011_0010011;
   $is_xori  = $dec_bits ==? 11'bx_100_0010011;
   $is_ori   = $dec_bits ==? 11'bx_110_0010011;
   $is_andi  = $dec_bits ==? 11'bx_111_0010011;
   $is_slli  = $dec_bits ==? 11'b0_001_0010011;
   $is_srli  = $dec_bits ==? 11'b0_101_0010011;
   $is_srai  = $dec_bits ==? 11'b1_101_0010011;

   $is_lb  = $dec_bits ==? 11'bx_000_0000011;
   $is_lh  = $dec_bits ==? 11'bx_001_0000011;
   $is_lw  = $dec_bits ==? 11'bx_010_0000011;
   $is_lbu = $dec_bits ==? 11'bx_100_0000011;
   $is_lhu = $dec_bits ==? 11'bx_101_0000011;
   $is_load = $is_lb || $is_lh || $is_lw || $is_lbu || $is_lhu;

   $is_sb = $dec_bits ==? 11'bx_000_0100011;
   $is_sh = $dec_bits ==? 11'bx_001_0100011;
   $is_sw = $dec_bits ==? 11'bx_010_0100011;
   $is_store = $is_sb || $is_sh || $is_sw;

   $is_lui   = $opcode ==? 7'b0110111;
   $is_auipc = $opcode ==? 7'b0010111;

   $is_jal  = $opcode ==? 7'b1101111;
   $is_jalr = ($opcode ==? 7'b1100111) && ($funct3 == 3'b000);
   $jalr_tgt_pc[31:0] = ($src1_value + $imm) & 32'hFFFFFFFE;

   $is_system = $opcode ==? 7'b1110011;
   $is_ecall  = $is_system && ($funct3==3'b000) && ($instr[31:20]==12'b0);
   $is_ebreak = $is_system && ($funct3==3'b000) && ($instr[31:20]==12'b1);
   $is_csrrw  = $is_system && ($funct3==3'b001);
   $is_csrrs  = $is_system && ($funct3==3'b010);
   $is_csrrc  = $is_system && ($funct3==3'b011);
   $is_csrrwi = $is_system && ($funct3==3'b101);
   $is_csrrsi = $is_system && ($funct3==3'b110);
   $is_csrrci = $is_system && ($funct3==3'b111);
   $is_csr    = $is_csrrw || $is_csrrs || $is_csrrc || $is_csrrwi || $is_csrrsi || $is_csrrci;
   $is_fence  = $opcode ==? 7'b0001111;
   $is_trap   = $is_ecall || $is_ebreak;

   $csr_addr[4:0] = $instr[24:20];
   $csr_operand[31:0] = ($is_csrrwi || $is_csrrsi || $is_csrrci) ? {27'b0, $rs1[4:0]} : $src1_value;
   $csr_new_value[31:0] = ($is_csrrw || $is_csrrwi) ? $csr_operand :
                           ($is_csrrs || $is_csrrsi) ? ($csr_old_value | $csr_operand) :
                                                        ($csr_old_value & ~$csr_operand);

   // ---- QSPI data-side wiring (unchanged — $d_addr stays 25 bits) ----
   $ld_st_addr[31:0] = $src1_value + $imm;
   $byte_offset[1:0] = $ld_st_addr[1:0];

   $d_addr[24:0] = $ld_st_addr[24:0];
   $d_we = $is_store;

   $d_wstrb[3:0] =
      ($is_lb || $is_lbu || $is_sb) ? (4'b0001 << $byte_offset) :
      ($is_lh || $is_lhu || $is_sh) ? (4'b0011 << {$byte_offset[1], 1'b0}) :
      ($is_lw || $is_sw)            ? 4'b1111 :
                                       4'b0000;

   $d_wdata[31:0] = $is_sb ? {4{$src2_value[7:0]}} :
                     $is_sh ? {2{$src2_value[15:0]}} :
                              $src2_value;

   // ---- UART wiring — NEW ----
   // $ld_st_addr is already a full 32-bit sum, so we can slice the
   // device-select bits straight from it without touching $d_addr at all
   // (rv32i_qspi_mem's d_addr port is fixed at 25 bits, so widening
   // $d_addr itself would create a port-width mismatch).
   $peri_sel[1:0]  = $ld_st_addr[27:26];             // NEW — 00=QSPI, 01=UART
   $reg_addr[1:0]  = $ld_st_addr[3:2];                // NEW — selects DATA/STATUS/CTRL/BAUD_DIV
   $reg_we         = ($state == 4'd8);                // FIXED — pulses for the one cycle spent in UART_WRITE (no tx_irq gate, or CTRL could never be written to enable tx_irq in the first place)
   $reg_re         = ($state == 4'd6);                // FIXED — pulses for the one cycle spent in UART_READ (no rx_irq gate — reg_rdata is combinational, STATUS/CTRL/BAUD_DIV need no wait)
   $reg_wdata[31:0] = $src2_value;                    // NEW — same source as a QSPI store's $d_wdata

   // ALU
   $result[31:0] = $is_addi ? $src1_value + $imm :
                   $is_add  ? $src1_value + $src2_value :
                   $is_sub  ? $src1_value - $src2_value :
                   $is_sll  ? $src1_value << $src2_value[4:0] :
                   $is_slt  ? {31'b0, ($src1_value[31] != $src2_value[31]) ? $src1_value[31] : ($src1_value < $src2_value)} :
                   $is_sltu ? {31'b0, $src1_value < $src2_value} :
                   $is_xor  ? $src1_value ^ $src2_value :
                   $is_srl  ? $src1_value >> $src2_value[4:0] :
                   $is_sra  ? ($src1_value[31] ? ~((~$src1_value) >> $src2_value[4:0]) : ($src1_value >> $src2_value[4:0])) :
                   $is_or   ? $src1_value | $src2_value :
                   $is_and  ? $src1_value & $src2_value :
                   $is_slti  ? {31'b0, ($src1_value[31] != $imm[31]) ? $src1_value[31] : ($src1_value < $imm)} :
                   $is_sltiu ? {31'b0, $src1_value < $imm} :
                   $is_xori  ? $src1_value ^ $imm :
                   $is_ori   ? $src1_value | $imm :
                   $is_andi  ? $src1_value & $imm :
                   $is_slli  ? $src1_value << $imm[4:0] :
                   $is_srli  ? $src1_value >> $imm[4:0] :
                   $is_srai  ? ($src1_value[31] ? ~((~$src1_value) >> $imm[4:0]) : ($src1_value >> $imm[4:0])) :
                   $is_lui   ? $imm :
                   $is_auipc ? $pc + $imm :
                   ($is_lw && ($peri_sel == 2'b01)) ? reg_rdata :               // NEW — UART word load
                   $is_lw    ? mem_d_rdata :
                   $is_lb    ? {{24{mem_d_rdata[7]}}, mem_d_rdata[7:0]} :
                   $is_lbu   ? {24'b0, mem_d_rdata[7:0]} :
                   $is_lh    ? {{16{mem_d_rdata[15]}}, mem_d_rdata[15:0]} :
                   $is_lhu   ? {16'b0, mem_d_rdata[15:0]} :
                   $is_jal   ? $pc + 32'd4 :
                   $is_jalr  ? $pc + 32'd4 :
                   $is_csr   ? $csr_old_value :
                   32'b0;

   // Register File Write — unchanged formula. It only depends on
   // instruction TYPE and $commit, never on $state directly — since a
   // UART load decodes as $is_i_instr (I-type) exactly like a QSPI load,
   // this already works correctly for UART reads for free, as long as
   // $commit fires at the right moment (which it now does, via the new
   // UART_READ_BUSY condition above).
   $wr_index[4:0] = $rd;
   $wr_data[31:0] = $result;
   $wr_en = ($is_r_instr ||
            $is_i_instr ||
            $is_u_instr ||
            $is_j_instr ||
            $is_csr)
        && ($rd != 5'd0)
        && $commit;

   // Branch Logic (unchanged)
   $taken_br = $is_beq ? ($src1_value == $src2_value) :
               $is_bne ? ($src1_value != $src2_value) :
               $is_blt ? ($src1_value < $src2_value) :
               $is_bge ? ($src1_value >= $src2_value) :
               $is_bltu ? ($src1_value <  $src2_value) :
               $is_bgeu ? ($src1_value >= $src2_value) :
                          1'b0;
   $br_tgt_pc[31:0] = $pc + $imm;

   // CSR register bank (unchanged)
   $csr_wr_en = $is_csr && !$reset && $commit;
   /csr[31:0]
      $csr_wr = /top$csr_wr_en && (/top$csr_addr == #csr);
      <<1$value[31:0] = /top$reset ? 32'b0 : ($csr_wr ? /top$csr_new_value : $RETAIN);
   $csr_old_value[31:0] = /csr[$csr_addr]$value;

   `BOGUS_USE($is_store $rd_valid $funct3_valid $imm_valid $is_fence $is_ebreak)

   m4+tb()
   *failed = *cyc_cnt > M4_MAX_CYC;

   m4+rf(32, 32, $reset, $wr_en, $wr_index[4:0], $wr_data[31:0], $rs1_valid, $rs1[4:0], $src1_value, $rs2_valid, $rs2[4:0], $src2_value)
   m4+cpu_viz()
\SV_plus
   // QSPI bridges — unchanged.
   assign i_addr  = $i_addr;
   assign i_req   = $i_req;
   assign d_addr  = $d_addr;
   assign d_req   = $d_req;
   assign d_we    = $d_we;
   assign d_wstrb = $d_wstrb;
   assign d_wdata = $d_wdata;
   // UART bridges — NEW. These become rv32i_core.sv's new output ports.
   assign reg_addr  = $reg_addr;
   assign reg_we    = $reg_we;
   assign reg_re    = $reg_re;
   assign reg_wdata = $reg_wdata;
\SV
   endmodule