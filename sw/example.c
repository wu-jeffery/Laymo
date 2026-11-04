#include "laymo_rv32.h"

// External matrices use 8 bytes per element. A/B values are in the low 32
// bits of each word; C receives full signed 64-bit words.
void laymo_run_gemm(uint64_t a_byte_addr, uint64_t b_byte_addr,
                    uint64_t c_byte_addr, uint32_t m, uint32_t p,
                    uint32_t k, uint32_t a_stride_bytes,
                    uint32_t b_stride_bytes, uint32_t c_stride_bytes) {
    laymo_set_mp(m, p);
    laymo_set_k(k);
    laymo_set_a(0, 0);
    laymo_set_b(0, 0);
    laymo_set_c(0, 0);

    laymo_set_ext(a_byte_addr);
    laymo_set_stride(a_stride_bytes);
    laymo_load_a();

    laymo_set_ext(b_byte_addr);
    laymo_set_stride(b_stride_bytes);
    laymo_load_b();

    laymo_gemm();

    laymo_set_ext(c_byte_addr);
    laymo_set_stride(c_stride_bytes);
    laymo_store_c();
}
