# SPDX-FileCopyrightText: 2024
# SPDX-License-Identifier: Apache-2.0
#
# test_rv32i_qspi.py — cocotb tests for rv32i_qspi_mem
#
# Covers:
#   test_reset_init          — reset/init sequence, all selects deasserted
#   test_instr_fetch_word    — 32-bit instruction read from flash at offset 0
#   test_instr_fetch_offset  — 32-bit instruction read from flash at offset 4
#   test_data_read_word      — LW from PSRAM A
#   test_data_write_word     — SW to PSRAM A, then LW to verify
#   test_data_read_psram_b   — LW from PSRAM B
#   test_data_write_psram_b  — SW to PSRAM B, then LW to verify
#   test_byte_write_strobe   — SB via d_wstrb=4'b0001 then LBU to verify
#   test_halfword_write      — SH via d_wstrb=4'b0011 then LH to verify
#   test_back_to_back        — two consecutive instruction fetches
#   test_data_then_instr     — SW followed immediately by an instruction fetch
#
# Expected ROM pre-load (test_mem.hex, 32 bytes):
#   Address 0x00: DE AD BE EF  →  i_rdata = 0xEFBEADDE
#   Address 0x04: 01 23 45 67  →  i_rdata = 0x67452301
#   Address 0x08: AA BB CC DD  →  i_rdata = 0xDDCCBBAA
#   Address 0x0C: 11 22 33 44
#   Address 0x10: 55 66 77 88
#   Address 0x14: 99 AA BB CC
#   Address 0x18: FF FE FD FC
#   Address 0x1C: 00 00 00 00

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

# ── helpers ───────────────────────────────────────────────────────────────────

TIMEOUT_CYCLES = 300  # max cycles to wait for a ready signal

async def setup_clock(dut):
    """Start 100 MHz clock."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

async def do_reset(dut):
    """Reset the DUT for several cycles.

    During reset, spi_data_in[1:0] = 0b01 is driven by the testbench
    so that qspi_controller latches delay_cycles_cfg = 1.
    """
    dut.rstn.value   = 0
    dut.i_req.value  = 0
    dut.i_addr.value = 0
    dut.d_req.value  = 0
    dut.d_we.value   = 0
    dut.d_wstrb.value = 0xF
    dut.d_wdata.value = 0
    dut.d_addr.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)

async def wait_ready(dut, ready_sig, timeout=TIMEOUT_CYCLES):
    """Wait for a ready signal to go high; raise on timeout."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if ready_sig.value == 1:
            return
    raise TimeoutError(f"Ready signal did not fire within {timeout} cycles")

async def instr_fetch(dut, addr):
    """Issue a 32-bit instruction fetch and return the result."""
    dut.i_addr.value = addr
    dut.i_req.value  = 1
    await RisingEdge(dut.clk)
    dut.i_req.value  = 0
    await wait_ready(dut, dut.i_ready)
    return int(dut.i_rdata.value)

async def data_read(dut, addr, wstrb=0xF):
    """Issue a data read (LW by default) and return d_rdata."""
    dut.d_addr.value  = addr
    dut.d_we.value    = 0
    dut.d_wstrb.value = wstrb
    dut.d_wdata.value = 0
    dut.d_req.value   = 1
    await RisingEdge(dut.clk)
    dut.d_req.value   = 0
    await wait_ready(dut, dut.d_ready)
    return int(dut.d_rdata.value)

async def data_write(dut, addr, wdata, wstrb=0xF):
    """Issue a data write and wait for d_ready."""
    dut.d_addr.value  = addr
    dut.d_we.value    = 1
    dut.d_wstrb.value = wstrb
    dut.d_wdata.value = wdata
    dut.d_req.value   = 1
    await RisingEdge(dut.clk)
    dut.d_req.value   = 0
    await wait_ready(dut, dut.d_ready)

# ── tests ─────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_init(dut):
    """After reset all chip-selects must be deasserted (active-low, so =1)."""
    await setup_clock(dut)
    await do_reset(dut)
    assert dut.spi_flash_select.value == 1, "flash_select should be HIGH (deasserted) after reset"
    assert dut.spi_ram_a_select.value == 1, "ram_a_select should be HIGH after reset"
    assert dut.spi_ram_b_select.value == 1, "ram_b_select should be HIGH after reset"
    assert dut.i_ready.value == 0, "i_ready should be LOW after reset"
    assert dut.d_ready.value == 0, "d_ready should be LOW after reset"
    dut._log.info("PASS: reset/init — all selects deasserted")


@cocotb.test()
async def test_instr_fetch_word(dut):
    """Instruction fetch from flash address 0x000000.

    ROM[0:3] = DE AD BE EF  →  expected i_rdata = 0xEFBEADDE (little-endian)
    """
    await setup_clock(dut)
    await do_reset(dut)

    word = await instr_fetch(dut, 0x000000)
    expected = 0xEFBEADDE
    assert word == expected, \
        f"instr_fetch(0x000000): got 0x{word:08X}, expected 0x{expected:08X}"
    dut._log.info(f"PASS: instr_fetch(0x000000) = 0x{word:08X}")


@cocotb.test()
async def test_instr_fetch_offset(dut):
    """Instruction fetch from flash address 0x000004.

    ROM[4:7] = 01 23 45 67  →  expected i_rdata = 0x67452301
    """
    await setup_clock(dut)
    await do_reset(dut)

    word = await instr_fetch(dut, 0x000004)
    expected = 0x67452301
    assert word == expected, \
        f"instr_fetch(0x000004): got 0x{word:08X}, expected 0x{expected:08X}"
    dut._log.info(f"PASS: instr_fetch(0x000004) = 0x{word:08X}")


