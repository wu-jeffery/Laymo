`timescale 1ns/1ps

// Output-stationary N x N matrix-multiply array.
// A enters from the left, B from the top, and each PE forwards both by one
// cell per clock. The caller skews A row r by r cycles and B column c by c
// cycles so matching A[r][k] and B[k][c] meet at PE(r,c).
module systolic_array #(
    parameter int N = 128
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clear,
    input  logic signed [31:0] a_in [N],
    input  logic               a_valid [N],
    input  logic signed [31:0] b_in [N],
    input  logic               b_valid [N],
    output logic signed [63:0] c_out [N][N]
);
    logic signed [31:0] a_pipe [N][N+1];
    logic signed [31:0] b_pipe [N+1][N];
    logic a_valid_pipe [N][N+1];
    logic b_valid_pipe [N+1][N];

    for (genvar r = 0; r < N; r++) begin : rows
        assign a_pipe[r][0] = a_in[r];
        assign a_valid_pipe[r][0] = a_valid[r];
    end
    for (genvar c = 0; c < N; c++) begin : columns
        assign b_pipe[0][c] = b_in[c];
        assign b_valid_pipe[0][c] = b_valid[c];
    end

    for (genvar r = 0; r < N; r++) begin : pe_rows
        for (genvar c = 0; c < N; c++) begin : pe_columns
            always_ff @(posedge clk) begin
                if (!rst_n || clear) begin
                    a_pipe[r][c+1] <= '0;
                    b_pipe[r+1][c] <= '0;
                    a_valid_pipe[r][c+1] <= 1'b0;
                    b_valid_pipe[r+1][c] <= 1'b0;
                end else begin
                    a_pipe[r][c+1] <= a_pipe[r][c];
                    b_pipe[r+1][c] <= b_pipe[r][c];
                    a_valid_pipe[r][c+1] <= a_valid_pipe[r][c];
                    b_valid_pipe[r+1][c] <= b_valid_pipe[r][c];
                end
            end

            mac u_mac (
                .clk,
                .rst_n,
                .clear,
                .enable(a_valid_pipe[r][c] && b_valid_pipe[r][c]),
                .a(a_pipe[r][c]),
                .b(b_pipe[r][c]),
                .acc(c_out[r][c])
            );
        end
    end
endmodule
