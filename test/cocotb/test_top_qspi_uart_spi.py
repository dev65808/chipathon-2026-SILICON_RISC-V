import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Default uart_riscv_if params: CLK_HZ=50_000_000, BIT_RATE=115_200
CYCLES_PER_BIT = 434

UART_TX_BYTE = 0x42   # written by firmware to UART DATA (expected on uart_tx pin)
UART_RX_BYTE = 0x55   # sent in by the testbench over uart_rx
SPI_TX_BYTE  = 0x5A   # written by firmware to SPI DATA (expected on spi_mosi)
SPI_RX_BYTE  = 0xC3   # fed in by the testbench over spi_miso


# ---------------------------------------------------------------------------
# UART helpers (same pattern as test_top_full.py / test_top_uart_rw.py)
# ---------------------------------------------------------------------------
async def hold_uart_rx(dut, bit_value, cycles):
    dut.chip_inst.uart_rx.value = bit_value
    for _ in range(cycles):
        await RisingEdge(dut.clk)

async def send_uart_byte(dut, byte_val):
    # Standard 8N1 frame: start bit (0), 8 data bits LSB-first, stop bit (1).
    await hold_uart_rx(dut, 0, CYCLES_PER_BIT)
    for i in range(8):
        await hold_uart_rx(dut, (byte_val >> i) & 1, CYCLES_PER_BIT)
    await hold_uart_rx(dut, 1, CYCLES_PER_BIT)

