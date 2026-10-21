`timescale 1ns/1ps

module tb_mac;
    logic clk;
    logic rst_n = 1'b0;
    logic enable = 1'b0;
    logic clear = 1'b0;
    logic signed [31:0] a = '0;
    logic signed [31:0] b = '0;
    logic signed [63:0] acc;
    logic signed [63:0] expected = '0;
    int checks = 0;

    mac dut (.*);
    always #5 clk = ~clk;

    task automatic check_acc;
        if (acc !== expected)
            $fatal(1, "check %0d: expected %016x, got %016x", checks, expected, acc);
        checks++;
    endtask

    task automatic step(
        input logic en,
        input logic clr,
        input logic signed [31:0] lhs,
        input logic signed [31:0] rhs
    );
        @(negedge clk);
        enable = en;
        clear = clr;
        a = lhs;
        b = rhs;
        if (clr)
            expected = '0;
        else if (en)
            expected = expected + (longint'(lhs) * longint'(rhs));
        @(posedge clk);
        #1;
        check_acc();
    endtask

    initial begin
        clk = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check_acc();
        rst_n = 1'b1;

        step(1, 0, 3, 4);
        step(1, 0, -2, 7);
        step(0, 0, 32'sh7fffffff, 32'sh7fffffff);
        step(1, 1, 99, 99); // clear wins over enable
        step(1, 0, 32'sh80000000, 32'sh80000000);
        step(1, 0, 32'sh80000000, 32'sh80000000); // 64-bit wrap

        @(negedge clk);
        rst_n = 1'b0;
        expected = '0;
        @(posedge clk);
        #1;
        check_acc();
        rst_n = 1'b1;

        for (int i = 0; i < 1000; i++)
            step(1'($urandom % 4 != 0), 1'(i % 137 == 0), $urandom, $urandom);

        $display("PASS: %0d INT32 MAC checks", checks);
        $finish;
    end
endmodule
