# QSPI Memory Subsystem for a Single-Cycle RV32I Processor

This document describes how to use the **`rv32i_qspi_mem`** module to attach
external QSPI flash (instructions) and QSPI PSRAM × 2 (data) to a
single-cycle RV32I RISC-V core via the
[QSPI PMOD](https://github.com/mole99/qspi-pmod).

---

## 1. Files

| Path | Description |
|------|-------------|
| `src/A30-RISCV/peri/qspi_mem/rv32i_qspi_mem.v` | Top-level CPU-facing wrapper (new) |
| `src/A30-RISCV/peri/qspi_mem/qspi_ctrl.v` | Low-level QSPI byte engine (IP from tinyQV) |
| `test/A30-RISCV/tb_rv32i_qspi.v` | Verilog testbench |
| `test/A30-RISCV/test_rv32i_qspi.py` | cocotb test suite |
| `test/A30-RISCV/test_rv32i_qspi.mk` | Makefile for the test |
| `test/A30-RISCV/sim_qspi.v` | Verilog model of the Flash and RAM |
| `test/A30-RISCV/test_mem.hex` | ROM image used by the testbench |
| `docs/qspi_mem_subsystem.md` | This file |

---

## 2. Block Diagram

```
                ┌────────────────────────────────────────────┐
  Single-Cycle  │           rv32i_qspi_mem                   │
  RV32I Core    │                                            │
                │  ┌──────────────────────────────────────┐  │
  i_addr ──────►│  │  Instruction FSM (4-byte flash burst)│  │
  i_req  ──────►│  └─────────────┬────────────────────────┘  │
  i_rdata◄──────│                │                           │   QSPI PMOD
  i_ready◄──────│  ┌─────────────▼────────────────────────┐  │  ┌──────────┐
                │  │   Data FSM (1/2/4-byte PSRAM R/W)    │  │  │  Flash   │
  d_addr ──────►│  └─────────────┬────────────────────────┘  │◄─►  (inst)  │
  d_req  ──────►│                │                           │  │          │
  d_we   ──────►│  ┌─────────────▼────────────────────────┐  │  │ PSRAM A  │
  d_wstrb──────►│  │         qspi_controller              │  │◄─►  (data)  │
  d_wdata──────►│  │  (byte-serial QSPI engine)           │  │  │          │
  d_rdata◄──────│  └──────────────────────────────────────┘  │  │ PSRAM B  │
  d_ready◄──────│                                            │◄─►  (data)  │
                └────────────────────────────────────────────┘  └──────────┘
```

---

## 3. Signal Reference

### 3.1 Instruction Port

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `i_addr` | in | 24 | Byte address within flash (0x000000 – 0xFFFFFF) |
| `i_req` | in | 1 | Pulse HIGH for one cycle to request a 32-bit fetch |
| `i_rdata` | out | 32 | 32-bit little-endian instruction word |
| `i_ready` | out | 1 | One-cycle pulse: `i_rdata` is valid |

### 3.2 Data Port

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `d_addr` | in | 25 | Byte start address (bit 24 = 1 → PSRAM space) |
| `d_req` | in | 1 | Pulse HIGH for one cycle to start a transaction |
| `d_we` | in | 1 | 0 = read, 1 = write |
| `d_wstrb` | in | 4 | Byte enables — see §4 |
| `d_wdata` | in | 32 | Write data: byte *i* at bits `[8i+7:8i]` |
| `d_rdata` | out | 32 | Read data: byte *i* at bits `[8i+7:8i]` |
| `d_ready` | out | 1 | One-cycle pulse: transaction complete |

### 3.3 QSPI PMOD

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `spi_data_in` | in | 4 | QSPI IO lines (DQ0–DQ3) from PMOD |
| `spi_data_out` | out | 4 | QSPI IO lines to PMOD |
| `spi_data_oe` | out | 4 | Output-enable for each IO line |
| `spi_clk_out` | out | 1 | QSPI serial clock |
| `spi_flash_select` | out | 1 | Flash chip-select (active LOW) |
| `spi_ram_a_select` | out | 1 | PSRAM A chip-select (active LOW) |
| `spi_ram_b_select` | out | 1 | PSRAM B chip-select (active LOW) |

---

## 4. Memory Map

| Region | d_addr range | Size | Device | Access |
|--------|--------------|------|--------|--------|
| Flash (instructions) | 0x0000000 – 0x0FFFFFF | 16 MB | Flash chip | i_req only (read-only) |
| PSRAM A (data) | 0x1000000 – 0x17FFFFF | 8 MB | PSRAM A | d_req read/write |
| PSRAM B (data) | 0x1800000 – 0x1FFFFFF | 8 MB | PSRAM B | d_req read/write |

> **Note:** these ranges match the `qspi_controller` internal address decoder.
> The flash is assumed to already be in QSPI **fast-read continuous mode** (EBh).
> The two PSRAMs must already be in **QSPI mode** before `rstn` is released.

---

## 5. Transaction Encoding with `d_wstrb`

`d_wstrb` encodes both which bytes to transfer and where they start:

| `d_wstrb` | Bytes | Start offset | Typical RISC-V instruction |
|-----------|-------|-------------|---------------------------|
| `4'b0001` | 1 | `d_addr+0` | LB/LBU/SB at byte 0 |
| `4'b0010` | 1 | `d_addr+1` | LB/LBU/SB at byte 1 |
| `4'b0100` | 1 | `d_addr+2` | LB/LBU/SB at byte 2 |
| `4'b1000` | 1 | `d_addr+3` | LB/LBU/SB at byte 3 |
| `4'b0011` | 2 | `d_addr+0` | LH/LHU/SH at byte 0 |
| `4'b1100` | 2 | `d_addr+2` | LH/LHU/SH at byte 2 |
| `4'b1111` | 4 | `d_addr+0` | LW/SW (word) |

**For reads:** `d_rdata[7:0]` holds the first byte received (at `d_addr +
lowest_set_bit(d_wstrb)`), `d_rdata[15:8]` the second, and so on.  
The CPU is responsible for any sign/zero-extension and byte-lane extraction.

**For writes:** byte *i* of `d_wdata` (`d_wdata[8i+7:8i]`) is written to
`d_addr + i` for each set bit *i* in `d_wstrb`.

---

## 6. Timing / Latency

All latencies shown in **system-clock cycles** (100 MHz reference).

| Transaction | Approx. latency (cycles) | Notes |
|-------------|--------------------------|-------|
| Flash read (4 bytes) | ≈ 50–55 | ADDR (12) + DUMMY (8) + DATA (8) + overhead |
| PSRAM read (4 bytes) | ≈ 40–45 | CMD (4) + ADDR (12) + DUMMY (8) + DATA (8) |
| PSRAM read (1 byte) | ≈ 38–42 | Same preamble, 2 fewer DATA cycles |
| PSRAM write (4 bytes) | ≈ 36–40 | No DUMMY; `d_ready` fires ~1 cycle after last byte |
| PSRAM write (1 byte) | ≈ 30–34 | |

> The QSPI SPI clock runs at **half** the system clock (i.e. 50 MHz for a
> 100 MHz design).  The `delay_cycles_cfg` setting in `qspi_controller` must
> match the round-trip propagation delay of the PMOD connection (typically 1
> at ≤50 MHz; see `qspi_ctrl.v` header for details).

### Stalling Strategy for a Single-Cycle Core

A single-cycle core must stall its pipeline whenever the memory is not ready:

```
                       ┌── i_req high for 1 cycle ──┐
time:   ... | N | N+1 |    N+2    | ... | N+50 | ...
              ↑                              ↑
          CPU issues req              i_ready fires
                                      CPU reads i_rdata
                                      and advances PC
```

The simplest implementation:

1. Add a `stall` signal to every pipeline register's enable:
   `pipe_en = i_ready | d_ready | (no_mem_op)`.
2. Issue `i_req` when the core needs the next instruction and no other
   transaction is pending.
3. Issue `d_req` when a load/store is decoded; deassert `i_req` until
   `d_ready` fires.
4. Never issue a new request of either kind while a previous request's ready
   has not yet been seen.

---

## 7. Reset / Initialisation

```
         ┌─────────────── rstn LOW ──────────────┐
         │  spi_data_in[2:0] must hold:          │  rstn HIGH
         │  [1:0] = delay_cycles_cfg (1..3)      │
         │  [2]   = 0 (use positive-edge clock)  │
         └───────────────────────────────────────┘
```

During the reset window the `qspi_controller` latches `delay_cycles_cfg`
(bits [1:0] of `spi_data_in`) and `spi_clk_use_neg` (bit [2]) on every
rising edge of `clk`.  Hold `rstn` low for at least **10 clock cycles** with
the configuration value stable on `spi_data_in[2:0]`.

In the test bench this is handled by driving `spi_data_in = 4'b0001` while
`rstn = 0` (delay = 1, positive-edge clock).

---

## 8. Step-by-Step Integration with a Generic RV32I Core

Below is a minimal wiring example in Verilog pseudo-code.

```verilog
module my_rv32i_soc (
    input  clk,
    input  rstn,
    // … QSPI PMOD pins …
);

    // ── CPU ──────────────────────────────────────────────────────────────
    wire [23:0] cpu_pc;          // current PC (only lower 24 bits used for flash)
    wire        cpu_instr_stall; // stall the fetch stage
    wire [31:0] cpu_instr;       // instruction word from memory

    wire [24:0] cpu_daddr;       // effective data address
    wire        cpu_dmem_req;    // load or store this cycle
    wire        cpu_dwe;         // 1=store, 0=load
    wire  [3:0] cpu_dwstrb;      // byte enables
    wire [31:0] cpu_dwdata;      // store data
    wire [31:0] cpu_drdata;      // load data
    wire        cpu_dmem_stall;  // stall the execute stage

    // ── Memory subsystem ────────────────────────────────────────────────
    wire        i_ready, d_ready;

    rv32i_qspi_mem mem (
        .clk             (clk),
        .rstn            (rstn),

        // Instruction port
        .i_addr          (cpu_pc[23:0]),
        .i_req           (!cpu_instr_stall),   // request when pipeline not stalled
        .i_rdata         (cpu_instr),
        .i_ready         (i_ready),

        // Data port
        .d_addr          (cpu_daddr),
        .d_req           (cpu_dmem_req),
        .d_we            (cpu_dwe),
        .d_wstrb         (cpu_dwstrb),
        .d_wdata         (cpu_dwdata),
        .d_rdata         (cpu_drdata),
        .d_ready         (d_ready),

        // QSPI PMOD (connect directly to top-level IO pads)
        .spi_data_in     (spi_data_in),
        .spi_data_out    (spi_data_out),
        .spi_data_oe     (spi_data_oe),
        .spi_clk_out     (spi_clk_out),
        .spi_flash_select(spi_flash_select),
        .spi_ram_a_select(spi_ram_a_select),
        .spi_ram_b_select(spi_ram_b_select)
    );

    // ── Stall logic ──────────────────────────────────────────────────────
    // Fetch stage stalls until i_ready, or while a data op is pending.
    assign cpu_instr_stall = !i_ready && !(/* new fetch just launched */);

    // Execute stage stalls on loads/stores until d_ready.
    assign cpu_dmem_stall  = cpu_dmem_req && !d_ready;

    // ── CPU instantiation ────────────────────────────────────────────────
    my_rv32i_core core (
        .clk       (clk),
        .rstn      (rstn),
        .instr     (cpu_instr),
        .instr_stall (!i_ready),
        .daddr     (cpu_daddr),
        .dmem_req  (cpu_dmem_req),
        .dwe       (cpu_dwe),
        .dwstrb    (cpu_dwstrb),
        .dwdata    (cpu_dwdata),
        .drdata    (cpu_drdata),
        .dmem_stall(cpu_dmem_stall),
        // …
    );

endmodule
```

### d_wstrb generation in the CPU

```verilog
// Example combinatorial decoder for RISC-V store instructions
always @(*) begin
    case (funct3)                     // funct3 from instruction word
        3'b000: begin                 // SB
            d_wstrb = 4'b0001 << effective_addr[1:0];
            d_wdata = {4{rs2[7:0]}};
        end
        3'b001: begin                 // SH
            d_wstrb = 4'b0011 << {effective_addr[1], 1'b0};
            d_wdata = {2{rs2[15:0]}};
        end
        3'b010: begin                 // SW
            d_wstrb = 4'b1111;
            d_wdata = rs2;
        end
        default: d_wstrb = 4'b0000;
    endcase
end
```

For loads, `d_wstrb` maps to size:

| `funct3` | `d_wstrb` | d_rdata extraction |
|----------|-----------|--------------------|
| LB / LBU | `4'b0001` | `d_rdata[7:0]` (sign/zero extend) |
| LH / LHU | `4'b0011` | `d_rdata[15:0]` |
| LW | `4'b1111` | `d_rdata[31:0]` |

---

## 9. Chip-Select Strategy for Two PSRAMs

The module exposes `spi_ram_a_select` and `spi_ram_b_select` as separate
active-low outputs, matching the two PSRAM slots on the QSPI PMOD.

The `qspi_controller` selects the correct chip automatically based on
`d_addr[24:23]`:

| `d_addr[24:23]` | Chip selected |
|-----------------|---------------|
| `2'b10` | PSRAM A (`spi_ram_a_select` LOW) |
| `2'b11` | PSRAM B (`spi_ram_b_select` LOW) |

A 2-system-clock guard after every PSRAM deselect is enforced inside
`rv32i_qspi_mem` (mirroring the internal constraint of `qspi_controller`)
to guarantee CS# deassert hold time.

---

## 10. Running the cocotb Testbench

<!--
### Prerequisites
```bash
pip install cocotb==1.9.2
# Icarus Verilog ≥10 or Verilator ≥5
```
--!>

### Run

```bash
cd test/A30-RISCV/
make -f test_rv32i_qspi.mk          # Icarus Verilog (default)
make -f test_rv32i_qspi.mk SIM=verilator
```

### Expected output (all passing)

```
test_reset_init          PASSED
test_instr_fetch_word    PASSED
test_instr_fetch_offset  PASSED
test_data_read_word      PASSED
test_data_write_word     PASSED
test_data_read_psram_b   PASSED
test_data_write_psram_b  PASSED
test_byte_write_strobe   PASSED
test_halfword_write      PASSED
test_back_to_back        PASSED
test_data_then_instr     PASSED
```

### Wave Dump

```bash
make -f test_rv32i_qspi.mk WAVES=1
gtkwave sim_build/rv32i_qspi/tb_rv32i_qspi.fst
```

---

## 11. Limitations and Future Work

- **Write-only lanes not supported**: non-contiguous `d_wstrb` patterns
  (e.g. `4'b1010`) are not correctly handled; only contiguous patterns
  that correspond to standard RISC-V LB/LH/LW/SB/SH/SW accesses are
  guaranteed.
- **No burst / cache**: each CPU request maps to exactly one QSPI burst.
  An instruction cache or prefetch buffer would dramatically improve
  performance.
- **Flash assumed in continuous-read mode**: the flash must be placed in
  QSPI fast-read continuous mode (EBh command) externally before reset is
  released.  PSRAMs must be in QSPI mode.
- **No write-back verification**: the module trusts that QSPI writes are
  accepted; there is no read-modify-write or ECC support.
