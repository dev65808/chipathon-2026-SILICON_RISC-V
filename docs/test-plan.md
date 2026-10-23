# SILICON_RISC-V (`qspi_chip_top`) Post-Silicon Test Plan

## 1. Scope and assumptions

- **DUT:** `qspi_chip_top`, an RV32I core with QSPI flash/PSRAM controller, UART and SPI, on GF180MCU (`gf180mcu_fd_sc_mcu7t5v0`).
- **Design clock:** `CLOCK_PERIOD: 160` in your final config, so I assume about 6.25 MHz if that value is in ns. The QSPI SCK runs at half the system clock. Confirm both numbers before bring-up.
- **Reset:** `reset` is active-high (`rstn = !reset` inside the chip). This is the opposite polarity of tinyQV's `rst_n`.
- **External memory:** the [QSPI PMOD](https://github.com/mole99/qspi-pmod) has 1 flash and 2 PSRAMs. Only flash CS and RAM A CS are bonded out. RAM B CS is left unconnected in `qspi_chip_top.sv`, so you get PSRAM A only (8 MB, `0x1000000–0x17FFFFF`).
- **Code runs from flash only.** Data goes to flash (read) and PSRAM A (read/write).

### Pin map (from `info.yaml`)

| Pad | Dir | Use |
|---|---|---|
| `clk` | in (Schmitt) | System clock |
| `reset` | in (CMOS) | Active-high reset |
| `spi_data0..3` | bidir 24 mA | QSPI IO0..IO3 |
| `spi_clk_out` | out | QSPI SCK |
| `spi_flash_select` | out | Flash CS# |
| `spi_ram_a_select` | out | PSRAM A CS# |
| `uart_tx` / `uart_rx` | out / in | UART |
| `spi_select`, `disp_spi_clk_out`, `spi_mosi`, `spi_dc`, `spi_miso` | out / in | Display SPI |
| `VDD` / `VSS` | power | Core and I/O supply |

## 2. Equipment

- Bench supply with current limit and current readout, a 3.3 V or 5 V rail depending on your pad ring and board.
- Signal generator or crystal oscillator for `clk`, and a DMM.
- Logic analyzer with 8+ channels at 100 MS/s or better (Saleae or sigrok-compatible), and a scope for the clock and SCK.
- USB-UART adapter (3.3 V).
- Microcontroller as a helper for reset and flash/PSRAM setup (RP2040/Pico with MicroPython, or an Arduino), plus an optional external flash programmer.
- QSPI PMOD (16 MB flash + 2×8 MB PSRAM), or a flash and an APS6404L-style PSRAM on a breakout.
- Host machine with a `riscv32-unknown-elf` toolchain (RV32I, `-march=rv32i -mabi=ilp32`).

## 3. Test board hookup

```
 Helper MCU (Pico)              Chip under test               QSPI PMOD
 ─────────────────              ───────────────               ─────────
 GPIO ──────────► reset
 GPIO/osc ──────► clk
 GPIO x3 ◄──────► spi_data[2:0]  (drive during reset to set config)
                  spi_data[3:0] ◄──────────────────────────►  IO0..IO3
                  spi_clk_out   ─────────────────────────────► SCK
                  spi_flash_select ──────────────────────────► CS0 (Flash)
                  spi_ram_a_select ──────────────────────────► CS1 (PSRAM A)
 USB-UART RX ◄─── uart_tx
 USB-UART TX ───► uart_rx
                  VDD/VSS ◄── bench supply
```

- Pull the IO0–IO3 lines weakly high on the board (about 10 kΩ), as the PMOD does.
- Pull both CS# lines high (about 10 kΩ) so the memories stay deselected while the chip is in reset or its pads are tri-stated.
- Keep SCK and IO traces short, because the SCK fan-out matters at 3.3 V and above.
- Add 100 nF and 10 µF decoupling at the supply.

## 4. Test phases

### Phase 0: Visual and electrical sanity (no clock)

| ID | Test | Pass criteria |
|---|---|---|
| 0.1 | Inspect the package and bond wires, check for shorts VDD-VSS with a DMM | No short; resistance in the expected range |
| 0.2 | Power up with a 10 mA current limit and the clock stopped | Supply current is low (static leakage only), with no heating |
| 0.3 | Ramp the supply to nominal, with `reset` high and no clock | Idle current within the expected range; record it |
| 0.4 | Check pad levels with a DMM | Output-only pads sit at a defined level; no pad is at an unexpected rail |

### Phase 1: Clock and reset

| ID | Test | Pass criteria |
|---|---|---|
| 1.1 | Apply `clk` at 1 MHz, then step up, with `reset` high | Current rises smoothly with frequency; no latch-up |
| 1.2 | Release `reset` with the memories disconnected | The chip starts issuing QSPI cycles: `spi_flash_select` goes low and `spi_clk_out` toggles (see 2.x) |
| 1.3 | Check `spi_clk_out` frequency | Equals `clk/2` |
| 1.4 | Assert `reset` mid-run | CS# lines go high and SCK stops within a few cycles |

### Phase 2: QSPI bus bring-up with the memory model (before software)

This phase uses only the logic analyzer, with an unprogrammed or known-content flash.

| ID | Test | Pass criteria |
|---|---|---|
| 2.1 | Capture the first fetch after reset | `spi_flash_select` low, then 6 nibbles of address on IO[3:0] (24 bits), then dummy cycles, then 8 data nibbles (32-bit instruction) |
| 2.2 | Confirm the fetch address | The first `i_addr` equals the core's reset PC (check the RTL; probably `0x000000`) |
| 2.3 | Confirm the read latency setting | The data phase starts the expected number of cycles after the address phase |
| 2.4 | Repeat at several reset latency settings (`spi_data[1:0]` = 1, 2, 3) | Observed data alignment tracks the setting |
| 2.5 | Check CS# deassert gap | At least 2 system clocks between a PSRAM CS# deassert and the next select (`docs/qspi_mem_subsystem.md §9`) |

### Phase 3: Flash and PSRAM setup (details in §5 and §6)

| ID | Test | Pass criteria |
|---|---|---|
| 3.1 | Read the flash JEDEC ID using the helper MCU | Matches the datasheet |
| 3.2 | Program, then read back and verify a test image | 100% match |
| 3.3 | Enter continuous-read mode (EBh with mode bits) | Reads with no command byte work |
| 3.4 | Put the PSRAM in QPI mode (`35h`) and read its ID | KGD / ID bytes are correct |

### Phase 4: Execute from flash (CPU functional bring-up)

Use the cocotb test names in `cocotb/chip_top_tb.py` as the model for each program. Build one small binary per test (see §7 for the example programs).

| ID | Program | Pass criteria |
|---|---|---|
| 4.1 | Infinite loop (`j .`) | PC stays on the loop. The fetch stream repeats, and no write cycles occur |
| 4.2 | Load a constant and branch on it | Matches the expected trace on the analyzer |
| 4.3 | UART "hello" (`test_top_qspi_uart`) | The host terminal prints the exact string |
| 4.4 | UART echo (`test_top_uart_echo`) | Each byte typed on the host comes back unchanged |
| 4.5 | UART read/write (`test_top_uart_rw`) | A known string round-trips with no corruption |
| 4.6 | ALU self-test (add, sub, shifts, slt, logic ops) | Prints PASS over UART |
| 4.7 | Branch and jump self-test (JAL, JALR, BEQ…BGEU) | Prints PASS |
| 4.8 | Load/store from PSRAM, covering LB, LBU, LH, LHU, LW, SB, SH, SW | Prints PASS |
| 4.9 | PSRAM walking-1 and walking-0, then address-as-data | No mismatches |
| 4.10 | Display SPI (`test_top_spi_rw`) | Waveform on `spi_mosi`, `disp_spi_clk_out`, `spi_select` and `spi_dc` matches the expected bytes. If there is no display, loop `spi_mosi` back to `spi_miso` |
| 4.11 | Combined QSPI + UART + SPI (`test_top_qspi_uart_spi`) | Passes |

### Phase 5: Characterization

| ID | Test | Method |
|---|---|---|
| 5.1 | Fmax | Raise `clk` in steps until a self-test fails. Record the pass limit at each voltage |
| 5.2 | Voltage margin | Repeat 5.1 at ±10% VDD |
| 5.3 | Temperature | Optional hot/cold spray or a hot plate |
| 5.4 | Latency vs frequency | Find the minimum working `delay_cycles_cfg` at each clock rate |
| 5.5 | Power | Record supply current idle and running (loop vs memory-heavy code) |
| 5.6 | Multi-unit | Repeat the key tests (4.3, 4.8, 5.1) on every chip received |

### Phase 6: Results

- Each test records pass/fail with the date, chip ID, voltage, clock and latency.
- Keep logic-analyzer captures and UART logs for any failure.
- Compare the measured Fmax against the static timing result (zero setup/hold violations across 9 PVT corners).

## 5. Reset and boot sequence (QSPI configuration)

The controller latches its configuration from the IO pins during reset (`docs/qspi_mem_subsystem.md §7`):

- `spi_data[1:0]` is `delay_cycles_cfg` (1 to 3).
- `spi_data[2]` is `spi_clk_use_neg` (0 means the positive edge).
- Hold `reset` high for **at least 10 clock cycles** with these values stable.

Procedure:

1. Power up with `reset` high. The memories are already configured (§6).
2. Drive CS# lines high (pull-ups) and set `spi_data[3:0]` to `0b0001` for latency 1, or `0b0010` or `0b0011` for higher latency. Bit 2 stays 0.
3. Clock at least 10 times with `reset` high.
4. Release the helper MCU's drive on `spi_data[3:0]` (tri-state its pins) *before* releasing reset.
5. Bring `reset` low. The core fetches from flash address 0.

> **Check in the RTL:** the chip pads must stay input-only (`spi_data_oe = 0`) while `reset` is high so the helper MCU and the chip never drive IO lines at once. Also check how `uart_rx` idles. Confirm both before the first power-up.

Latency guidance: at ≤50 MHz SCK, a latency of 1 is typical (`qspi_ctrl.v` header). tinyQV at 64 MHz needed 2 to 3. Sweep this value (test 2.4 and 5.4).

## 6. Attaching and loading the external QSPI flash and PSRAM

### 6.1 Wiring

| Chip pad | PMOD / memory pin |
|---|---|
| `spi_data0..3` | IO0..IO3 of flash and PSRAM (shared bus) |
| `spi_clk_out` | SCK (shared) |
| `spi_flash_select` | Flash CS# |
| `spi_ram_a_select` | PSRAM A CS# |
| PSRAM B CS# | Tie high; unused |
| VDD / VSS | Memory power and ground (check voltage compatibility; many PSRAMs are 3.3 V only) |

The flash and the PSRAM share the data lines, so only one of them can drive at a time. The chip's controller arbitrates with the CS lines.

Voltage: the memories' I/O level must match the chip's pad VDD. If the pad ring runs at 5 V, add level shifters. The APS6404L is 3.3 V only.

### 6.2 Programming the flash

Choose one method.

**A. Standalone (recommended).** Program the flash before it goes on the board, or while the chip is held in reset with its pads tri-stated:

- Use a CH341A or other SPI programmer with `flashrom`, or an RP2040 running MicroPython/`pico-sdk` that bit-bangs standard SPI on IO0 (DI), IO1 (DO), SCK and CS#:

```bash
# Build the program
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T link.ld -o prog.elf start.S main.c
riscv32-unknown-elf-objcopy -O binary prog.elf prog.bin

# Program with flashrom (example for a CH341A)
flashrom -p ch341a_spi -c "<FLASH_PART>" -w prog.bin
flashrom -p ch341a_spi -c "<FLASH_PART>" -v prog.bin
```

**B. In-system from the helper MCU.** Keep the chip in reset (`reset` high, pads tri-stated, which needs the RTL check above) and let the RP2040 drive the shared bus. This is what the Tiny Tapeout demo board does.

**Image layout.** The reset PC fetches from flash `0x000000`, which is also where the 24-bit instruction address starts. Put `.text` at 0 and set the linker `ORIGIN` accordingly:

```
MEMORY {
  FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 16M
  PSRAM (rwx) : ORIGIN = 0x01000000, LENGTH = 8M
}
```

Check the actual reset vector in `rv32i_core.sv` (it may differ).

### 6.3 Leaving the flash in continuous-read mode

The controller sends no command byte on fetch. It expects the flash to already be in fast-read quad-I/O continuous mode (`docs/qspi_mem_subsystem.md §4`, "Flash assumed in continuous-read mode"):

1. Send the command `EBh` (Fast Read Quad I/O) in standard SPI. The part may first need its Quad Enable (QE) bit set in its status register (Winbond: SR2 bit 1, command `31h`).
2. Send the 24-bit address, then the mode bits (for example `0xA0`, M[7:4] = `1010`), then the dummy cycles.
3. Clock out at least one data byte, then raise CS#.

While the mode bits stay `1010`, later reads can skip the `EBh` command. The chip's next fetch will therefore work with no command byte. A power cycle of the flash clears the mode, so redo this step every power-up.

MicroPython sketch for the RP2040 (pseudo-structure, adapt pin numbers and the part's datasheet):

```python
def flash_enter_continuous():
    cs(0); spi_write(0xEB)              # Fast Read Quad I/O
    quad_write(addr=0x000000)           # 6 nibbles
    quad_write(mode=0xA0)               # continuous-read mode bits
    quad_dummy(n=4)                     # per datasheet
    quad_read(n=1)
    cs(1)                               # leave continuous mode armed
```

### 6.4 Setting up the PSRAMs

Before each power-up, with `reset` still high:

1. Hold CS# low, send `66h` (Reset Enable), toggle CS#, send `99h` (Reset), and wait at least 2 µs (APS6404L).
2. Send `35h` (Enter Quad Mode) in SPI mode. The part is now in QPI mode.
3. Read the ID in QPI mode as a check (`9Fh`).

Both flash and PSRAM keep their mode while powered, so do this once after each power-up and before releasing reset. The controller then uses QPI commands (`EBh` quad read, `38h` quad write). A write test (4.8, 4.9) confirms that setup worked.

### 6.5 Loading a program: checklist

1. Build `prog.bin`.
2. Program and verify the flash (6.2).
3. Enter continuous-read mode (6.3).
4. Put the PSRAM in QPI mode (6.4).
5. Set `spi_data[2:0]` for latency and edge, and hold `reset` high for at least 10 clocks (§5).
6. Tri-state the helper MCU pins and release `reset`.
7. Watch the UART with the terminal at the expected baud (the design baud is `CLK_HZ/BIT_RATE`; check the `uart_riscv_if` parameters against the real clock).

## 7. Software test programs to write

Keep these small and self-checking, and print PASS or FAIL over UART:

| Program | Checks |
|---|---|
| `blink_loop.S` | Fetch from flash, no data traffic |
| `uart_hello.c` | UART TX and baud divisor |
| `uart_echo.c` | UART RX path |
| `alu_test.c` | Core arithmetic and logic |
| `branch_test.c` | Control flow |
| `ram_test.c` | PSRAM word, half-word and byte access, walking 1/0, address-as-data |
| `spi_test.c` | Display SPI interface |
| `stress.c` | Mixed flash fetch and PSRAM traffic over many iterations |

The UART and SPI register addresses in your design differ from tinyQV's, so take them from `uart_riscv_if.v`, `spi_riscv_if.v` and the core's address decode. I couldn't confirm them from the files I read.

## 8. Failure triage

| Symptom | Likely cause | Check |
|---|---|---|
| No SCK activity | Reset stuck, clock missing | `reset` polarity, clock amplitude |
| Fetches happen, garbage instructions | Latency wrong, flash not in continuous mode | Sweep `spi_data[1:0]`; redo 6.3 |
| Works at low clock, fails at high | Latency or edge setting | Try a larger latency or `spi_data[2]` = 1 |
| Reads fine, writes fail | PSRAM not in QPI mode, CS# timing | Redo 6.4; check the 2-clock guard |
| UART garbage | Baud mismatch | Compare the actual clock against `CLK_HZ` |
| Hangs after the first PSRAM access | PSRAM not responding | Check the CS# wiring and voltage level |
| Supply current unusually high | Bus contention | Make sure the helper MCU released the IO lines |

## 9. Gaps to close before first silicon bring-up

- The core's reset PC and the UART/SPI base addresses (not read).
- Pad behavior during reset: whether `spi_data_oe` is 0 while `reset` is high.
- The pad ring voltage and whether the memories need level shifting.
- RAM B has no pad, so only 8 MB of PSRAM is usable.
- The chip has no debug mux like tinyQV's (`out7` plus `in3–in6`). If you want internal visibility, the logic analyzer on the QSPI bus and the UART are your only windows.
