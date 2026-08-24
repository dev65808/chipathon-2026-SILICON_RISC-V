import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Default uart_riscv_if params: CLK_HZ=50_000_000, B_RATE=115_200
CYCLES_PER_BIT = 434

# Sets the physical uart_rx pin to bit_value (0 or 1), then just waits, clock edge by clock edge, for cycles cycles — holding that bit steady for the full duration of one UART bit period. This is the lowest-level building block: "put this voltage level on the pin for this long."
async def hold_uart_rx(dut, bit_value, cycles):
    dut.chip_inst.uart_rx.value = bit_value
    for _ in range(cycles):
        await RisingEdge(dut.clk)

# Builds a full standard UART frame: start bit (always 0) → 8 data bits, sent LSB-first ((byte_val >> i) & 1 peels off bit 0, then bit 1, then bit 2...) → stop bit (always 1, matches the idle-high line state). This is the test acting as an external device sending a byte into your core's uart_rx pin, exactly the way a real device would.
async def send_uart_byte(dut, byte_val):
    # Standard 8N1 frame: start bit (0), 8 data bits LSB-first, stop bit (1).
    await hold_uart_rx(dut, 0, CYCLES_PER_BIT)
    for i in range(8):
        await hold_uart_rx(dut, (byte_val >> i) & 1, CYCLES_PER_BIT)
    await hold_uart_rx(dut, 1, CYCLES_PER_BIT)


# Runs continuously in the background, sampling uart_tx every clock edge, watching for a 1-to-0 transition — that's the start bit of a new transmission. try/except handles the case where the signal is X (undefined) early in simulation before reset settles. Once a falling edge is seen, the loop breaks out.
async def monitor_uart_tx(dut, result):
    """Watches uart_tx for a real transmitted frame and decodes the byte --
    this is the STORE-instruction proof: did SW actually put the right bits
    on the physical pin, not just update an internal register."""
    prev = 1
    while True:
        await RisingEdge(dut.clk)
        try:
            cur = int(dut.chip_inst.uart_tx.value)
        except ValueError:
            cur = 1
        if prev == 1 and cur == 0:
            break
        prev = cur

# Skips ahead one and a half bit-periods — landing right in the middle of the first data bit, which is the safest place to sample a UART line (avoids reading right at a transition edge).
    for _ in range(CYCLES_PER_BIT + CYCLES_PER_BIT // 2):
        await RisingEdge(dut.clk)

# Reads 8 bits, one bit-period apart, reconstructing the transmitted byte LSB-first (mirror image of how send_uart_byte sent it) — same shift-and-OR technique for 32-bit assembly, just building one byte instead of a 32-bit word. The finished byte gets appended to result (a list, passed in by reference, so the main test can read it back).
    byte_val = 0
    for i in range(8):
        bit = int(dut.chip_inst.uart_tx.value)
        byte_val |= (bit << i)
        for _ in range(CYCLES_PER_BIT):
            await RisingEdge(dut.clk)
    result.append(byte_val)


# Actual test

@cocotb.test()
async def test_uart_load_store(dut):
    """Proof of the two things being checked right now:
    1. STORE (SW x7,0(x4)): does a value written from a CPU register
       actually get transmitted correctly out of uart_tx?
    2. LOAD (LW x8,0(x4)): does a byte received on uart_rx actually
       get written correctly into the destination register (x8)?
    No QSPI instructions in this program -- pure UART isolation."""
    
    # coco tb actually starts to runs
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())


# Sets the RX line to its correct idle state before anything else happens — a real UART line sits high when nothing is being sent.
    dut.chip_inst.uart_rx.value = 1  # idle-high before anything starts

# Creates an empty list to catch whatever byte gets transmitted, then launches monitor_uart_tx as a background task — it now watches uart_tx continuously, in parallel with everything else that follows.
    tx_result = []
    cocotb.start_soon(monitor_uart_tx(dut, tx_result))

# Waits a fixed 200 ns before doing anything else, giving your core's internal reset logic time to finish and start executing from address 0.
    await Timer(200, unit="ns")  # let internal reset release first


# Sends the byte 0x55 into the core over uart_rx — this is the byte your program's LW x8,0(x4) is meant to pick up. dut._log.info just prints a message into the simulation log, not functional — pure documentation of what's happening.
    RX_BYTE = 0x55
    dut._log.info(f"Sending 0x{RX_BYTE:02x} over uart_rx (this is what the LOAD instruction should pick up)...")
    await send_uart_byte(dut, RX_BYTE)
    dut._log.info("RX byte fully sent -- now waiting for the program's delay loop and LW to run.")


# Waits 120,000 ns of simulated time — long enough for the core to finish writing CTRL, transmitting 0x42, running the 80-iteration delay loop, and executing the final LW, before the test checks any results.
    # Give the core time to: write CTRL, STORE 0x42 (triggers TX), run the
    # 80-cycle delay loop, then LOAD the RX byte, then halt.
    await Timer(120000, unit="ns")

    x4 = xreg(dut, 4)
    x5 = xreg(dut, 5)
    x7 = xreg(dut, 7)
    x8 = xreg(dut, 8)
    final_pc = pc(dut)

    dut._log.info(f"x4={x4:#x}(exp 0x4000000)  -- UART base address")
    dut._log.info(f"x5={x5}(exp 3)  -- CTRL value written")
    dut._log.info(f"x7={x7:#x}(exp 0x42)  -- STORE: byte written to DATA (should appear on uart_tx)")
    dut._log.info(f"x8={x8:#x}(exp {RX_BYTE:#x})  -- LOAD: byte read from DATA, written into destination register")
    dut._log.info(f"pc={final_pc:#x}(exp 0x24)  -- halt loop address")
    if tx_result:
        dut._log.info(f"Byte actually observed on uart_tx pin: {tx_result[0]:#x}(exp 0x42)")
    else:
        dut._log.info("No byte was ever observed on uart_tx pin!")

    assert x4 == 0x04000000,      "UART base address LUI failed"
    assert x5 == 3,               "CTRL write failed"
    assert x7 == 0x42,            "TX byte setup failed"
    assert x8 == RX_BYTE,         "LOAD FAILED: uart_rx byte was not correctly written into the destination register x8"
    assert final_pc == 0x24,      "core did not reach the halt loop"
    assert len(tx_result) == 1,   "STORE FAILED: no byte was ever observed on uart_tx -- SW did not transmit"
    assert tx_result[0] == 0x42,  f"STORE FAILED: uart_tx carried {tx_result[0]:#x}, expected 0x42"

    dut._log.info("PASS: STORE instruction correctly transmitted 0x42 out of uart_tx, "
                   "AND LOAD instruction correctly wrote the received 0x55 into destination register x8.")
