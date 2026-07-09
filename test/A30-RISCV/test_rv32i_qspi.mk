# test_rv32i_qspi.mk — cocotb Makefile for rv32i_qspi_mem testbench
# Usage:
#   make -f test_rv32i_qspi.mk          # run all tests (Icarus Verilog)
#   make -f test_rv32i_qspi.mk SIM=verilator
#   make -f test_rv32i_qspi.mk WAVES=1  # dump VCD

SIM          ?= icarus
WAVES        ?= 0
TOPLEVEL_LANG = verilog

SRC_DIR      = $(PWD)/../../src/A30-RISCV

# RTL sources: rv32i_qspi_mem wrapper + the original qspi_controller it wraps
VERILOG_SOURCES  = $(SRC_DIR)/peri/qspi_mem/rv32i_qspi_mem.v
VERILOG_SOURCES += $(SRC_DIR)/peri/qspi_mem/qspi_ctrl.v

# Simulation model for flash/PSRAM PMOD
VERILOG_SOURCES += $(PWD)/sim_qspi.v

# Testbench top
VERILOG_SOURCES += $(PWD)/tb_rv32i_qspi.v

# Pre-loaded ROM image for instruction-fetch tests
INIT_FILE    ?= $(PWD)/test_mem.hex
COMPILE_ARGS += -DINIT_FILE=\"$(INIT_FILE)\"
COMPILE_ARGS += -I$(SRC_DIR)

TOPLEVEL = tb_rv32i_qspi
MODULE   = test_rv32i_qspi

SIM_BUILD = sim_build/rv32i_qspi

ifeq ($(WAVES),1)
COMPILE_ARGS += -DDUMP_WAVES
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
