#ifndef LAYMO_RV32_H
#define LAYMO_RV32_H

#include <stdint.h>

#if !defined(__riscv) || __riscv_xlen != 32
#error "Laymo custom instructions require an RV32 core with laymo_riscv_custom"
#endif

// The core must hold each issued instruction until the Laymo inst_done pulse.
// All instructions use custom-0 (0x0b), funct3=0, rd=x0.
#define LAYMO_SETUP(funct7, a, b) \
    __asm__ volatile (".insn r 0x0b, 0, " #funct7 ", x0, %0, %1" \
                      : : "r"((uint32_t)(a)), "r"((uint32_t)(b)) : "memory")
#define LAYMO_ISSUE(funct7) \
    __asm__ volatile (".insn r 0x0b, 0, " #funct7 ", x0, x0, x0" \
                      : : : "memory")

static inline void laymo_set_mp(uint32_t m, uint32_t p) {
    LAYMO_SETUP(0, m, p);
}
static inline void laymo_set_k(uint32_t k) {
    LAYMO_SETUP(1, k, 0);
}
static inline void laymo_set_a(uint32_t row, uint32_t k) {
    LAYMO_SETUP(2, row, k);
}
static inline void laymo_set_b(uint32_t k, uint32_t col) {
    LAYMO_SETUP(3, k, col);
}
static inline void laymo_set_c(uint32_t row, uint32_t col) {
    LAYMO_SETUP(4, row, col);
}
static inline void laymo_set_ext(uint64_t byte_address) {
    LAYMO_SETUP(5, (uint32_t)byte_address, (uint32_t)(byte_address >> 32));
}
static inline void laymo_set_stride(uint32_t bytes) {
    LAYMO_SETUP(6, bytes, 0);
}
static inline void laymo_load_a(void)  { LAYMO_ISSUE(16); }
static inline void laymo_load_b(void)  { LAYMO_ISSUE(17); }
static inline void laymo_gemm(void)    { LAYMO_ISSUE(18); }
static inline void laymo_store_c(void) { LAYMO_ISSUE(19); }

#undef LAYMO_SETUP
#undef LAYMO_ISSUE
#endif
