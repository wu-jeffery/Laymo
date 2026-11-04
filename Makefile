VERILATOR ?= verilator

GEMM_RTL = rtl/mac.sv rtl/systolic_array.sv rtl/skew_buffer.sv \
	rtl/array_scheduler.sv rtl/output_row_buffer.sv rtl/gemm_controller.sv \
	rtl/gemm_scratchpad.sv rtl/gemm_engine.sv
GEMM_TIMER = $(abspath rtl/dv/wall_clock.cpp)

.PHONY: test test-int32 test-array test-array-small test-fp32 test-gemm-small test-gemm-128 test-gemm-1000 test-gemm-tall test-command test-riscv-custom
test: test-int32 test-array-small test-fp32 test-gemm-small test-command test-riscv-custom

test-int32:
	$(VERILATOR) --binary --timing --Wall --top-module tb_mac --Mdir build/int32 -o tb_mac rtl/mac.sv rtl/dv/tb_mac.sv
	./build/int32/tb_mac

test-array:
	$(VERILATOR) --binary --timing --Wall --top-module tb_systolic_array --Mdir build/array128 -o tb_systolic_array rtl/mac.sv rtl/systolic_array.sv rtl/dv/tb_systolic_array.sv
	./build/array128/tb_systolic_array

test-array-small:
	$(VERILATOR) --binary --timing --Wall -GN=3 -GK=4 -GCASES=101 --top-module tb_systolic_array --Mdir build/array-small -o tb_systolic_array rtl/mac.sv rtl/systolic_array.sv rtl/dv/tb_systolic_array.sv
	./build/array-small/tb_systolic_array

test-fp32:
	$(VERILATOR) --binary --timing --Wall --top-module tb_mac_fp32 --Mdir build/fp32 -o tb_mac_fp32 rtl/fp32/fp32_pkg.sv rtl/fp32/mac_fp32.sv rtl/fp32/dv/tb_mac_fp32.sv $(abspath rtl/fp32/dv/fp32_golden.cpp)
	./build/fp32/tb_mac_fp32

test-gemm-small:
	$(VERILATOR) --binary --timing --Wall -j 4 --top-module tb_gemm_engine --Mdir build/gemm-small -o tb_gemm_engine $(GEMM_RTL) rtl/dv/tb_gemm_engine.sv $(GEMM_TIMER)
	./build/gemm-small/tb_gemm_engine

test-gemm-128:
	$(VERILATOR) --binary --timing --Wall -j 4 -GN=128 -GMAX_M=129 -GMAX_P=130 -GMAX_K=129 --top-module tb_gemm_engine --Mdir build/gemm-128 -o tb_gemm_engine $(GEMM_RTL) rtl/dv/tb_gemm_engine.sv $(GEMM_TIMER)
	./build/gemm-128/tb_gemm_engine

test-gemm-1000:
	$(VERILATOR) --binary --timing --Wall -j 4 -GN=128 -GMAX_M=1000 -GMAX_P=1000 -GMAX_K=1000 -GRUN_LARGE=1 --top-module tb_gemm_engine --Mdir build/gemm-1000 -o tb_gemm_engine $(GEMM_RTL) rtl/dv/tb_gemm_engine.sv $(GEMM_TIMER)
	./build/gemm-1000/tb_gemm_engine

test-gemm-tall:
	$(VERILATOR) --binary --timing --Wall -j 4 -GN=128 -GMAX_M=53568 -GMAX_P=64 -GMAX_K=576 -GRUN_TALL=1 --top-module tb_gemm_engine --Mdir build/gemm-tall -o tb_gemm_engine $(GEMM_RTL) rtl/dv/tb_gemm_engine.sv $(GEMM_TIMER)
	./build/gemm-tall/tb_gemm_engine

test-command:
	$(VERILATOR) --binary --timing --Wall -j 4 --top-module tb_laymo_accelerator --Mdir build/command -o tb_laymo_accelerator rtl/laymo_command_pkg.sv $(GEMM_RTL) rtl/laymo_accelerator.sv rtl/dv/tb_laymo_accelerator.sv
	./build/command/tb_laymo_accelerator

test-riscv-custom:
	$(VERILATOR) --binary --timing --Wall -j 4 --top-module tb_laymo_riscv_custom --Mdir build/riscv-custom -o tb_laymo_riscv_custom rtl/laymo_command_pkg.sv $(GEMM_RTL) rtl/laymo_accelerator.sv rtl/laymo_riscv_custom.sv rtl/dv/tb_laymo_riscv_custom.sv
	./build/riscv-custom/tb_laymo_riscv_custom
