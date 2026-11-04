`timescale 1ns/1ps

// A fixed cycle delay for one operand lane. Invalid bubbles advance too.
module skew_buffer #(
    parameter int DELAY = 0
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic               clk,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic               rst_n,
    input  logic               clear,
    input  logic signed [31:0] in_data,
    input  logic               in_valid,
    output logic signed [31:0] out_data,
    output logic               out_valid
);
    if (DELAY == 0) begin : bypass
        assign out_data = in_data;
        assign out_valid = in_valid && rst_n && !clear;
    end else begin : delayed
        logic signed [31:0] data_pipe [DELAY];
        logic valid_pipe [DELAY];

        // Data needs no reset because invalid entries are never consumed.
        always_ff @(posedge clk) begin
            if (!rst_n || clear) begin
                for (int i = 0; i < DELAY; i++)
                    valid_pipe[i] <= 1'b0;
            end else begin
                data_pipe[0] <= in_data;
                valid_pipe[0] <= in_valid;
                for (int i = 1; i < DELAY; i++) begin
                    data_pipe[i] <= data_pipe[i-1];
                    valid_pipe[i] <= valid_pipe[i-1];
                end
            end
        end

        assign out_data = data_pipe[DELAY-1];
        assign out_valid = valid_pipe[DELAY-1];
    end
endmodule