async def monitor_uart_tx(dut, result):
    """Watches uart_tx for a real transmitted frame and decodes the byte."""
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
    # Land in the middle of data bit 0 (1.5 bit periods after the start edge).
    for _ in range(CYCLES_PER_BIT + CYCLES_PER_BIT // 2):
        await RisingEdge(dut.clk)
    byte_val = 0
    for i in range(8):
        bit = int(dut.chip_inst.uart_tx.value)
        byte_val |= (bit << i)
        for _ in range(CYCLES_PER_BIT):
            await RisingEdge(dut.clk)
    result.append(byte_val)


# ---------------------------------------------------------------------------
# SPI helpers (same pattern as test_top_spi_rw.py)
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
async def test_core_qspi_uart_spi(dut):
    """Runs QSPI PSRAM store/load, full UART TX+RX+STATUS+BAUD_DIV, and
    full SPI TX+RX -- all three peripherals verified in a single firmware
    image on the SPI-enabled core."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.chip_inst.uart_rx.value = 1     # idle-high before anything starts
    dut.chip_inst.spi_miso.value = 0    # idle-low before anything starts

    # Background watchers -- each just waits until the firmware actually
    # triggers its half of the exchange, however long that takes.
    tx_result = []
    cocotb.start_soon(monitor_uart_tx(dut, tx_result))

    select_result = []
    cocotb.start_soon(monitor_spi_select(dut, select_result))

    spi_tx_bits = []
    cocotb.start_soon(exchange_spi_bits(dut, spi_tx_bits))

    await Timer(200, unit="ns")  # let internal reset release first

    dut._log.info(f"Sending UART RX byte 0x{UART_RX_BYTE:02x} ({CYCLES_PER_BIT} cycles/bit)...")
    await send_uart_byte(dut, UART_RX_BYTE)
    dut._log.info("UART RX byte fully sent.")

    # Give the core time to: finish QSPI store/load, UART CTRL/TX/delay/RX/
    # STATUS/BAUD_DIV, then SPI CONFIG/CTRL/TX/poll/RX, then reach halt.
    # Every instruction fetch goes through the QSPI controller (~30+ system
    # clock cycles per rv32i_qspi_mem.v's own header comment), and the
    # 400-iteration UART delay loop alone is 800 fetches -- so this needs a
    # much larger budget than a QSPI-free program would.
    await Timer(700000, unit="ns")

    x1  = xreg(dut, 1)
    x2  = xreg(dut, 2)
    x3  = xreg(dut, 3)
    x4  = xreg(dut, 4)
    x5  = xreg(dut, 5)
    x6  = xreg(dut, 6)
    x7  = xreg(dut, 7)
    x8  = xreg(dut, 8)
    x9  = xreg(dut, 9)
    x10 = xreg(dut, 10)
    x11 = xreg(dut, 11)
    x12 = xreg(dut, 12)
    x13 = xreg(dut, 13)
    x14 = xreg(dut, 14)
    x15 = xreg(dut, 15)
    x16 = xreg(dut, 16)
    x17 = xreg(dut, 17)
    final_pc = pc(dut)

    reconstructed_spi_tx = 0
    for i, bit in enumerate(spi_tx_bits):
        reconstructed_spi_tx |= (bit << (7 - i))

    dut._log.info(f"-- QSPI --  x1={x1}(exp 5) x2={x2:#x}(exp 0x1000000) x3={x3}(exp 5)")
    dut._log.info(f"-- UART --  x4={x4:#x}(exp 0x4000000) x5={x5}(exp 3) x6={x6}(exp 3) "
                  f"x7={x7:#x}(exp 0x42) x8={x8:#x}(exp {UART_RX_BYTE:#x}) x9={x9}(exp 0) "
                  f"x10={x10:#x} x11={x11}(exp 434)")
    dut._log.info(f"-- SPI  --  x12={x12:#x}(exp 0x8000000) x13={x13}(exp 2) x14={x14}(exp 3) "
                  f"x15={x15:#x}(exp 0x5a) x16={x16}(exp 0) x17={x17:#x}(exp {SPI_RX_BYTE:#x})")
    dut._log.info(f"pc={final_pc:#x}(exp 0x6c)")
    if tx_result:
        dut._log.info(f"Byte observed on uart_tx pin: {tx_result[0]:#x}(exp 0x42)")
    else:
        dut._log.info("No byte was ever observed on uart_tx pin!")
    dut._log.info(f"Bits captured on spi_mosi: {spi_tx_bits} -> reconstructed 0x{reconstructed_spi_tx:02x}(exp 0x5a)")

    # --- QSPI assertions ---
    assert x1 == 5,               "QSPI ADDI failed"
    assert x2 == 0x01000000,      "QSPI LUI (PSRAM A base) failed"
    assert x3 == 5,               "QSPI store/load round-trip failed"

    # --- UART assertions ---
    assert x4 == 0x04000000,      "UART base address LUI failed"
    assert x5 == 3,               "UART CTRL value setup failed"
    assert x6 == 3,               "UART CTRL write/readback failed"
    assert x7 == 0x42,            "UART TX byte setup failed"
    assert x8 == UART_RX_BYTE,    "UART_READ did not return the byte sent over uart_rx"
    assert x9 == 0,               "UART delay loop did not complete correctly"
    assert x11 == 434,            f"UART BAUD_DIV read {x11}, expected 434"
    assert len(tx_result) == 1,   "No byte was ever observed on uart_tx pin"
    assert tx_result[0] == 0x42,  f"uart_tx pin carried {tx_result[0]:#x}, expected 0x42"

    # --- SPI assertions ---
    assert x12 == 0x08000000,     "SPI base address LUI failed"
    assert x13 == 2,              "SPI CONFIG value setup failed"
    assert x14 == 3,              "SPI CTRL value setup failed"
    assert x15 == SPI_TX_BYTE,    "SPI TX byte setup failed"
    assert len(select_result) == 1, "spi_select never asserted -- SPI transfer never started"
    assert len(spi_tx_bits) == 8, f"expected 8 bits on spi_mosi, got {len(spi_tx_bits)}"
    assert reconstructed_spi_tx == SPI_TX_BYTE, \
        f"SPI STORE failed: spi_mosi carried 0x{reconstructed_spi_tx:02x}, expected {SPI_TX_BYTE:#x}"
    assert x17 == SPI_RX_BYTE,    f"SPI LOAD failed: x17={x17:#x}, expected {SPI_RX_BYTE:#x}"

    # --- Program completion ---
    assert final_pc == 0x6C,      "core did not reach the halt loop"

    dut._log.info("PASS: QSPI store/load, full UART TX+RX+STATUS+BAUD_DIV, "
                  "and full SPI TX+RX all verified together in one program "
                  "on the SPI-enabled core.")
