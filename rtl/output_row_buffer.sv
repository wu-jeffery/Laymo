`timescale 1ns/1ps

// One-row elastic buffer between the array read port and C scratchpad.
module output_row_buffer #(
    parameter int N = 128
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [63:0] in_data [N],
    input  logic [31:0]        in_m0,
    input  logic [31:0]        in_p0,
    input  logic [31:0]        in_row,
    input  logic [31:0]        in_cols,
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [63:0] out_data [N],
    output logic [31:0]        out_m0,
    output logic [31:0]        out_p0,
    output logic [31:0]        out_row,
    output logic [31:0]        out_cols
);
    assign in_ready = !out_valid || out_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_m0 <= '0;
            out_p0 <= '0;
            out_row <= '0;
            out_cols <= '0;
            for (int c = 0; c < N; c++)
                out_data[c] <= '0;
        end else if (in_ready) begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_m0 <= in_m0;
                out_p0 <= in_p0;
                out_row <= in_row;
                out_cols <= in_cols;
                for (int c = 0; c < N; c++)
                    out_data[c] <= in_data[c];
            end
        end
    end
endmodule
