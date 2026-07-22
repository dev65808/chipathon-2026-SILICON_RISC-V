import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

def xreg(dut, n):
    return dut.chip_inst.core_inst.Xreg_value_a0[n].value.to_unsigned()

@cocotb.test()
async def test_core_addi_lui_sw_lw_bge(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await Timer(3200, unit="ns")
    x1 = xreg(dut, 1); x2 = xreg(dut, 2); x3 = xreg(dut, 3)
    dut._log.info(f"x1={x1}(exp5) x2={x2:#x}(exp 0x1000000) x3={x3}(exp5)")
    assert x1 == 5 and x2 == 0x1000000 and x3 == 5
    dut._log.info("PASS: chip-level structure verified correct")
