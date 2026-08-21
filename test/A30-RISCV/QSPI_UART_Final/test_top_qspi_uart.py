import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

# Default uart_riscv_if params: CLK_HZ=50_000_000, BIT_RATE=115_200
# BAUD_DIV = (CLK_HZ - 1) // BIT_RATE = 434 clock cycles per bit.
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

@cocotb.test()
async def test_core_qspi_and_uart(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.chip_inst.uart_rx.value = 1  # idle-high before anything starts
    await Timer(200, unit="ns")       # let the testbench's internal reset release first

    EXPECTED_BYTE = 0x42  # 'B'
    dut._log.info(f"Sending 0x{EXPECTED_BYTE:02x} over uart_rx ({CYCLES_PER_BIT} cycles/bit)...")
    await send_uart_byte(dut, EXPECTED_BYTE)
    dut._log.info("Byte fully sent.")

    # Give the core time to: do the QSPI store+load, finish the busy-wait
    # loop, then do the UART read and halt.
    await Timer(70000, unit="ns")

    x3 = xreg(dut, 3)   # QSPI load-back result (expect 5)
    x8 = xreg(dut, 8)   # UART read result (expect 0x42)
    final_pc = pc(dut)  # halt loop address (expect 0x24 -- 10th instruction)

    dut._log.info(f"x3={x3}(exp 5) x8={x8:#x}(exp {EXPECTED_BYTE:#x}) pc={final_pc:#x}(exp 0x24)")
    assert x3 == 5, "QSPI store/load round-trip failed"
    assert x8 == EXPECTED_BYTE, "UART_READ did not return the byte actually sent over uart_rx"
    assert final_pc == 0x24, "core did not reach the halt loop"
    dut._log.info("PASS: QSPI store/load AND UART read both verified in one program")