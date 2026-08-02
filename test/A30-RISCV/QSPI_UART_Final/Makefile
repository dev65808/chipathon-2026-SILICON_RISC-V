SIM          ?= icarus
TOPLEVEL_LANG = verilog

VERILOG_SOURCES  = $(PWD)/pseudo_rand_stub.sv
VERILOG_SOURCES += $(PWD)/qspi_ctrl.v
VERILOG_SOURCES += $(PWD)/rv32i_qspi_mem.v
VERILOG_SOURCES += $(PWD)/sim_qspi.v
VERILOG_SOURCES += $(PWD)/rv32i_core.sv
VERILOG_SOURCES += $(PWD)/qspi_chip_top.sv
VERILOG_SOURCES += $(PWD)/tb_qspi_chip_top.v
VERILOG_SOURCES += $(PWD)/uart_tx.v
VERILOG_SOURCES += $(PWD)/uart_rx.v
VERILOG_SOURCES += $(PWD)/uart_riscv_if.v

INIT_FILE    ?= $(PWD)/test_mem_full.hex
COMPILE_ARGS += -DINIT_FILE=\"$(INIT_FILE)\"
COMPILE_ARGS += -I$(PWD)

TOPLEVEL = tb_qspi_chip_top
MODULE   = test_top_full
SIM_BUILD = sim_build/chiptop

include $(shell cocotb-config --makefiles)/Makefile.sim
