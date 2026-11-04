`timescale 1ns/1ps

// Three logical N-bank memories. Each A row and B/C column has its own bank,
// so a vector read (or C row write) uses one port in each bank per cycle.
module gemm_scratchpad #(
    parameter int N = 128,
    parameter int MAX_M = 256,
    parameter int MAX_P = 256,
    parameter int MAX_K = 256
) (
    input  logic               clk,
    input  logic               rst_n,
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
    output logic signed [63:0] host_c_data,
    input  logic               read_req,
    input  logic [31:0]        read_m0,
    input  logic [31:0]        read_p0,
    input  logic [31:0]        read_k,
    input  logic [31:0]        read_rows,
    input  logic [31:0]        read_cols,
    input  logic [31:0]        read_a_row_base,
    input  logic [31:0]        read_a_k_base,
    input  logic [31:0]        read_b_k_base,
    input  logic [31:0]        read_b_col_base,
    output logic               read_rsp_valid,
    output logic signed [31:0] a_vector [N],
    output logic signed [31:0] b_vector [N],
    input  logic               write_valid,
    output logic               write_ready,
    input  logic               write_stall,
    input  logic [31:0]        write_m0,
    input  logic [31:0]        write_p0,
    input  logic [31:0]        write_row,
    input  logic [31:0]        write_cols,
    input  logic [31:0]        write_c_row_base,
    input  logic [31:0]        write_c_col_base,
    input  logic signed [63:0] write_data [N]
);
    localparam int M_BLOCKS = (MAX_M + N - 1) / N;
    localparam int P_BLOCKS = (MAX_P + N - 1) / N;
    localparam int A_DEPTH = M_BLOCKS * MAX_K;
    localparam int B_DEPTH = MAX_K * P_BLOCKS;
    localparam int C_DEPTH = MAX_M * P_BLOCKS;

    logic signed [31:0] a_bank [N][A_DEPTH];
    logic signed [31:0] b_bank [N][B_DEPTH];
    logic signed [63:0] c_bank [N][C_DEPTH];

    assign write_ready = !write_stall;
    assign host_c_data = c_bank[host_c_col % N]
                               [host_c_row * P_BLOCKS + host_c_col / N];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_rsp_valid <= 1'b0;
            for (int lane = 0; lane < N; lane++) begin
                a_vector[lane] <= '0;
                b_vector[lane] <= '0;
            end
        end else begin
            read_rsp_valid <= read_req;
            if (read_req) begin
                for (int lane = 0; lane < N; lane++) begin
                    if (lane < read_rows)
                        a_vector[lane] <= a_bank[(read_a_row_base + read_m0 +
                                                  32'(lane)) % N]
                            [((read_a_row_base + read_m0 + 32'(lane)) / N) *
                             MAX_K + read_a_k_base + read_k];
                    else
                        a_vector[lane] <= '0;
                    if (lane < read_cols)
                        b_vector[lane] <= b_bank[(read_b_col_base + read_p0 +
                                                  32'(lane)) % N]
                            [(read_b_k_base + read_k) * P_BLOCKS +
                             (read_b_col_base + read_p0 + 32'(lane)) / N];
                    else
                        b_vector[lane] <= '0;
                end
            end
        end

        if (host_a_we)
            a_bank[host_a_row % N]
                  [(host_a_row / N) * MAX_K + host_a_k] <= host_a_data;
        if (host_a_vec_we) begin
            for (int lane = 0; lane < N; lane++) begin
                if (lane < host_a_vec_rows)
                    a_bank[lane][(host_a_vec_m0 / N) * MAX_K + host_a_vec_k]
                        <= host_a_vec_data[lane];
            end
        end
        if (host_b_we)
            b_bank[host_b_col % N]
                  [host_b_k * P_BLOCKS + host_b_col / N] <= host_b_data;
        if (host_b_vec_we) begin
            for (int lane = 0; lane < N; lane++) begin
                if (lane < host_b_vec_cols)
                    b_bank[lane][host_b_vec_k * P_BLOCKS + host_b_vec_p0 / N]
                        <= host_b_vec_data[lane];
            end
        end
        if (write_valid && write_ready) begin
            for (int lane = 0; lane < N; lane++) begin
                if (lane < write_cols)
                    c_bank[(write_c_col_base + write_p0 + 32'(lane)) % N]
                          [(write_c_row_base + write_m0 + write_row) *
                           P_BLOCKS + (write_c_col_base + write_p0 +
                                       32'(lane)) / N]
                        <= write_data[lane];
            end
        end
    end
endmodule