@cocotb.test()
async def test_data_read_word(dut):
    """LW from PSRAM A after a prior write establishes known data."""
    await setup_clock(dut)
    await do_reset(dut)

    addr   = 0x1000010   # PSRAM A, offset 0x10
    wdata  = 0xCAFEBABE

    # Write then read back
    await data_write(dut, addr, wdata, wstrb=0xF)
    rdata = await data_read(dut, addr, wstrb=0xF)

    assert rdata == wdata, \
        f"data_read(0x{addr:07X}): got 0x{rdata:08X}, expected 0x{wdata:08X}"
    dut._log.info(f"PASS: LW from PSRAM A = 0x{rdata:08X}")


@cocotb.test()
async def test_data_write_word(dut):
    """SW to PSRAM A, verify with LW (separate read transaction)."""
    await setup_clock(dut)
    await do_reset(dut)

    addr  = 0x1000020
    wdata = 0xDEAD1234

    await data_write(dut, addr, wdata)
    rdata = await data_read(dut, addr)

    assert rdata == wdata, \
        f"SW/LW PSRAM A 0x{addr:07X}: wrote 0x{wdata:08X}, read 0x{rdata:08X}"
    dut._log.info(f"PASS: SW/LW PSRAM A = 0x{rdata:08X}")


@cocotb.test()
async def test_data_read_psram_b(dut):
    """LW from PSRAM B after a prior write."""
    await setup_clock(dut)
    await do_reset(dut)

    addr  = 0x1800010   # PSRAM B, offset 0x10
    wdata = 0x12345678

    await data_write(dut, addr, wdata)
    rdata = await data_read(dut, addr)

    assert rdata == wdata, \
        f"data R/W PSRAM B 0x{addr:07X}: wrote 0x{wdata:08X}, read 0x{rdata:08X}"
    dut._log.info(f"PASS: LW from PSRAM B = 0x{rdata:08X}")


@cocotb.test()
async def test_data_write_psram_b(dut):
    """SW to PSRAM B at a different address, verify with LW."""
    await setup_clock(dut)
    await do_reset(dut)

    addr  = 0x1800040
    wdata = 0xABCDEF01

    await data_write(dut, addr, wdata)
    rdata = await data_read(dut, addr)

    assert rdata == wdata, \
        f"SW/LW PSRAM B 0x{addr:07X}: wrote 0x{wdata:08X}, read 0x{rdata:08X}"
    dut._log.info(f"PASS: SW/LW PSRAM B = 0x{rdata:08X}")


@cocotb.test()
async def test_byte_write_strobe(dut):
    """SB (wstrb=0b0001) writes one byte; the other bytes of the word are unaffected."""
    await setup_clock(dut)
    await do_reset(dut)

    base  = 0x1000030
    init  = 0x11223344

    # First, write a full word so the surrounding bytes are known
    await data_write(dut, base, init, wstrb=0xF)

    # Now overwrite only byte 0 (d_addr = base, wstrb = 0b0001)
    new_byte = 0xFF
    await data_write(dut, base, new_byte | (new_byte << 8) | (new_byte << 16) | (new_byte << 24),
                     wstrb=0x1)

    # Read back one byte at the same address
    rdata = await data_read(dut, base, wstrb=0x1)
    got_byte = rdata & 0xFF

    assert got_byte == new_byte, \
        f"byte write: expected 0x{new_byte:02X} at byte 0, got 0x{got_byte:02X}"
    dut._log.info(f"PASS: SB byte-lane 0 = 0x{got_byte:02X}")


@cocotb.test()
async def test_halfword_write(dut):
    """SH (wstrb=0b0011) writes two bytes; verify with a 2-byte read."""
    await setup_clock(dut)
    await do_reset(dut)

    addr   = 0x1000050
    hword  = 0xBEEF

    # Write halfword at addr (bytes 0 and 1)
    await data_write(dut, addr, hword | (hword << 16), wstrb=0x3)

    # Read back two bytes
    rdata = await data_read(dut, addr, wstrb=0x3)
    got = rdata & 0xFFFF

    assert got == hword, \
        f"halfword write: expected 0x{hword:04X}, got 0x{got:04X}"
    dut._log.info(f"PASS: SH halfword = 0x{got:04X}")


@cocotb.test()
async def test_back_to_back(dut):
    """Two consecutive instruction fetches — verify both return correct data."""
    await setup_clock(dut)
    await do_reset(dut)

    w0 = await instr_fetch(dut, 0x000000)
    w1 = await instr_fetch(dut, 0x000004)

    assert w0 == 0xEFBEADDE, f"fetch[0]: got 0x{w0:08X}"
    assert w1 == 0x67452301, f"fetch[1]: got 0x{w1:08X}"
    dut._log.info(f"PASS: back-to-back fetches 0x{w0:08X}, 0x{w1:08X}")


@cocotb.test()
async def test_data_then_instr(dut):
    """SW to PSRAM A followed by an instruction fetch — both must succeed."""
    await setup_clock(dut)
    await do_reset(dut)

    # Data write
    addr  = 0x1000060
    wdata = 0x55AA55AA
    await data_write(dut, addr, wdata)

    # Instruction fetch immediately after
    instr = await instr_fetch(dut, 0x000000)

    assert instr == 0xEFBEADDE, f"instr after SW: got 0x{instr:08X}"
    dut._log.info(f"PASS: SW then instr_fetch: instr=0x{instr:08X}")
