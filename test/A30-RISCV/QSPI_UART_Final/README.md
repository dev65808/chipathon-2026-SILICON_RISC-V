# QSPI_UART_Final

RV32I RISC-V core + real QSPI flash/PSRAM memory subsystem + memory-mapped
UART peripheral, verified via cocotb.

## Structure

- `rv32i_core.sv` + `top_gen.sv` — the RV32I core (all QSPI memory ports
  and UART register-interface ports exposed, no memory model or UART IP
  instantiated inside)
- `qspi_ctrl.v`, `rv32i_qspi_mem.v` — the real QSPI memory controller IP
- `sim_qspi.v` — simulated flash + PSRAM A + PSRAM B (external chip model,
  instantiated only in the testbench, not inside the chip-level module)
- `uart_riscv_if.v`, `uart_tx.v`, `uart_rx.v` — the UART peripheral IP
  (register interface + transmitter + receiver)
- `pseudo_rand_stub.sv` — stub satisfying an internal Makerchip helper reference
- `qspi_chip_top.sv` — chip-level top module: instantiates the core, the
  QSPI memory controller, and the UART interface together
- `tb_qspi_chip_top.v` — testbench: instantiates `qspi_chip_top` and
  `sim_qspi_pmod`, wires the QSPI bus between them, and exposes `uart_tx`/
  `uart_rx` as explicit testbench signals for cocotb to drive
- `top.tlv` — the Makerchip/TL-Verilog source `rv32i_core.sv`/`top_gen.sv`
  were compiled from (kept for reference, not part of the build)
- `Makefile` — build/run recipe

## Test files

- `test_mem.hex` + `test_top.py` — UART-only test: sends one byte over
  `uart_rx` and checks the core reads it back correctly via `UART_READ`
- `test_mem_qspi_uart.hex` + `test_top_qspi_uart.py` — combined test:
  runs a QSPI store/load round-trip AND a UART byte read in a single
  10-instruction program
- `test_mem_full.hex` + `test_top_full.py` — full test: QSPI round-trip,
  UART CTRL register write/readback (enable bits), UART TX verified
  directly on the physical `uart_tx` pin, UART RX, STATUS register, and
  BAUD_DIV register, all in a single 17-instruction program

Only one test pair runs at a time — point the `Makefile`'s
`COCOTB_TEST_MODULES` and `INIT_FILE` at whichever pair you want to run.

## Prerequisites

- Icarus Verilog (`iverilog`)
- Python 3
- cocotb (`pip3 install cocotb`)
- GTKWave (`brew install --cask gtkwave`) — for viewing waveforms

## Run

```bash
cd QSPI_UART_Final
rm -rf sim_build results.xml
make
gtkwave waveform.vcd
```

---

## Test 1: UART-only test

**Files:** `test_mem.hex` + `test_top.py`

Sends one byte (`0x42`) over `uart_rx` (bit-banged, standard 8N1 frame)
and checks the core correctly reads it back through the `UART_READ` /
`UART_READ_BUSY` FSM states.

### What it verifies

1. `LUI x4,0x04000` — load UART peripheral base address into x4
2. `ADDI x9,x0,80` — set up a delay counter
3. `ADDI x9,x9,-1` (loop) — decrement
4. `BNE x9,x0,-4` — loop until counter hits 0 (gives time for the byte
   to arrive over `uart_rx`)
5. `LW x8,x4,0` — read the UART DATA register into x8
6. `BGE x0,x0,0` — halt

Final check: `x8 == 0x42` (byte received correctly), `pc == 0x14`
(reached the halt loop).

### Expected output

```
x8=0x42(exp 0x42) pc=0x14(exp 0x14)
PASS: real UART RX byte correctly received via UART_READ/UART_READ_BUSY
TESTS=1 PASS=1 FAIL=0 SKIP=0
```

---

## Test 2: Combined QSPI + UART test

**Files:** `test_mem_qspi_uart.hex` + `test_top_qspi_uart.py`

Runs a QSPI store/load round-trip AND a UART byte read in a single
10-instruction program, proving both peripherals work correctly
together through one core.

### What it verifies

1. `ADDI x1,x0,5`
2. `LUI x2,0x1000`
3. `SW x1,x2,0`
4. `LW x3,x2,0`
5. `LUI x4,0x04000`
6. `ADDI x9,x0,80`
7. `ADDI x9,x9,-1` (loop)
8. `BNE x9,x0,-4` (loop until counter hits 0)
9. `LW x8,x4,0` — reads the UART DATA register
10. `BGE x0,x0,0` — halt

Final check: `x3 == 5` (QSPI round-trip), `x8 == 0x42` (UART byte
received), `pc == 0x24` (reached the halt loop).

### Expected output

