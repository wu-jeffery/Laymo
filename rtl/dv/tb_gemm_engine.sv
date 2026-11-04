`timescale 1ns/1ps

module tb_gemm_engine #(
    parameter int N = 4,
    parameter int MAX_M = 131,
    parameter int MAX_P = 130,
    parameter int MAX_K = 9,
    parameter bit RUN_LARGE = 1'b0,
    parameter bit RUN_TALL = 1'b0
);
    import "DPI-C" function longint unsigned wall_clock_ns();
    localparam int REF_M = 131;
    localparam int REF_P = 130;
    localparam int REF_K = 129;
    localparam int P_BLOCKS = (MAX_P + N - 1) / N;

    logic clk;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [31:0] m = '0, p = '0, k = '0;
    logic [31:0] a_row_base = '0, a_k_base = '0;
    logic [31:0] b_k_base = '0, b_col_base = '0;
    logic [31:0] c_row_base = '0, c_col_base = '0;
    logic busy, done;
    logic read_stall, write_stall, stalls_enabled = 1'b0;
    logic [31:0] cycle_count;
    logic host_a_we = 1'b0, host_b_we = 1'b0;
    logic [31:0] host_a_row = '0, host_a_k = '0;
    logic host_a_vec_we = 1'b0;
    logic [31:0] host_a_vec_m0 = '0, host_a_vec_k = '0;
    logic [31:0] host_a_vec_rows = '0;
    logic signed [31:0] host_a_vec_data [N];
    logic [31:0] host_b_k = '0, host_b_col = '0;
    logic host_b_vec_we = 1'b0;
    logic [31:0] host_b_vec_p0 = '0, host_b_vec_k = '0;
    logic [31:0] host_b_vec_cols = '0;
    logic signed [31:0] host_b_vec_data [N];
    logic signed [31:0] host_a_data = '0, host_b_data = '0;
    logic [31:0] host_c_row = '0, host_c_col = '0;
    logic signed [63:0] host_c_data;
    logic signed [31:0] a_gold [REF_M][REF_K];
    logic signed [31:0] b_gold [REF_K][REF_P];
    logic signed [63:0] expected [REF_M][REF_P];
    int checks = 0;

    always #5 clk = ~clk;
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycle_count <= '0;
        else
            cycle_count <= cycle_count + 1;
    end
    assign read_stall = stalls_enabled && ((cycle_count % 7) == 2);
    assign write_stall = stalls_enabled && ((cycle_count % 5) < 2);

    gemm_engine #(.N(N), .MAX_M(MAX_M), .MAX_P(MAX_P), .MAX_K(MAX_K)) dut (.*);

    function automatic logic signed [31:0] make_a(
        input int row, input int kk, input int case_number
    );
        return 32'(((row * 7 + kk * 3 + case_number) % 17) - 8);
    endfunction

    function automatic logic signed [31:0] make_b(
        input int kk, input int col, input int case_number
    );
        return 32'(((kk * 11 + col * 5 + case_number * 2) % 19) - 9);
    endfunction

    // Dense operands with a cheap independent result formula for large cases.
    function automatic int f(input int row);
        return (row % 13) - 6;
    endfunction
    function automatic int h(input int row);
        return (row % 5) - 2;
    endfunction
    function automatic int g(input int kk);
        return (kk % 7) - 3;
    endfunction
    function automatic int u(input int col);
        return (col % 11) - 5;
    endfunction
    function automatic int v(input int col);
        return (col % 3) - 1;
    endfunction

    task automatic run_case(
        input int case_number,
        input int rows,
        input int cols,
        input int inner,
        input bit add_stalls
    );
        int timeout_cycles;
        bit finished;
        logic [31:0] preload_cycle_start, preload_cycle_end;
        logic [31:0] gemm_cycle_start, gemm_cycle_end;
        longint unsigned preload_wall_start, preload_wall_end;
        longint unsigned reference_wall_end, gemm_wall_start, gemm_wall_end;
        longint unsigned check_wall_end;
        real mac_per_cycle, utilization_pct;

        preload_cycle_start = cycle_count;
        preload_wall_start = wall_clock_ns();

        for (int r = 0; r < rows; r++) begin
            for (int kk = 0; kk < inner; kk++) begin
                a_gold[r][kk] = make_a(r, kk, case_number);
                @(negedge clk);
                host_a_we = 1'b1;
                host_a_row = 32'(r);
                host_a_k = 32'(kk);
                host_a_data = a_gold[r][kk];
            end
        end
        @(negedge clk);
        host_a_we = 1'b0;

        for (int kk = 0; kk < inner; kk++) begin
            for (int c = 0; c < cols; c++) begin
                b_gold[kk][c] = make_b(kk, c, case_number);
                @(negedge clk);
                host_b_we = 1'b1;
                host_b_k = 32'(kk);
                host_b_col = 32'(c);
                host_b_data = b_gold[kk][c];
            end
        end
        @(negedge clk);
        host_b_we = 1'b0;
        preload_cycle_end = cycle_count;
        preload_wall_end = wall_clock_ns();

        for (int r = 0; r < rows; r++) begin
            for (int c = 0; c < cols; c++) begin
                expected[r][c] = '0;
                for (int kk = 0; kk < inner; kk++)
                    expected[r][c] += longint'(a_gold[r][kk]) *
                                      longint'(b_gold[kk][c]);
            end
        end
        reference_wall_end = wall_clock_ns();

        @(negedge clk);
        m = 32'(rows);
        p = 32'(cols);
        k = 32'(inner);
        stalls_enabled = add_stalls;
        start = 1'b1;
        gemm_cycle_start = cycle_count;
        gemm_wall_start = wall_clock_ns();
        @(negedge clk);
        start = 1'b0;

        timeout_cycles = ((rows + N - 1) / N) * ((cols + N - 1) / N) *
                         (inner + 4 * N + 100) + 1000;
        finished = 1'b0;
        for (int step = 0; step < timeout_cycles; step++) begin
            @(posedge clk);
            #1;
            if (done) begin
                finished = 1'b1;
                break;
            end
        end
        if (!finished)
            $fatal(1, "case %0d timed out: N=%0d M=%0d P=%0d K=%0d",
                   case_number, N, rows, cols, inner);
        if (busy)
            $fatal(1, "case %0d done asserted while busy", case_number);
        gemm_cycle_end = cycle_count;
        gemm_wall_end = wall_clock_ns();

        for (int r = 0; r < rows; r++) begin
            for (int c = 0; c < cols; c++) begin
                host_c_row = 32'(r);
                host_c_col = 32'(c);
                #1;
                if (host_c_data !== expected[r][c])
                    $fatal(1, "case %0d C[%0d][%0d]: expected %0d, got %0d",
                           case_number, r, c, expected[r][c], host_c_data);
                checks++;
            end
        end
        check_wall_end = wall_clock_ns();
        mac_per_cycle = ($itor(rows) * cols * inner) /
                        $itor(gemm_cycle_end - gemm_cycle_start);
        utilization_pct = 100.0 * mac_per_cycle / (N * N);
        $display("PERF case=%0d load=scalar stalls=%0d N=%0d M=%0d P=%0d K=%0d preload_cycles=%0d gemm_cycles=%0d case_ms=%0.3f preload_ms=%0.3f reference_ms=%0.3f gemm_ms=%0.3f check_ms=%0.3f mac_per_cycle=%0.3f utilization_pct=%0.3f",
                 case_number, add_stalls, N, rows, cols, inner,
                 preload_cycle_end - preload_cycle_start,
                 gemm_cycle_end - gemm_cycle_start,
                 (check_wall_end - preload_wall_start) / 1.0e6,
                 (preload_wall_end - preload_wall_start) / 1.0e6,
                 (reference_wall_end - preload_wall_end) / 1.0e6,
                 (gemm_wall_end - gemm_wall_start) / 1.0e6,
                 (check_wall_end - gemm_wall_end) / 1.0e6,
                 mac_per_cycle, utilization_pct);
        $display("PASS case %0d: N=%0d C[%0d][%0d], K=%0d, stalls=%0d",
                 case_number, N, rows, cols, inner, add_stalls);
        stalls_enabled = 1'b0;
    endtask

    task automatic run_structured_case(
        input int case_number,
        input int rows,
        input int cols,
        input int inner,
        input bit add_stalls
    );
        int row_blocks, col_blocks, blocks, timeout_cycles;
        bit finished;
        logic [31:0] preload_cycle_start, preload_cycle_end;
        logic [31:0] gemm_cycle_start, gemm_cycle_end;
        longint unsigned preload_wall_start, preload_wall_end;
        longint unsigned reference_wall_end, gemm_wall_start, gemm_wall_end;
        longint unsigned check_wall_end;
        longint signed sum_g, sum_g2, expected_value;
        real mac_per_cycle, utilization_pct;

        row_blocks = (rows + N - 1) / N;
        col_blocks = (cols + N - 1) / N;
        blocks = (row_blocks > col_blocks) ? row_blocks : col_blocks;
        preload_cycle_start = cycle_count;
        preload_wall_start = wall_clock_ns();

        // One A row vector and one B column vector can be loaded per clock.
        for (int block = 0; block < blocks; block++) begin
            for (int kk = 0; kk < inner; kk++) begin
                @(negedge clk);
                host_a_vec_we = (block < row_blocks);
                host_b_vec_we = (block < col_blocks);
                host_a_vec_m0 = 32'(block * N);
                host_b_vec_p0 = 32'(block * N);
                host_a_vec_k = 32'(kk);
                host_b_vec_k = 32'(kk);
                host_a_vec_rows = (block < row_blocks) ?
                    32'(((block + 1) * N <= rows) ? N : rows - block * N) : '0;
                host_b_vec_cols = (block < col_blocks) ?
                    32'(((block + 1) * N <= cols) ? N : cols - block * N) : '0;
                for (int lane = 0; lane < N; lane++) begin
                    host_a_vec_data[lane] = ((block * N + lane) < rows) ?
                        32'(f(block * N + lane) * g(kk) + h(block * N + lane)) : '0;
                    host_b_vec_data[lane] = ((block * N + lane) < cols) ?
                        32'(g(kk) * u(block * N + lane) + v(block * N + lane)) : '0;
                end
            end
        end
        @(negedge clk);
        host_a_vec_we = 1'b0;
        host_b_vec_we = 1'b0;
        preload_cycle_end = cycle_count;
        preload_wall_end = wall_clock_ns();

        sum_g = 0;
        sum_g2 = 0;
        for (int kk = 0; kk < inner; kk++) begin
            sum_g += longint'(g(kk));
            sum_g2 += longint'(g(kk)) * longint'(g(kk));
        end
        reference_wall_end = wall_clock_ns();

        @(negedge clk);
        m = 32'(rows);
        p = 32'(cols);
        k = 32'(inner);
        stalls_enabled = add_stalls;
        start = 1'b1;
        gemm_cycle_start = cycle_count;
        gemm_wall_start = wall_clock_ns();
        @(negedge clk);
        start = 1'b0;

        timeout_cycles = row_blocks * col_blocks *
                         (inner + 4 * N + 100) * 2 + 1000;
        finished = 1'b0;
        for (int step = 0; step < timeout_cycles; step++) begin
            @(posedge clk);
            #1;
            if (done) begin
                finished = 1'b1;
                break;
            end
        end
        if (!finished)
            $fatal(1, "case %0d timed out: N=%0d M=%0d P=%0d K=%0d",
                   case_number, N, rows, cols, inner);
        if (busy)
            $fatal(1, "case %0d done asserted while busy", case_number);
        gemm_cycle_end = cycle_count;
        gemm_wall_end = wall_clock_ns();

        // Small cases cover the host read port. Read banks directly here so
        // million-element checking adds no clock cycles to the measurement.
        for (int row = 0; row < rows; row++) begin
            for (int col = 0; col < cols; col++) begin
                expected_value = longint'(f(row)) * longint'(u(col)) * sum_g2
                    + (longint'(f(row)) * longint'(v(col))
                    + longint'(h(row)) * longint'(u(col))) * sum_g
                    + longint'(h(row)) * longint'(v(col)) * inner;
                if (dut.scratchpad.c_bank[col % N]
                        [row * P_BLOCKS + col / N] !== expected_value)
                    $fatal(1, "case %0d C[%0d][%0d]: expected %0d, got %0d",
                           case_number, row, col, expected_value,
                           dut.scratchpad.c_bank[col % N]
                               [row * P_BLOCKS + col / N]);
                checks++;
            end
        end
        host_c_row = 32'(rows - 1);
        host_c_col = 32'(cols - 1);
        #1;
        if (host_c_data !== expected_value)
            $fatal(1, "case %0d host C read: expected %0d, got %0d",
                   case_number, expected_value, host_c_data);
        check_wall_end = wall_clock_ns();

        mac_per_cycle = ($itor(rows) * cols * inner) /
                        $itor(gemm_cycle_end - gemm_cycle_start);
        utilization_pct = 100.0 * mac_per_cycle / (N * N);
        $display("PERF case=%0d load=vector stalls=%0d N=%0d M=%0d P=%0d K=%0d preload_cycles=%0d gemm_cycles=%0d case_ms=%0.3f preload_ms=%0.3f reference_ms=%0.3f gemm_ms=%0.3f check_ms=%0.3f mac_per_cycle=%0.3f utilization_pct=%0.3f",
                 case_number, add_stalls, N, rows, cols, inner,
                 preload_cycle_end - preload_cycle_start,
                 gemm_cycle_end - gemm_cycle_start,
                 (check_wall_end - preload_wall_start) / 1.0e6,
                 (preload_wall_end - preload_wall_start) / 1.0e6,
                 (reference_wall_end - preload_wall_end) / 1.0e6,
                 (gemm_wall_end - gemm_wall_start) / 1.0e6,
                 (check_wall_end - gemm_wall_end) / 1.0e6,
                 mac_per_cycle, utilization_pct);
        $display("PASS case %0d: N=%0d C[%0d][%0d], K=%0d, stalls=%0d",
                 case_number, N, rows, cols, inner, add_stalls);
        stalls_enabled = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        for (int lane = 0; lane < N; lane++) begin
            host_a_vec_data[lane] = '0;
            host_b_vec_data[lane] = '0;
        end
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        if (RUN_TALL) begin
            run_structured_case(0, 53568, 64, 576, 1'b0);
        end else if (N >= 128) begin
            run_case(0, 129, 130, 129, 1'b1);
            if (RUN_LARGE) begin
                run_structured_case(1, 257, 513, 257, 1'b0);
                run_structured_case(2, 1000, 1000, 1000, 1'b1);
            end
        end else begin
            run_case(0, 5, 7, 4, 1'b0);
            run_case(1, 7, 5, 9, 1'b1);
            run_case(2, 131, 130, 9, 1'b1);
            run_case(3, 1, 1, 1, 1'b1);
            run_case(4, 2, 3, 0, 1'b0);
            run_case(5, 128, 128, 9, 1'b0);
            run_case(6, 130, 129, 1, 1'b1);
            run_case(7, 9, 2, 9, 1'b1);
        end
        $display("PASS: %0d tiled GEMM output checks", checks);
        $finish;
    end
endmodule
