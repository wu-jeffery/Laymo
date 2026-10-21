`timescale 1ns/1ps

module tb_systolic_array #(
    parameter int N = 128,
    parameter int K = 128,
    parameter int CASES = 3
);

    logic clk;
    logic rst_n = 1'b0;
    logic clear = 1'b0;
    logic signed [31:0] a_in [N];
    logic a_valid [N];
    logic signed [31:0] b_in [N];
    logic b_valid [N];
    logic signed [63:0] c_out [N][N];

    logic signed [31:0] matrix_a [N][K];
    logic signed [31:0] matrix_b [K][N];
    logic signed [63:0] expected [N][N];
    int checks = 0;

    systolic_array #(.N(N)) dut (.*);
    always #5 clk = ~clk;

    task automatic check_matrix(input int case_number);
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                if (c_out[r][c] !== expected[r][c])
                    $fatal(1, "case %0d C[%0d][%0d]: expected %016x, got %016x",
                           case_number, r, c, expected[r][c], c_out[r][c]);
                checks++;
            end
        end
    endtask

    task automatic run_case(input int case_number);
        // Clear both accumulators and the operand pipelines between matrices.
        @(negedge clk);
        clear = 1'b1;
        for (int i = 0; i < N; i++) begin
            a_in[i] = '0;
            b_in[i] = '0;
            a_valid[i] = 1'b0;
            b_valid[i] = 1'b0;
        end
        @(posedge clk);
        #1;
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++)
                if (c_out[r][c] !== 64'b0)
                    $fatal(1, "case %0d: clear failed at C[%0d][%0d]", case_number, r, c);

        for (int r = 0; r < N; r++) begin
            for (int k = 0; k < K; k++)
                matrix_a[r][k] = (case_number == 0) ? 32'(r * K + k + 1) : $urandom;
        end
        for (int k = 0; k < K; k++) begin
            for (int c = 0; c < N; c++)
                matrix_b[k][c] = (case_number == 0) ? 32'((k + 1) * (c + 1)) : $urandom;
        end

        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                expected[r][c] = '0;
                for (int k = 0; k < K; k++)
                    expected[r][c] += longint'(matrix_a[r][k]) * longint'(matrix_b[k][c]);
            end
        end

        // Row r starts r cycles late; column c starts c cycles late.
        for (int t = 0; t < K + 2*N - 2; t++) begin
            @(negedge clk);
            clear = 1'b0;
            for (int r = 0; r < N; r++) begin
                a_valid[r] = (t >= r) && (t < r + K);
                a_in[r] = a_valid[r] ? matrix_a[r][t-r] : '0;
            end
            for (int c = 0; c < N; c++) begin
                b_valid[c] = (t >= c) && (t < c + K);
                b_in[c] = b_valid[c] ? matrix_b[t-c][c] : '0;
            end
            @(posedge clk);
            #1;
        end
        check_matrix(case_number);
    endtask

    initial begin
        clk = 1'b0;
        for (int i = 0; i < N; i++) begin
            a_in[i] = '0;
            b_in[i] = '0;
            a_valid[i] = 1'b0;
            b_valid[i] = 1'b0;
        end
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1'b1;

        for (int test_number = 0; test_number < CASES; test_number++)
            run_case(test_number);

        $display("PASS: %0d systolic-array result checks across %0d %0d x %0d matrices",
                 checks, CASES, N, N);
        $finish;
    end
endmodule
