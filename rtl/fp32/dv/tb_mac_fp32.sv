`timescale 1ns/1ps

module tb_mac_fp32;
    import "DPI-C" function int unsigned fp32_reference(
        input int unsigned acc_bits,
        input int unsigned a_bits,
        input int unsigned b_bits
    );

    logic clk;
    logic rst_n = 1'b0;
    logic enable = 1'b0;
    logic clear = 1'b0;
    logic [31:0] a = '0;
    logic [31:0] b = '0;
    logic [31:0] acc;
    logic [31:0] reference_acc;
    logic [31:0] random_a, random_b;
    int checks = 0;

    mac_fp32 dut (.*);
    always #5 clk = ~clk;

    task automatic check_acc(input logic [31:0] expected);
        if (acc !== expected)
            $fatal(1, "check %0d: expected %08x, got %08x", checks, expected, acc);
        checks++;
    endtask

    task automatic step(
        input logic en,
        input logic clr,
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input logic [31:0] expected
    );
        @(negedge clk);
        enable = en;
        clear = clr;
        a = lhs;
        b = rhs;
        @(posedge clk);
        #1;
        check_acc(expected);
    endtask

    initial begin
        clk = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check_acc(32'h00000000);
        rst_n = 1'b1;

        step(1, 0, 32'h40400000, 32'h40800000, 32'h41400000); // 3 * 4 = 12
        step(1, 0, 32'hc0000000, 32'h40e00000, 32'hc0000000); // -2 * 7 + 12 = -2
        step(0, 0, 32'h7f800000, 32'h00000000, 32'hc0000000); // hold
        step(1, 0, 32'h3f000000, 32'h3e800000, 32'hbff00000); // +0.125
        step(1, 1, 32'h7f800000, 32'h00000000, 32'h00000000); // clear priority
        step(1, 0, 32'h3fc00000, 32'h40000000, 32'h40400000); // 1.5 * 2 = 3

        // Exact cancellation, a half-ULP tie, and one full ULP at 1.0.
        step(1, 0, 32'hbf800000, 32'h40400000, 32'h00000000);
        step(1, 0, 32'h3f800000, 32'h3f800000, 32'h3f800000);
        step(1, 0, 32'h33800000, 32'h3f800000, 32'h3f800000);
        step(1, 0, 32'h34000000, 32'h3f800000, 32'h3f800001);

        // Flush subnormals to zero; overflow to infinity; invalid 0 * infinity.
        step(1, 1, 32'h00000000, 32'h00000000, 32'h00000000);
        step(1, 0, 32'h00000001, 32'h3f800000, 32'h00000000);
        step(1, 0, 32'h7f7fffff, 32'h40000000, 32'h7f800000);
        step(1, 0, 32'h00000000, 32'h7f800000, 32'h7fc00000);

        // Synchronous reset clears a nonzero accumulator.
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        check_acc(32'h00000000);
        rst_n = 1'b1;
        step(1, 0, 32'hbf800000, 32'h3f800000, 32'hbf800000);

        step(1, 1, 32'h00000000, 32'h00000000, 32'h00000000);
        reference_acc = 32'b0;
        for (int i = 0; i < 500; i++) begin
            if ((i != 0) && (i % 50 == 0)) begin
                step(1, 1, 32'h00000000, 32'h00000000, 32'h00000000);
                reference_acc = 32'b0;
            end
            random_a = $urandom;
            random_b = $urandom;
            random_a[30:23] = 8'(115 + ($urandom % 25));
            random_b[30:23] = 8'(115 + ($urandom % 25));
            reference_acc = fp32_reference(reference_acc, random_a, random_b);
            step(1, 0, random_a, random_b, reference_acc);
        end

        $display("PASS: %0d FP32 MAC checks", checks);
        $finish;
    end
endmodule
