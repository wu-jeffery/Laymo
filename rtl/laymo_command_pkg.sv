`timescale 1ns/1ps
package laymo_command_pkg;
    typedef enum logic [2:0] {
        LAYMO_LOAD_A  = 3'd1,
        LAYMO_LOAD_B  = 3'd2,
        LAYMO_GEMM    = 3'd3,
        LAYMO_STORE_C = 3'd4
    } laymo_opcode_t;
endpackage
