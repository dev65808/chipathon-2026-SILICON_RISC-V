SIM          ?= icarus
TOPLEVEL_LANG = verilog

VERILOG_SOURCES  = $(PWD)/pseudo_rand_stub.sv
VERILOG_SOURCES += $(PWD)/../../../src/A30-RISCV/qspi_controller.v
VERILOG_SOURCES += $(PWD)/../../../src/A30-RISCV/rv32i_qspi_mem.v
VERILOG_SOURCES += $(PWD)/sim_qspi_pmod.v
VERILOG_SOURCES += $(PWD)/../../../src/A30-RISCV/rv32i_core.sv
VERILOG_SOURCES += $(PWD)/../../../src/A30-RISCV/qspi_chip_top.sv
VERILOG_SOURCES += $(PWD)/tb_qspi_chip_top.v

INIT_FILE    ?= $(PWD)/test_mem.hex
COMPILE_ARGS += -DINIT_FILE=\"$(INIT_FILE)\"
COMPILE_ARGS += -I$(PWD)
COMPILE_ARGS += -I../../../src/A30-RISCV

TOPLEVEL = tb_qspi_chip_top
MODULE   = test_top
SIM_BUILD = sim_build/chiptop

include $(shell cocotb-config --makefiles)/Makefile.sim
