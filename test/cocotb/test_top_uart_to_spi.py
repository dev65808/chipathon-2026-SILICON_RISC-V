import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Default uart_riscv_if params: CLK_HZ=50_000_000, BIT_RATE=115_200
CYCLES_PER_BIT = 434

BRIDGE_BYTE = 0x99   # sent in over uart_rx -- this is the byte that should
                      # travel UART -> core register -> SPI DATA -> spi_mosi
SPI_RX_BYTE = 0xAB   # fed in over spi_miso during the SPI transfer


# ---------------------------------------------------------------------------
# UART helper -- sends one byte in over uart_rx (standard 8N1 frame)
# ---------------------------------------------------------------------------
async def hold_uart_rx(dut, bit_value, cycles):
    dut.chip_inst.uart_rx.value = bit_value
    for _ in range(cycles):
        await RisingEdge(dut.clk)

async def send_uart_byte(dut, byte_val):
    await hold_uart_rx(dut, 0, CYCLES_PER_BIT)          # start bit
    for i in range(8):
        await hold_uart_rx(dut, (byte_val >> i) & 1, CYCLES_PER_BIT)  # LSB-first
    await hold_uart_rx(dut, 1, CYCLES_PER_BIT)          # stop bit


# ---------------------------------------------------------------------------
# SPI helpers -- same pattern as test_top_spi_rw.py
# ---------------------------------------------------------------------------
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
            dut._log.info("spi_select asserted -- SPI transfer started.")
            return
        prev = cur

async def exchange_spi_bits(dut, tx_bits_out):
    for i in range(8):
        await RisingEdge(dut.chip_inst.disp_spi_clk_out)
        mosi_bit = int(dut.chip_inst.spi_mosi.value)
        tx_bits_out.append(mosi_bit)
        rx_bit = (SPI_RX_BYTE >> (7 - i)) & 1
        dut.chip_inst.spi_miso.value = rx_bit
        await FallingEdge(dut.chip_inst.disp_spi_clk_out)


# ---------------------------------------------------------------------------
# Actual test
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_uart_to_spi_bridge(dut):
    """Proves data forwarding: a byte arriving over uart_rx is read by
    firmware and written straight into the SPI DATA register, forwarding
    it out over spi_mosi -- no fixed delay loops, both waits are real
    STATUS-bit handshake polls."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.chip_inst.uart_rx.value = 1     # idle-high before anything starts
    dut.chip_inst.spi_miso.value = 0    # idle-low before anything starts

    select_result = []
    cocotb.start_soon(monitor_spi_select(dut, select_result))

    spi_tx_bits = []
    cocotb.start_soon(exchange_spi_bits(dut, spi_tx_bits))

    await Timer(200, unit="ns")  # let internal reset release first

    dut._log.info(f"Sending 0x{BRIDGE_BYTE:02x} over uart_rx -- this should be "
                  f"forwarded to SPI DATA and appear on spi_mosi...")
    await send_uart_byte(dut, BRIDGE_BYTE)
    dut._log.info("UART byte fully sent.")

    # Both loops in the firmware are real handshake polls (STATUS bits), not
    # fixed counters, but every fetch still goes through the QSPI-backed
    # instruction memory, so give a generous budget.
    await Timer(400000, unit="ns")

    x4  = xreg(dut, 4)
    x12 = xreg(dut, 12)
    x13 = xreg(dut, 13)
    x14 = xreg(dut, 14)
    x6  = xreg(dut, 6)
    x7  = xreg(dut, 7)
    x8  = xreg(dut, 8)
    x9  = xreg(dut, 9)
    final_pc = pc(dut)

    reconstructed_tx = 0
    for i, bit in enumerate(spi_tx_bits):
        reconstructed_tx |= (bit << (7 - i))

    dut._log.info(f"x4={x4:#x}(exp 0x4000000)  x12={x12:#x}(exp 0x8000000)")
    dut._log.info(f"x13={x13}(exp 2)  x14={x14}(exp 3)")
    dut._log.info(f"x6={x6}(exp 2)  -- UART STATUS masked to rx_valid")
    dut._log.info(f"x7={x7:#x}(exp {BRIDGE_BYTE:#x})  -- byte read from UART, forwarded to SPI")
    dut._log.info(f"x8={x8}(exp 0)  -- SPI STATUS masked to busy (0=done)")
    dut._log.info(f"x9={x9:#x}(exp {SPI_RX_BYTE:#x})  -- byte read back from SPI DATA")
    dut._log.info(f"pc={final_pc:#x}(exp 0x3c)")
    dut._log.info(f"Bits captured on spi_mosi: {spi_tx_bits} -> "
                  f"reconstructed 0x{reconstructed_tx:02x}(exp {BRIDGE_BYTE:#x})")

    assert x4 == 0x04000000,       "UART base address LUI failed"
    assert x12 == 0x08000000,      "SPI base address LUI failed"
    assert x13 == 2,               "SPI CONFIG value setup failed"
    assert x14 == 3,               "SPI CTRL value setup failed"
    assert x6 == 2,                "UART STATUS did not show rx_valid before proceeding"
    assert x7 == BRIDGE_BYTE,      "UART_READ did not return the byte sent over uart_rx"
    assert len(select_result) == 1,"spi_select never asserted -- SPI transfer never started"
    assert len(spi_tx_bits) == 8,  f"expected 8 bits on spi_mosi, got {len(spi_tx_bits)}"
    assert reconstructed_tx == BRIDGE_BYTE, \
        f"BRIDGE FAILED: spi_mosi carried 0x{reconstructed_tx:02x}, expected {BRIDGE_BYTE:#x} " \
        f"-- the byte read from UART was not correctly forwarded to SPI"
    assert x8 == 0,                "SPI STATUS did not clear (busy stuck high)"
    assert x9 == SPI_RX_BYTE,      f"SPI LOAD failed: x9={x9:#x}, expected {SPI_RX_BYTE:#x}"
    assert final_pc == 0x3C,       "core did not reach the halt loop"

    dut._log.info("PASS: byte received over uart_rx was correctly forwarded "
                  "by firmware into the SPI DATA register and observed "
                  "bit-for-bit on spi_mosi -- UART -> SPI bridge verified.")
