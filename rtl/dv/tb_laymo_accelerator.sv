`timescale 1ns/1ps

module tb_laymo_accelerator;
    import laymo_command_pkg::*;
    localparam int N = 4;
    localparam int ROWS = 5;
    localparam int COLS = 3;
    localparam int INNER = 5;
    localparam int A_WORD = 16;
    localparam int B_WORD = 128;
    localparam int C_WORD = 256;
    logic clk;
    logic rst_n = 1'b0;
    logic cmd_valid = 1'b0;
    logic cmd_ready, cmd_busy, cmd_done, cmd_error;
    logic [2:0] cmd_opcode = '0;
    logic [31:0] cmd_m = '0, cmd_p = '0, cmd_k = '0;
    logic [63:0] cmd_ext_addr = '0;
    logic [31:0] cmd_ext_stride_bytes = '0;
    logic [31:0] cmd_a_row = '0, cmd_a_k = '0;
    logic [31:0] cmd_b_k = '0, cmd_b_col = '0;
    logic [31:0] cmd_c_row = '0, cmd_c_col = '0;
    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [63:0] mem_req_addr, mem_req_wdata;
    logic mem_rsp_valid;
    logic [31:0] mem_rsp_rdata;
    logic signed [63:0] memory [512];
    int cycles;

    function automatic logic signed [31:0] make_a(input int r, input int kk);
        return r * 3 - kk - 4;
    endfunction
    function automatic logic signed [31:0] make_b(input int kk, input int c);
        return kk * 2 + c - 3;
    endfunction

    always #5 clk = ~clk;
    assign mem_req_ready = (cycles % 4 != 1);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            mem_rsp_valid <= 1'b0;
            mem_rsp_rdata <= '0;
        end else begin
            cycles <= cycles + 1;
            mem_rsp_valid <= 1'b0;
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_addr[2:0] != 0 || mem_req_addr / 8 >= 512)
                    $fatal(1, "invalid external address %0d", mem_req_addr);
                if (mem_req_write)
                    memory[mem_req_addr[11:3]] <= $signed(mem_req_wdata);
                else begin
                    mem_rsp_rdata <= memory[mem_req_addr[11:3]][31:0];
                    mem_rsp_valid <= 1'b1;
                end
            end
        end
    end

    laymo_accelerator #(.N(N), .MAX_M(10), .MAX_P(10), .MAX_K(8)) dut (.*);

    task automatic issue(input logic [2:0] op, input bit expect_error);
        bit saw_done;
        @(negedge clk);
        if (!cmd_ready || cmd_busy)
            $fatal(1, "command port not ready");
        cmd_opcode = op;
        cmd_valid = 1'b1;
        @(posedge clk);
        #1;
        cmd_valid = 1'b0;
        saw_done = cmd_done;
        for (int t = 0; t < 2000 && !saw_done; t++) begin
            @(posedge clk);
            #1;
            saw_done = cmd_done;
        end
        if (!saw_done)
            $fatal(1, "command %0d timed out", op);
        if (cmd_error !== expect_error)
            $fatal(1, "command %0d error=%0d expected=%0d",
                   op, cmd_error, expect_error);
        if (cmd_busy || !cmd_ready)
            $fatal(1, "command %0d did not return to idle", op);
    endtask

    initial begin
        clk = 1'b0;
        for (int i = 0; i < 512; i++)
            memory[i] = '0;
        for (int r = 0; r < ROWS; r++) begin
            for (int kk = 0; kk < INNER; kk++)
                memory[A_WORD + r * 8 + kk] = 64'(make_a(r, kk));
        end
        for (int kk = 0; kk < INNER; kk++) begin
            for (int c = 0; c < COLS; c++)
                memory[B_WORD + kk * 6 + c] = 64'(make_b(kk, c));
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        cmd_m = ROWS;
        cmd_k = INNER;
        cmd_a_row = 2;
        cmd_a_k = 1;
        cmd_ext_addr = 64'(A_WORD * 8);
        cmd_ext_stride_bytes = 64;
        issue(LAYMO_LOAD_A, 1'b0);

        cmd_k = INNER;
        cmd_p = COLS;
        cmd_b_k = 2;
        cmd_b_col = 3;
        cmd_ext_addr = 64'(B_WORD * 8);
        cmd_ext_stride_bytes = 48;
        issue(LAYMO_LOAD_B, 1'b0);

        cmd_m = ROWS;
        cmd_p = COLS;
        cmd_k = INNER;
        cmd_c_row = 1;
        cmd_c_col = 4;
        issue(LAYMO_GEMM, 1'b0);

        cmd_ext_addr = 64'(C_WORD * 8);
        cmd_ext_stride_bytes = 40;
        issue(LAYMO_STORE_C, 1'b0);

        for (int r = 0; r < ROWS; r++) begin
            for (int c = 0; c < COLS; c++) begin
                longint signed expected_value;
                expected_value = 0;
                for (int kk = 0; kk < INNER; kk++)
                    expected_value += longint'(make_a(r, kk)) *
                                      longint'(make_b(kk, c));
                if (memory[C_WORD + r * 5 + c] !== expected_value)
                    $fatal(1, "C[%0d][%0d] expected %0d got %0d",
                           r, c, expected_value, memory[C_WORD + r * 5 + c]);
            end
        end

        cmd_a_row = 9;
        issue(LAYMO_GEMM, 1'b1);
        $display("PASS command DMA and offset GEMM: %0d outputs, cycles=%0d",
                 ROWS * COLS, cycles);
        $finish;
    end
endmodule
