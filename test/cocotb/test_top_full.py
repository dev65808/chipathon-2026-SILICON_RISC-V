import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Default uart_riscv_if params: CLK_HZ=50_000_000, BIT_RATE=115_200
CYCLES_PER_BIT = 434

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
    """Watches uart_tx for a real transmitted frame and decodes the byte,
    proving the core's UART_WRITE actually put the correct bits on the pin
    -- not just that the FSM transitioned correctly internally."""
    # Wait for the falling edge that starts the frame (idle-high -> 0)
    prev = 1
    while True:
        await RisingEdge(dut.clk)
        try:
            cur = int(dut.chip_inst.uart_tx.value)
        except ValueError:
            cur = 1  # still X during reset -- treat as idle, keep waiting
        if prev == 1 and cur == 0:
            break
        prev = cur
    # We're at the very start of the start bit. Wait 1.5 bit periods so we
    # land safely in the MIDDLE of data bit 0, not right on a bit boundary
    # (sampling exactly on an edge is a race condition -- this was the bug).
    for _ in range(CYCLES_PER_BIT + CYCLES_PER_BIT // 2):
        await RisingEdge(dut.clk)
    byte_val = 0
    for i in range(8):
        bit = int(dut.chip_inst.uart_tx.value)
        byte_val |= (bit << i)
        for _ in range(CYCLES_PER_BIT):
            await RisingEdge(dut.clk)
    result.append(byte_val)

@cocotb.test()
async def test_core_full_uart_qspi(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.chip_inst.uart_rx.value = 1  # idle-high before anything starts

    # Watch the TX pin in the background for the entire test -- it will
    # capture whatever byte the core transmits, whenever it happens.
    tx_result = []
    cocotb.start_soon(monitor_uart_tx(dut, tx_result))

    await Timer(200, unit="ns")  # let the testbench's internal reset release first

    RX_BYTE = 0x55
    dut._log.info(f"Sending 0x{RX_BYTE:02x} over uart_rx ({CYCLES_PER_BIT} cycles/bit)...")
    await send_uart_byte(dut, RX_BYTE)
    dut._log.info("RX byte fully sent.")

    # Give the core time to: do the QSPI store+load, write+readback CTRL,
    # transmit the TX byte, finish the RX delay loop, do the UART read,
    # read STATUS, and halt.
    await Timer(150000, unit="ns")

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
    final_pc = pc(dut)

    dut._log.info(f"x1={x1}(exp 5) x2={x2:#x}(exp 0x1000000) x3={x3}(exp 5)  -- QSPI store/load")
    dut._log.info(f"x4={x4:#x}(exp 0x4000000)  -- UART base address")
    dut._log.info(f"x5={x5}(exp 3) x6={x6}(exp 3)  -- CTRL register write/readback")
    dut._log.info(f"x7={x7:#x}(exp 0x42)  -- TX byte value written to DATA")
    dut._log.info(f"x8={x8:#x}(exp {RX_BYTE:#x})  -- RX byte received from uart_rx")
    dut._log.info(f"x9={x9}(exp 0)  -- delay loop counter, should be 0 when done")
    dut._log.info(f"x10={x10:#x}(exp 0x0)  -- STATUS: bit0=tx_busy, bit1=rx_valid, both idle by now")
    dut._log.info(f"x11={x11}(exp 434)  -- BAUD_DIV readback")
    dut._log.info(f"pc={final_pc:#x}(exp 0x40)  -- halt loop address")
    if tx_result:
        dut._log.info(f"Byte actually observed on uart_tx pin: {tx_result[0]:#x}(exp 0x42)")
    else:
        dut._log.info("No byte was ever observed on uart_tx pin!")

    assert x1 == 5,               "QSPI ADDI failed"
    assert x2 == 0x1000000,       "QSPI LUI failed"
    assert x3 == 5,               "QSPI store/load round-trip failed"
    assert x4 == 0x04000000,      "UART base address LUI failed"
    assert x5 == 3,               "CTRL value setup failed"
    assert x6 == 3,               "CTRL register write/readback failed -- enable bits not sticking"
    assert x7 == 0x42,            "TX byte value setup failed"
    assert x8 == RX_BYTE,         "UART_READ did not return the byte actually sent over uart_rx"
    assert x9 == 0,               "delay loop did not complete correctly"
    assert x10 == 0x0,            "STATUS register did not read back idle (tx_busy=0, rx_valid=0) as expected"
    assert x11 == 434,            f"BAUD_DIV register read {x11}, expected 434 (=(50000000-1)//115200)"
    assert final_pc == 0x40,      "core did not reach the halt loop"
    assert len(tx_result) == 1,   "No byte was ever observed on uart_tx -- UART_WRITE may not have transmitted"
    assert tx_result[0] == 0x42,  f"uart_tx pin carried {tx_result[0]:#x}, expected 0x42"

    dut._log.info("PASS: QSPI round-trip, UART CTRL enable write/readback, "
                   "UART TX (verified directly on the pin), UART RX, STATUS, "
                   "and BAUD_DIV all verified together in one program")