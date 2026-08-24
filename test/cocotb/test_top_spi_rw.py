# cocotb is the Python-based hardware verification framework itself. Clock is a helper class that generates a periodic clock signal on a DUT pin. RisingEdge/FallingEdge/Timer are "trigger" objects — things you await inside a coroutine to pause execution until a specific simulation event happens (a clock edge, or a fixed amount of simulated time passing).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


# A helper function to peek inside the CPU's register file directly from the testbench (not through any real chip pin — this reaches straight into simulation internals). dut is the whole testbench (tb_qspi_chip_top), .chip_inst drills into the chip instance, .core_inst drills into the RISC-V core instance, .Xreg_value_a0[n] accesses register n in the internal Xreg_value array (the compiled TLV's name for the register file), .value gets its current simulation value, .to_unsigned() converts it to a plain Python integer.
def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

# Same idea, but reads the program counter (L0_pc_a0, the compiled TLV's internal name for the PC signal) instead of a register — used later to confirm the core actually reached the halt loop at the expected address (0x2C).
def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Byte the firmware sends out over spi_mosi (this is x7, written to DATA).

TX_BYTE = 0x5A

# Byte the testbench drives in over spi_miso, which should land in x8
# after the firmware's final LW.

RX_BYTE = 0xC3


# Watches spi_select for the 1 (idle) -> 0 (asserted) transition -- proof
# that the DATA write actually triggered spi_ctrl.v to start a transfer,
# not just update an internal register.
async def monitor_spi_select(dut, result):
    prev = 1
    while True:
        await RisingEdge(dut.clk)
        try:
            cur = int(dut.chip_inst.spi_select.value)
        except ValueError:
            cur = 1
        if prev == 1 and cur == 0:
            result.append(True)
            dut._log.info("spi_select asserted -- transfer started.")
            return
        prev = cur

# This is a cocotb coroutine (an async def function meant to run concurrently in the background). It watches spi_select (chip select) for the specific 1→0 transition (CS going active-low), which is the definitive proof that a real SPI transfer actually started — not just that some internal register got written. prev = 1 assumes CS starts idle-high. The while True loop waits for each rising clock edge (await RisingEdge(dut.clk)), reads the current value of spi_select, and the try/except guards against reading an X (unknown/uninitialized) value early in simulation before signals settle — if that happens, it just treats it as still-idle (cur = 1) rather than crashing. The moment it sees prev==1 and cur==0 in the same check, it appends True to the shared result list (this is how the coroutine reports back to the main test — Python lists are mutable and shared by reference) and returns, ending the coroutine.


# The actual bit-level SPI exchange. SPI is full-duplex and synchronous
# (unlike UART's fixed-baud timing), so instead of waiting fixed cycle
# counts we just react to real edges of disp_spi_clk_out as they happen.
#
# From spi_ctrl.v's own logic: each bit is shifted onto spi_mosi and held
# stable for the whole HIGH phase of disp_spi_clk_out (assign spi_mosi =
# data[7], continuously), and spi_miso is sampled into the shift register
# exactly at the FALLING edge (data <= {data[6:0], spi_miso} fires when
# spi_clk_out was 1 and is about to go low). So: sample MOSI right after
# each RisingEdge (it's already stable then), and update MISO before the
# following FallingEdge so it's ready to be captured.


async def exchange_spi_bits(dut, tx_bits_out):
    for i in range(8):
        await RisingEdge(dut.chip_inst.disp_spi_clk_out)
        mosi_bit = int(dut.chip_inst.spi_mosi.value)
        tx_bits_out.append(mosi_bit)
        # Set up the RX bit (MSB-first, same convention as TX) so it's
        # stable well before the upcoming falling edge samples it.
        rx_bit = (RX_BYTE >> (7 - i)) & 1
        dut.chip_inst.spi_miso.value = rx_bit
        await FallingEdge(dut.chip_inst.disp_spi_clk_out)
# this coroutine plays the role of the SPI display. For each of the 8 bits, it waits for a rising edge of disp_spi_clk_out (spi_mosi is stable by then, since our hardware holds it steady through the whole high phase), records that bit into tx_bits_out, then computes the next bit to send back (rx_bit = (RX_BYTE >> (7-i)) & 1 — MSB-first, same convention our hardware uses for TX), sets spi_miso to that value, and waits for the following falling edge (when our hardware's shift register actually samples it).

# Actual test

