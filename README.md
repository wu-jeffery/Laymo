Laymo is a project to build a custom hardware accelerator for LiDAR-based 3D object detection. It aims to process LiDAR point clouds efficiently and produce 3D bounding boxes around objects.

## Tests

The integer MAC and systolic-array testbenches are in [`rtl/dv`](rtl/dv). The general [`tb_gemm_engine`](rtl/dv/tb_gemm_engine.sv) bench contains eight quick cases at `N=4` and three cases at `N=128`. Run `make test` for the quick suite, `make test-array` for the standalone 128×128 array, `make test-gemm-128` for a tiled 129×129 by 129×130 GEMM, or `make test-gemm-1000` for the 129×130, 257×513, and 1000×1000 cases on the 128×128 array. The 1000×1000 case checks every million-element result against a closed-form reference. Each GEMM case reports preload and execution cycles, host runtime, and effective MAC utilization.

## Tiled integer GEMM

[`gemm_engine`](rtl/gemm_engine.sv) computes `C[M,P] = A[M,K] * B[K,P]` with signed 32-bit operands and signed 64-bit wrapping accumulators. `N` is the physical array width; `MAX_M`, `MAX_P`, and `MAX_K` set the scratchpad capacities. The requested dimensions must fit those capacities. This path is separate from the experimental FP32 MAC.

The engine uses output-stationary tiles:

1. Scalar or N-lane vector host ports preload A and B into the [`gemm_scratchpad`](rtl/gemm_scratchpad.sv) while `busy` is low. A is banked by row modulo `N`; B and C are banked by column modulo `N`. Each bank serves one lane, allowing one paired A/B vector read per clock and one C row write per clock. Scratchpad reads have one clock of latency.
2. The [`gemm_controller`](rtl/gemm_controller.sv) chooses each output tile, clears the array, requests K paired vectors from the scratchpad, waits for computation, and drains the valid result rows. The last row and column tiles are masked to their actual sizes.
3. The [`array_scheduler`](rtl/array_scheduler.sv) accepts paired vectors in K order. Its fixed [`skew_buffer`](rtl/skew_buffer.sv) delays A row `r` by `r` clocks and B column `c` by `c` clocks, including invalid bubbles. It reports completion after `tile_rows + tile_cols - 2` clocks from the last accepted pair, when the farthest active PE has consumed it.
4. Completed rows shift upward through the array's existing accumulator registers. A one-row [`output_row_buffer`](rtl/output_row_buffer.sv) captures each accepted row and holds it through C scratchpad stalls. The controller starts another tile only after all writes finish. `done` pulses once after the final write; host C reads can then inspect the result.

The scratchpad read and write stall inputs exercise backpressure. Host writes are ignored while the engine is busy. The command interface below provides scalar external-memory transfers; tile execution does not overlap with those transfers. The banked RTL defines the logical ports but has not been mapped to a particular SRAM macro.

`make test-gemm-tall` runs `A[53568][576] * B[576][64]` through the same general bench on the 128×128 array. This tall case uses vector preload and no injected stalls, then checks every C value against the closed-form reference. It is a separate target because its scratchpad is much larger than the quick cases.

With tile-aware completion, this tall case takes 376,973 GEMM cycles, down from 403,853 with the fixed 254-cycle completion delay. Preload cycles are reported separately.

Each `PERF` line in the GEMM testbench reports `preload_cycles` for host A/B writes and `gemm_cycles` from command start through the final C write. `gemm_ms` is host wall time for that execution interval; `case_ms` also includes preload, reference calculation, and result checking. These wall times exclude Verilator compilation and vary by machine. `mac_per_cycle = M*P*K/gemm_cycles`, and `utilization_pct` divides that rate by the physical `N*N` MACs.

## Software command interface

[`laymo_accelerator`](rtl/laymo_accelerator.sv) accepts one command at a time through `cmd_valid/cmd_ready`. A command captures dimensions, matrix bases, and an external byte address at acceptance. `cmd_done` pulses when all transfers or GEMM writes finish; `cmd_error` pulses with `cmd_done` for an invalid opcode, out-of-range scratchpad coordinates, or a misaligned external address/stride. The opcodes in [`laymo_command_pkg`](rtl/laymo_command_pkg.sv) are `LOAD_A=1`, `LOAD_B=2`, `GEMM=3`, and `STORE_C=4`.

| Command | Scratchpad coordinates used | External transfer |
| --- | --- | --- |
| `LOAD_A` | `A[a_row + r][a_k + q]`, `0<=r<m`, `0<=q<k` | Read from `ext_addr + r*stride + 8*q` |
| `LOAD_B` | `B[b_k + q][b_col + c]`, `0<=q<k`, `0<=c<p` | Read from `ext_addr + q*stride + 8*c` |
| `GEMM` | Read the above A/B submatrices; write `C[c_row + r][c_col + c]` | None |
| `STORE_C` | `C[c_row + r][c_col + c]`, `0<=r<m`, `0<=c<p` | Write to `ext_addr + r*stride + 8*c` |

All scratchpad coordinates are elements in the separate A, B, and C regions. `MAX_M`, `MAX_P`, and `MAX_K` bound them; GEMM bases can be unaligned to the array tile size. External addresses and strides are in bytes and must be multiples of eight. A zero stride packs rows with eight bytes per element. Each load reads one 64-bit external word and uses its low signed 32 bits; each store writes one signed 64-bit result. The external memory port allows one outstanding read request and accepts writes with `mem_req_ready`; a read response arrives later with `mem_rsp_valid`. This first software path moves one element per request. The existing direct vector preload ports remain available for high-bandwidth testbench loading.

[`laymo_riscv_custom`](rtl/laymo_riscv_custom.sv) adapts this command port to RV32 `custom-0` instructions (`opcode=0x0b`, `funct3=0`, `rd=x0`). The CPU supplies `inst_word` and register values at `rs1_value/rs2_value`, uses `inst_ready` to issue, and waits for `inst_done`; `inst_error` reports a failed instruction. The adapter exposes `rs1_index` and `rs2_index` for register-file lookup. The processor must route this opcode and stall until completion; Laymo does not yet include a CPU or external-memory controller. [`sw/laymo_rv32.h`](sw/laymo_rv32.h) provides inline functions for a core with that integration.

| `funct7` | Instruction | `rs1_value` | `rs2_value` |
| ---: | --- | --- | --- |
| 0 | Set `m,p` | `m` | `p` |
| 1 | Set `k` | `k` | ignored |
| 2 | Set A base | row | K coordinate |
| 3 | Set B base | K coordinate | column |
| 4 | Set C base | row | column |
| 5 | Set external byte address | low 32 bits | high 32 bits |
| 6 | Set external row stride | bytes, or zero for packed | ignored |
| 16, 17, 18, 19 | Load A, load B, GEMM, store C | ignored | ignored |

Set dimensions and bases, then load A and B from their external addresses, issue GEMM, and store C to a chosen external address. Setup instructions complete on acceptance; load, GEMM, and store instructions complete when the operation has finished. Run `make test-command` and `make test-riscv-custom` for end-to-end examples.
