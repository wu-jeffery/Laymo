VERILATOR ?= verilator

.PHONY: test test-int32 test-array test-array-small test-fp32
test: test-int32 test-array-small test-fp32

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