```
x3=5(exp 5) x8=0x42(exp 0x42) pc=0x24(exp 0x24)
PASS: QSPI store/load AND UART read both verified in one program
TESTS=1 PASS=1 FAIL=0 SKIP=0
```

`FAIL=0` confirms the core correctly fetched, decoded, and executed the
program — a QSPI store/load round-trip through simulated PSRAM, and a
UART byte received through the real bit-banged serial protocol — all
through one combined program.

---

## Test 3: Full test — QSPI + UART data + UART registers

**Files:** `test_mem_full.hex` + `test_top_full.py`

The most complete test. Covers everything Tests 1 and 2 cover, plus the
UART CTRL register's enable bits, the STATUS register, the BAUD_DIV
register, and independently verifies the TX byte by decoding it directly
off the `uart_tx` pin (not just checking the register value internally).

### What it verifies

1. `ADDI x1,x0,5`
2. `LUI x2,0x1000`
3. `SW x1,x2,0`
4. `LW x3,x2,0`  — QSPI store/load round-trip
5. `LUI x4,0x04000` — UART base address
6. `ADDI x5,x0,3`
7. `SW x5,8(x4)`
8. `LW x6,8(x4)` — writes `3` (binary `11`) to CTRL, enabling both
   `rx_irq_en` and `tx_irq_en`, then reads it back to confirm it stuck
9. `ADDI x7,x0,0x42`
10. `SW x7,0(x4)` — writes byte `0x42` to DATA, triggering `UART_WRITE`;
    the testbench independently watches the `uart_tx` pin and decodes
    the serial frame to confirm `0x42` actually came out on the wire
11. `ADDI x9,x0,80`
12. `ADDI x9,x9,-1` (loop)
13. `BNE x9,x0,-4` (loop until counter hits 0) — delay while an
    externally-sent byte (`0x55`) arrives on `uart_rx`
14. `LW x8,x4,0` — UART read (RX), receives the externally sent byte
15. `LW x10,4(x4)` — reads STATUS (bit0=`tx_busy`, bit1=`rx_valid`)
16. `LW x11,12(x4)` — reads BAUD_DIV
17. `BGE x0,x0,0` — halt

Final check: `x3==5` (QSPI), `x6==3` (CTRL write/readback), `x7==0x42`
and the byte observed on `uart_tx`==`0x42` (TX, verified two ways),
`x8==0x55` (RX), `x10==0x0` (STATUS reads idle — the core always
blocks until an operation completes, so software never observes a
busy/mid-transfer state), `x11==434` (BAUD_DIV = `(50,000,000-1)/115,200`),
`pc==0x40` (reached the halt loop).

### Expected output

```
x1=5(exp 5) x2=0x1000000(exp 0x1000000) x3=5(exp 5)  -- QSPI store/load
x4=0x4000000(exp 0x4000000)  -- UART base address
x5=3(exp 3) x6=3(exp 3)  -- CTRL register write/readback
x7=0x42(exp 0x42)  -- TX byte value written to DATA
x8=0x55(exp 0x55)  -- RX byte received from uart_rx
x9=0(exp 0)  -- delay loop counter, should be 0 when done
x10=0x0(exp 0x0)  -- STATUS: bit0=tx_busy, bit1=rx_valid, both idle by now
x11=434(exp 434)  -- BAUD_DIV readback
pc=0x40(exp 0x40)  -- halt loop address
Byte actually observed on uart_tx pin: 0x42(exp 0x42)
PASS: QSPI round-trip, UART CTRL enable write/readback, UART TX (verified
directly on the pin), UART RX, STATUS, and BAUD_DIV all verified together
in one program
TESTS=1 PASS=1 FAIL=0 SKIP=0
```

---

## Switching between the tests

Edit the `Makefile`:
- Set `COCOTB_TEST_MODULES` to `test_top` (UART-only), `test_top_qspi_uart`
  (combined), or `test_top_full` (full).
- Set the `-DINIT_FILE` path to `test_mem.hex` (UART-only),
  `test_mem_qspi_uart.hex` (combined), or `test_mem_full.hex` (full).

Then re-run:

```bash
rm -rf sim_build results.xml
make
gtkwave waveform.vcd
```

## FSM states (10 states)

`IDLE=0, FETCH_REQ=1, FETCH_WAIT=2, DATA_MEM_READ=3, DATA_MEM_WRITE=4,
DATA_MEM_WAIT=5, UART_READ=6, UART_READ_BUSY=7, UART_WRITE=8,
UART_WRITE_BUSY=9`

`UART_READ`→`UART_READ_BUSY` and `UART_WRITE`→`UART_WRITE_BUSY` are both
unconditional transitions (not gated on `rx_irq`/`tx_irq`), which fixes bugs
present in an earlier version of this design.