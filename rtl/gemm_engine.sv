`timescale 1ns/1ps

// Tiled, output-stationary integer GEMM: C[M,P] = A[M,K] * B[K,P].
// Host ports preload A/B while idle and read C after done.
module gemm_engine #(
    parameter int N = 128,
    parameter int MAX_M = 256,
    parameter int MAX_P = 256,
    parameter int MAX_K = 256
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [31:0]        m,
    input  logic [31:0]        p,
    input  logic [31:0]        k,
    input  logic [31:0]        a_row_base,
    input  logic [31:0]        a_k_base,
    input  logic [31:0]        b_k_base,
    input  logic [31:0]        b_col_base,
    input  logic [31:0]        c_row_base,
    input  logic [31:0]        c_col_base,
    output logic               busy,
    output logic               done,
    input  logic               read_stall,
    input  logic               write_stall,
    input  logic               host_a_we,
    input  logic [31:0]        host_a_row,
    input  logic [31:0]        host_a_k,
    input  logic signed [31:0] host_a_data,
    input  logic               host_a_vec_we,
    input  logic [31:0]        host_a_vec_m0,
    input  logic [31:0]        host_a_vec_k,
    input  logic [31:0]        host_a_vec_rows,
    input  logic signed [31:0] host_a_vec_data [N],
    input  logic               host_b_we,
    input  logic [31:0]        host_b_k,
    input  logic [31:0]        host_b_col,
    input  logic signed [31:0] host_b_data,
    input  logic               host_b_vec_we,
    input  logic [31:0]        host_b_vec_p0,
    input  logic [31:0]        host_b_vec_k,
    input  logic [31:0]        host_b_vec_cols,
    input  logic signed [31:0] host_b_vec_data [N],
    input  logic [31:0]        host_c_row,
    input  logic [31:0]        host_c_col,
    output logic signed [63:0] host_c_data
);
    logic array_clear, array_drain, tile_start;
    logic [31:0] tile_m0, tile_p0, tile_rows, tile_cols, k_len;
    logic read_req, read_rsp_valid;
    logic [31:0] read_k;
    logic signed [31:0] a_vector [N], b_vector [N];
    logic vector_ready, feed_done, compute_done;
    logic signed [31:0] a_in [N], b_in [N];
    logic a_valid [N], b_valid [N];
    logic signed [63:0] array_row [N];
    logic buffer_in_valid, buffer_in_ready, buffer_out_valid, buffer_out_ready;
    logic [31:0] buffer_in_row;
    logic signed [63:0] buffer_out_data [N];
    logic [31:0] buffer_out_m0, buffer_out_p0, buffer_out_row, buffer_out_cols;
    logic [31:0] a_row_base_reg, a_k_base_reg;
    logic [31:0] b_k_base_reg, b_col_base_reg;
    logic [31:0] c_row_base_reg, c_col_base_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_row_base_reg <= '0;
            a_k_base_reg <= '0;
            b_k_base_reg <= '0;
            b_col_base_reg <= '0;
            c_row_base_reg <= '0;
            c_col_base_reg <= '0;
        end else if (start && !busy) begin
            a_row_base_reg <= a_row_base;
            a_k_base_reg <= a_k_base;
            b_k_base_reg <= b_k_base;
            b_col_base_reg <= b_col_base;
            c_row_base_reg <= c_row_base;
            c_col_base_reg <= c_col_base;
        end
    end

    gemm_controller #(.N(N)) controller (
        .clk, .rst_n, .start, .m, .p, .k,
        .read_stall, .vector_ready, .feed_done, .compute_done,
        .buffer_in_ready, .buffer_out_valid,
        .busy, .done, .array_clear, .array_drain, .tile_start,
        .tile_m0, .tile_p0, .tile_rows, .tile_cols, .k_len,
        .read_req, .read_k, .buffer_in_valid, .buffer_in_row
    );

    gemm_scratchpad #(.N(N), .MAX_M(MAX_M), .MAX_P(MAX_P), .MAX_K(MAX_K))
    scratchpad (
        .clk, .rst_n,
        .host_a_we(host_a_we && !busy), .host_a_row, .host_a_k, .host_a_data,
        .host_a_vec_we(host_a_vec_we && !busy), .host_a_vec_m0,
        .host_a_vec_k, .host_a_vec_rows, .host_a_vec_data,
        .host_b_we(host_b_we && !busy), .host_b_k, .host_b_col, .host_b_data,
        .host_b_vec_we(host_b_vec_we && !busy), .host_b_vec_p0,
        .host_b_vec_k, .host_b_vec_cols, .host_b_vec_data,
        .host_c_row, .host_c_col, .host_c_data,
        .read_req, .read_m0(tile_m0), .read_p0(tile_p0), .read_k,
        .read_rows(tile_rows), .read_cols(tile_cols),
        .read_a_row_base(a_row_base_reg), .read_a_k_base(a_k_base_reg),
        .read_b_k_base(b_k_base_reg), .read_b_col_base(b_col_base_reg),
        .read_rsp_valid, .a_vector, .b_vector,
        .write_valid(buffer_out_valid), .write_ready(buffer_out_ready),
        .write_stall, .write_m0(buffer_out_m0), .write_p0(buffer_out_p0),
        .write_row(buffer_out_row), .write_cols(buffer_out_cols),
        .write_c_row_base(c_row_base_reg), .write_c_col_base(c_col_base_reg),
        .write_data(buffer_out_data)
    );

    array_scheduler #(.N(N)) scheduler (
        .clk, .rst_n, .tile_start, .tile_rows, .tile_cols, .k_len,
        .vector_valid(read_rsp_valid), .vector_ready,
        .a_vector, .b_vector, .feed_done, .compute_done,
        .a_in, .a_valid, .b_in, .b_valid
    );

    systolic_array #(.N(N)) array (
        .clk, .rst_n, .clear(array_clear), .drain(array_drain),
        .a_in, .a_valid, .b_in, .b_valid,
        .read_row_data(array_row)
    );

    output_row_buffer #(.N(N)) output_buffer (
        .clk, .rst_n,
        .in_valid(buffer_in_valid), .in_ready(buffer_in_ready),
        .in_data(array_row), .in_m0(tile_m0), .in_p0(tile_p0),
        .in_row(buffer_in_row), .in_cols(tile_cols),
        .out_valid(buffer_out_valid), .out_ready(buffer_out_ready),
        .out_data(buffer_out_data), .out_m0(buffer_out_m0),
        .out_p0(buffer_out_p0), .out_row(buffer_out_row),
        .out_cols(buffer_out_cols)
    );
endmodule
