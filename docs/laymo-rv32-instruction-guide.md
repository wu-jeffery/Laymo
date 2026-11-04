# Laymo RV32 instruction guide

**Audience:** firmware and driver engineers integrating Laymo with an RV32 core.
The RTL defines the instruction interface; a CPU and external-memory controller
still need to be connected. Executing these instructions on an unmodified CPU
will not operate Laymo.

## Encoding and completion

All instructions use R-type `custom-0`: `opcode=0x0b`, `funct3=0`, `rd=x0`.
`funct7` selects the operation. The CPU supplies the values of the encoded
`rs1` and `rs2` registers to Laymo. An instruction is accepted when
`inst_valid && inst_ready`; the CPU must wait for `inst_done` and handle
`inst_error`. Setup instructions finish immediately after acceptance. Load,
GEMM, and store finish only when their full operation completes.

| `funct7` | C helper | `rs1` value | `rs2` value | Effect |
| ---: | --- | --- | --- | --- |
| 0 | `laymo_set_mp(m,p)` | `M` | `P` | Set output dimensions `M×P`. |
| 1 | `laymo_set_k(k)` | `K` | ignored | Set reduction dimension. |
| 2 | `laymo_set_a(row,k)` | A row | A K coordinate | Set A **scratchpad** base. |
| 3 | `laymo_set_b(k,col)` | B K coordinate | B column | Set B scratchpad base. |
| 4 | `laymo_set_c(row,col)` | C row | C column | Set C scratchpad base. |
| 5 | `laymo_set_ext(addr)` | address bits 31:0 | address bits 63:32 | Set **external-memory** byte address. |
| 6 | `laymo_set_stride(bytes)` | row stride in bytes | ignored | Set external row spacing; zero means packed. |
| 16 | `laymo_load_a()` | ignored | ignored | Copy `M×K` elements from external memory into A scratchpad. |
| 17 | `laymo_load_b()` | ignored | ignored | Copy `K×P` elements into B scratchpad. |
| 18 | `laymo_gemm()` | ignored | ignored | Compute `C[M,P] = A[M,K] × B[K,P]` at the saved scratchpad bases. |
| 19 | `laymo_store_c()` | ignored | ignored | Copy `M×P` results from C scratchpad to external memory. |

The `SET_*` values persist until changed or reset. Each operation captures the
settings it needs when issued. `GEMM` does not use the external address or
stride. A load does not check whether other operands are present; software
must load them before GEMM unless it is reusing data already in scratchpad.

## Typical program sequence

Include [`sw/laymo_rv32.h`](../sw/laymo_rv32.h) in firmware for a core wired to
the Laymo instruction adapter:

```c
laymo_set_mp(m, p);
laymo_set_k(k);
laymo_set_a(0, 0);             // Scratchpad coordinates
laymo_set_b(0, 0);
laymo_set_c(0, 0);

laymo_set_ext(a_byte_addr);
laymo_set_stride(a_row_bytes);
laymo_load_a();                // Waits for all M*K elements

laymo_set_ext(b_byte_addr);
laymo_set_stride(b_row_bytes);
laymo_load_b();                // Waits for all K*P elements

laymo_gemm();                  // Waits for all output tiles and C writes

laymo_set_ext(c_byte_addr);
laymo_set_stride(c_row_bytes);
laymo_store_c();               // Waits for all M*P result writes
```

A and B may be loaded in either order. To reuse B, keep its scratchpad region
and `SET_B` base, then load a new A and issue another GEMM. Set a new C base
and external destination before storing if needed.

## Addresses, data, and limits

- `SET_A`, `SET_B`, and `SET_C` name **element coordinates in separate A, B,
  and C scratchpad regions**. They are not external pointers. The configured
  `MAX_M`, `MAX_P`, and `MAX_K` hardware parameters bound these coordinates;
  software must know the values used for its target build.
- `SET_EXT` names a byte address on Laymo's external-memory port. That address
  and a nonzero row stride must be multiples of 8. A zero stride means packed
  rows: `8*K` bytes for A and `8*P` bytes for B or C. For ordinary matrices,
  use a stride at least as large as the packed row size.
- Every A or B input occupies an 8-byte external slot. Laymo uses the low
  signed 32 bits and ignores the upper 32 bits. Each C result is a signed
  64-bit value written to an 8-byte slot. The current transfer engine issues
  one memory request per element; one `LOAD` instruction still covers the
  whole specified matrix.
- Invalid encodings, out-of-range scratchpad regions, and misaligned external
  addresses or strides report `inst_error`. The C helpers return `void`, so
  the CPU integration must turn that signal into a visible fault or status.

`MAX_M`, `MAX_P`, and `MAX_K` determine the physical scratchpad storage at RTL
build time. Software may use any dimensions within that built capacity, but
cannot enlarge it by setting larger `M`, `P`, or `K`: an over-capacity command
returns `inst_error`. Array tiling handles matrices wider than the physical
`N×N` PE array when they still fit in the scratchpad. To run matrices larger
than a fixed scratchpad, Laymo needs external-memory tile streaming and
partial-result accumulation across K blocks.

## Run the C++ instruction-port test

From the repository root, run:

```sh
make test-riscv-cpp
```

This builds the RTL with Verilator and runs
[`tb_laymo_riscv_custom.cpp`](../rtl/dv/tb_laymo_riscv_custom.cpp) as a small
CPU and external-memory model. The C++ driver constructs actual RV32
`custom-0` instruction words, sends `SET_*`, `LOAD_A`, `LOAD_B`, `GEMM`, and
`STORE_C`, checks 15 results, and checks that exceeding the built `MAX_M`,
`MAX_P`, or `MAX_K` reports an error. Its build uses `N=4`, `MAX_M=10`,
`MAX_P=10`, and `MAX_K=8`
so it runs quickly. It exercises the hardware interface in simulation; it
does not execute instructions on a physical RV32 CPU or FPGA.

The implementation is in [`rtl/laymo_riscv_custom.sv`](../rtl/laymo_riscv_custom.sv)
and [`rtl/laymo_accelerator.sv`](../rtl/laymo_accelerator.sv). The tested
instruction sequence is in
[`rtl/dv/tb_laymo_riscv_custom.sv`](../rtl/dv/tb_laymo_riscv_custom.sv).
