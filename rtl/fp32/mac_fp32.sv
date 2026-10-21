`timescale 1ns/1ps

module mac_fp32 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic        clear,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] acc
);
    import fp32_pkg::*;

    always_ff @(posedge clk) begin
        if (!rst_n)
            acc <= 32'b0;
        else if (clear)
            acc <= 32'b0;
        else if (enable)
            acc <= fp32_add(acc, fp32_mul(a, b));
    end
endmodule
