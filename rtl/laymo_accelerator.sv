`timescale 1ns/1ps

// Software-facing command port and single-outstanding external-memory mover.
// External addresses are bytes. Each transfer is one 64-bit word: LOAD uses
// its low signed 32 bits, STORE writes the complete signed 64-bit C element.
module laymo_accelerator #(
    parameter int N = 128,
    parameter int MAX_M = 256,
    parameter int MAX_P = 256,
    parameter int MAX_K = 256
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [2:0]  cmd_opcode,
    input  logic [31:0] cmd_m,
    input  logic [31:0] cmd_p,
    input  logic [31:0] cmd_k,
    input  logic [63:0] cmd_ext_addr,
    input  logic [31:0] cmd_ext_stride_bytes,
    input  logic [31:0] cmd_a_row,
    input  logic [31:0] cmd_a_k,
    input  logic [31:0] cmd_b_k,
    input  logic [31:0] cmd_b_col,
    input  logic [31:0] cmd_c_row,
    input  logic [31:0] cmd_c_col,
    output logic        cmd_busy,
    output logic        cmd_done,
    output logic        cmd_error,
    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [63:0] mem_req_addr,
    output logic [63:0] mem_req_wdata,
    input  logic        mem_rsp_valid,
    input  logic [31:0] mem_rsp_rdata
);
    import laymo_command_pkg::*;

    typedef enum logic [2:0] {
        IDLE, READ_REQ, READ_WAIT, WRITE_SP, EXEC_START, EXEC_WAIT, WRITE_MEM
    } state_t;
    state_t state;
    logic [2:0] op_reg;
    logic [31:0] m_reg, p_reg, k_reg;
    logic [31:0] a_row_reg, a_k_reg, b_k_reg, b_col_reg;
    logic [31:0] c_row_reg, c_col_reg;
    logic [63:0] ext_base_reg;
    logic [31:0] ext_stride_reg;
    logic [31:0] row_idx, col_idx;
    logic [31:0] transfer_rows, transfer_cols;
    logic [31:0] a_data_reg;
    logic engine_start, engine_busy, engine_done;
    logic signed [63:0] c_data;
    wire signed [31:0] unused_a_vec [N];
    wire signed [31:0] unused_b_vec [N];

    for (genvar lane = 0; lane < N; lane++) begin : unused_vector_ties
        assign unused_a_vec[lane] = '0;
        assign unused_b_vec[lane] = '0;
    end

    assign cmd_ready = (state == IDLE);
    assign cmd_busy = (state != IDLE) || engine_busy;
    assign engine_start = (state == EXEC_START);
    assign transfer_rows = (op_reg == LAYMO_LOAD_B) ? k_reg : m_reg;
    assign transfer_cols = (op_reg == LAYMO_LOAD_A) ? k_reg : p_reg;

    assign mem_req_valid = (state == READ_REQ) || (state == WRITE_MEM);
    assign mem_req_write = (state == WRITE_MEM);
    assign mem_req_addr = ext_base_reg + 64'(row_idx) * 64'(ext_stride_reg)
                        + 64'(col_idx) * 64'd8;
    assign mem_req_wdata = c_data;

    gemm_engine #(.N(N), .MAX_M(MAX_M), .MAX_P(MAX_P), .MAX_K(MAX_K)) engine (
        .clk, .rst_n, .start(engine_start),
        .m(m_reg), .p(p_reg), .k(k_reg),
        .a_row_base(a_row_reg), .a_k_base(a_k_reg),
        .b_k_base(b_k_reg), .b_col_base(b_col_reg),
        .c_row_base(c_row_reg), .c_col_base(c_col_reg),
        .busy(engine_busy), .done(engine_done),
        .read_stall(1'b0), .write_stall(1'b0),
        .host_a_we((state == WRITE_SP) && (op_reg == LAYMO_LOAD_A)),
        .host_a_row(a_row_reg + row_idx),
        .host_a_k(a_k_reg + col_idx),
        .host_a_data(a_data_reg),
        .host_a_vec_we(1'b0), .host_a_vec_m0('0), .host_a_vec_k('0),
        .host_a_vec_rows('0), .host_a_vec_data(unused_a_vec),
        .host_b_we((state == WRITE_SP) && (op_reg == LAYMO_LOAD_B)),
        .host_b_k(b_k_reg + row_idx),
        .host_b_col(b_col_reg + col_idx),
        .host_b_data(a_data_reg),
        .host_b_vec_we(1'b0), .host_b_vec_p0('0), .host_b_vec_k('0),
        .host_b_vec_cols('0), .host_b_vec_data(unused_b_vec),
        .host_c_row(c_row_reg + row_idx),
        .host_c_col(c_col_reg + col_idx),
        .host_c_data(c_data)
    );

    // A zero stride means tightly packed rows in external memory.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            op_reg <= '0;
            m_reg <= '0;
            p_reg <= '0;
            k_reg <= '0;
            a_row_reg <= '0;
            a_k_reg <= '0;
            b_k_reg <= '0;
            b_col_reg <= '0;
            c_row_reg <= '0;
            c_col_reg <= '0;
            ext_base_reg <= '0;
            ext_stride_reg <= '0;
            row_idx <= '0;
            col_idx <= '0;
            a_data_reg <= '0;
            cmd_done <= 1'b0;
            cmd_error <= 1'b0;
        end else begin
            cmd_done <= 1'b0;
            cmd_error <= 1'b0;
            case (state)
                IDLE: if (cmd_valid) begin
                    if ((cmd_opcode != LAYMO_LOAD_A) &&
                        (cmd_opcode != LAYMO_LOAD_B) &&
                        (cmd_opcode != LAYMO_GEMM) &&
                        (cmd_opcode != LAYMO_STORE_C)) begin
                        cmd_done <= 1'b1;
                        cmd_error <= 1'b1;
                    end else if (((cmd_opcode != LAYMO_GEMM) &&
                                  ((cmd_ext_addr[2:0] != 0) ||
                                   (cmd_ext_stride_bytes[2:0] != 0))) ||
                                 ((cmd_opcode == LAYMO_LOAD_A ||
                                   cmd_opcode == LAYMO_GEMM) &&
                                  (({1'b0, cmd_a_row} + {1'b0, cmd_m} > 33'(MAX_M)) ||
                                   ({1'b0, cmd_a_k} + {1'b0, cmd_k} > 33'(MAX_K)))) ||
                                 ((cmd_opcode == LAYMO_LOAD_B ||
                                   cmd_opcode == LAYMO_GEMM) &&
                                  (({1'b0, cmd_b_k} + {1'b0, cmd_k} > 33'(MAX_K)) ||
                                   ({1'b0, cmd_b_col} + {1'b0, cmd_p} > 33'(MAX_P)))) ||
                                 ((cmd_opcode == LAYMO_STORE_C ||
                                   cmd_opcode == LAYMO_GEMM) &&
                                  (({1'b0, cmd_c_row} + {1'b0, cmd_m} > 33'(MAX_M)) ||
                                   ({1'b0, cmd_c_col} + {1'b0, cmd_p} > 33'(MAX_P))))) begin
                        cmd_done <= 1'b1;
                        cmd_error <= 1'b1;
                    end else begin
                        op_reg <= cmd_opcode;
                        m_reg <= cmd_m;
                        p_reg <= cmd_p;
                        k_reg <= cmd_k;
                        a_row_reg <= cmd_a_row;
                        a_k_reg <= cmd_a_k;
                        b_k_reg <= cmd_b_k;
                        b_col_reg <= cmd_b_col;
                        c_row_reg <= cmd_c_row;
                        c_col_reg <= cmd_c_col;
                        ext_base_reg <= cmd_ext_addr;
                        ext_stride_reg <= (cmd_ext_stride_bytes != 0) ?
                            cmd_ext_stride_bytes :
                            ((cmd_opcode == LAYMO_LOAD_A) ?
                                32'(64'(cmd_k) * 64'd8) : 32'(64'(cmd_p) * 64'd8));
                        row_idx <= '0;
                        col_idx <= '0;
                        if (cmd_opcode == LAYMO_GEMM)
                            state <= EXEC_START;
                        else if ((cmd_opcode == LAYMO_LOAD_B ? cmd_k : cmd_m) == 0 ||
                                 (cmd_opcode == LAYMO_LOAD_A ? cmd_k : cmd_p) == 0)
                            cmd_done <= 1'b1;
                        else if (cmd_opcode == LAYMO_STORE_C)
                            state <= WRITE_MEM;
                        else
                            state <= READ_REQ;
                    end
                end
                READ_REQ: if (mem_req_ready)
                    state <= READ_WAIT;
                READ_WAIT: if (mem_rsp_valid) begin
                    a_data_reg <= mem_rsp_rdata;
                    state <= WRITE_SP;
                end
                WRITE_SP: begin
                    if (col_idx + 1 < transfer_cols)
                        col_idx <= col_idx + 1;
                    else begin
                        col_idx <= '0;
                        row_idx <= row_idx + 1;
                    end
                    if ((row_idx + 1 == transfer_rows) &&
                        (col_idx + 1 == transfer_cols)) begin
                        cmd_done <= 1'b1;
                        state <= IDLE;
                    end else
                        state <= READ_REQ;
                end
                EXEC_START: state <= EXEC_WAIT;
                EXEC_WAIT: if (engine_done) begin
                    cmd_done <= 1'b1;
                    state <= IDLE;
                end
                WRITE_MEM: if (mem_req_ready) begin
                    if (col_idx + 1 < transfer_cols)
                        col_idx <= col_idx + 1;
                    else begin
                        col_idx <= '0;
                        row_idx <= row_idx + 1;
                    end
                    if ((row_idx + 1 == transfer_rows) &&
                        (col_idx + 1 == transfer_cols)) begin
                        cmd_done <= 1'b1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