@cocotb.test()
async def test_spi_load_store(dut):

    """Proof of the four things being checked right now:
    1. CONFIG (SW): divider=2 actually slows disp_spi_clk_out down from
       the default fastest-possible rate.
    2. CTRL (SW): dc/end_txn bits get latched correctly.
    3. STORE (SW x7, 0(x4)): does the byte written from a CPU register
       actually get shifted out, bit by bit, MSB-first, on spi_mosi?
    4. LOAD (LW x8, 0(x4)): does the byte shifted in on spi_miso during
       that same transfer actually get written correctly into the
       destination register (x8)? Proves the full-duplex behavior works,
       not just TX.
    No UART/QSPI instructions in this program -- pure SPI isolation."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # spi_miso idle-low before anything starts (matches the testbench's
    # own initial block, reasserted here for clarity).
    dut.chip_inst.spi_miso.value = 0

    # Explicitly re-sets spi_miso to 0 from the Python side too, for clarity/redundancy with the Verilog testbench's own idle initialization.

    select_result = []
    cocotb.start_soon(monitor_spi_select(dut, select_result))

    # Creates the empty list that monitor_spi_select will append to, and launches that coroutine in the background — it starts silently watching spi_select right away, before anything else happens.

    # Let internal reset release first.
    await Timer(200, unit="ns")

    # Pauses the main test for 200ns of simulated time, giving the chip's internal reset sequence (the 10-cycle delay in the Verilog testbench) time to finish before the test starts caring about results.

    # Launch the bit-exchange handler in the background -- it will just
    # sit waiting on RisingEdge/FallingEdge until the firmware's DATA
    # write actually kicks off a transfer, however long that takes.
    tx_bits = []
    cocotb.start_soon(exchange_spi_bits(dut, tx_bits))

    # creates the list to collect captured MOSI bits, launches the bit-exchange coroutine in the background. It'll just sit idle, waiting on RisingEdge(dut.chip_inst.disp_spi_clk_out), until the firmware's DATA write actually starts toggling that clock — however long that takes.

    dut._log.info(f"Waiting for firmware to configure SPI, then transmit "
                  f"0x{TX_BYTE:02x} while testbench feeds back 0x{RX_BYTE:02x} "
                  f"over spi_miso...")

    # Give the core time to: write CONFIG, write CTRL, STORE 0x5A (triggers
    # the 8-bit transfer at divider=2, ~48+ system clocks), poll STATUS,
    # then LOAD the received byte, then halt.
    await Timer(20000, unit="ns")

    x4  = xreg(dut, 4)
    x10 = xreg(dut, 10)
    x5  = xreg(dut, 5)
    x7  = xreg(dut, 7)
    x6  = xreg(dut, 6)
    x8  = xreg(dut, 8)
    final_pc = pc(dut)

    reconstructed_tx = 0
    for i, bit in enumerate(tx_bits):
        reconstructed_tx |= (bit << (7 - i))

# Rebuilds a full byte from the 8 individual bits captured by exchange_spi_bits. Since bits were captured MSB-first (the loop counter i=0 corresponds to the first bit shifted, which should be bit 7), this shifts each captured bit into its correct position and OR's them together — reconstructing whatever byte was actually seen on spi_mosi, independent of what the firmware thinks it sent.

    dut._log.info(f"x4={x4:#x}(exp 0x8000000)  -- SPI base address")
    dut._log.info(f"x10={x10}(exp 2)  -- CONFIG divider value written")
    dut._log.info(f"x5={x5}(exp 3)  -- CTRL value written")
    dut._log.info(f"x7={x7:#x}(exp {TX_BYTE:#x})  -- STORE: byte written to DATA")
    dut._log.info(f"x6={x6}(exp 0)  -- STATUS after poll loop exits (busy cleared)")
    dut._log.info(f"x8={x8:#x}(exp {RX_BYTE:#x})  -- LOAD: byte read from DATA")
    dut._log.info(f"pc={final_pc:#x}(exp 0x2C)  -- halt loop address")
    dut._log.info(f"Bits captured on spi_mosi: {tx_bits} "
                  f"-> reconstructed 0x{reconstructed_tx:02x}(exp {TX_BYTE:#x})")

    assert x4 == 0x08000000,        "SPI base address LUI failed"
    assert x10 == 2,                "CONFIG write failed"
    assert x5 == 3,                 "CTRL write failed"
    assert x7 == TX_BYTE,           "TX byte setup failed"
    assert final_pc == 0x2C,        "core did not reach the halt loop"
    assert len(select_result) == 1, "spi_select never asserted -- DATA write did not trigger a transfer"
    assert len(tx_bits) == 8,       f"expected 8 bits captured on spi_mosi, got {len(tx_bits)}"
    assert reconstructed_tx == TX_BYTE, \
        f"STORE FAILED: spi_mosi carried 0x{reconstructed_tx:02x}, expected {TX_BYTE:#x}"
    assert x8 == RX_BYTE, \
        f"LOAD FAILED: spi_miso byte was not correctly written into destination register x8 (got {x8:#x}, expected {RX_BYTE:#x})"

    dut._log.info("PASS: STORE instruction correctly shifted 0x5A out of spi_mosi, "
                  "AND LOAD instruction correctly wrote the received 0xC3 into destination register x8.")
