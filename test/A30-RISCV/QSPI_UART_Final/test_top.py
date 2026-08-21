import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

def pc(dut):
    return dut.chip_inst.core_inst.L0_pc_a0.value.to_unsigned()

def state(dut):
    return dut.chip_inst.core_inst.L0_state_a0.value.to_unsigned()

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
async def test_core_uart_rx(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.chip_inst.uart_rx.value = 1  # idle-high before anything starts
    await Timer(200, unit="ns")       # let the testbench's internal reset release first

    EXPECTED_BYTE = 0x42  # 'B'
    dut._log.info(f"Sending 0x{EXPECTED_BYTE:02x} over uart_rx ({CYCLES_PER_BIT} cycles/bit)...")
    await send_uart_byte(dut, EXPECTED_BYTE)
    dut._log.info("Byte fully sent.")

    # Give the core time to finish its busy-wait loop and execute the LW + halt.
    await Timer(70000, unit="ns")

    x8 = xreg(dut, 8)
    final_pc = pc(dut)
    dut._log.info(f"x8={x8:#x}(exp {EXPECTED_BYTE:#x}) pc={final_pc:#x}(exp 0x14)")
    assert x8 == EXPECTED_BYTE, "UART_READ did not return the byte actually sent over uart_rx"
    assert final_pc == 0x14, "core did not reach the halt loop"
    dut._log.info("PASS: real UART RX byte correctly received via UART_READ/UART_READ_BUSY")