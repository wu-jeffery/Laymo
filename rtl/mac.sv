`timescale 1ns/1ps

// Signed 32 x 32 -> 64 multiply-accumulate. The 64-bit sum wraps on overflow.
module mac (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic               clear,
    input  logic signed [31:0] a,
    input  logic signed [31:0] b,
    output logic signed [63:0] acc
);
    logic signed [63:0] product;

    assign product = a * b;

    always_ff @(posedge clk) begin
        if (!rst_n)
            acc <= '0;
        else if (clear)
            acc <= '0;
        else if (enable)
            acc <= acc + product;
    end
endmodule
