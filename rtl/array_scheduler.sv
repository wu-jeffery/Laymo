`timescale 1ns/1ps

// Accepts paired A/B vectors for one C tile and skews each array edge lane.
module array_scheduler #(
    parameter int N = 128
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               tile_start,
    input  logic [31:0]        tile_rows,
    input  logic [31:0]        tile_cols,
    input  logic [31:0]        k_len,
    input  logic               vector_valid,
    output logic               vector_ready,
    input  logic signed [31:0] a_vector [N],
    input  logic signed [31:0] b_vector [N],
    output logic               feed_done,
    output logic               compute_done,
    output logic signed [31:0] a_in [N],
    output logic               a_valid [N],
    output logic signed [31:0] b_in [N],
    output logic               b_valid [N]
);
    localparam int LATENCY_BITS = (N > 1) ? $clog2(2 * N) : 1;
    logic feeding;
    logic [31:0] next_k;
    logic [LATENCY_BITS-1:0] remaining_latency;
    logic completion_pending;
    logic accept_vector;

    assign vector_ready = feeding && (next_k < k_len);
    assign accept_vector = vector_valid && vector_ready;
    assign feed_done = accept_vector && (next_k == k_len - 1);
    // The final active PE is (tile_rows-1, tile_cols-1). Both operands
    // traverse that many row/column links after the last vector is accepted.
    assign compute_done = completion_pending && (remaining_latency == 0);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            feeding <= 1'b0;
            next_k <= '0;
            remaining_latency <= '0;
            completion_pending <= 1'b0;
        end else if (tile_start) begin
            feeding <= 1'b1;
            next_k <= '0;
            remaining_latency <= '0;
            completion_pending <= 1'b0;
        end else begin
            if (feed_done) begin
                remaining_latency <= LATENCY_BITS'(tile_rows + tile_cols - 2);
                completion_pending <= 1'b1;
            end else if (completion_pending) begin
                if (remaining_latency != 0)
                    remaining_latency <= remaining_latency - 1'b1;
                else
                    completion_pending <= 1'b0;
            end
            if (accept_vector) begin
                next_k <= next_k + 1;
                if (feed_done)
                    feeding <= 1'b0;
            end
        end
    end

    for (genvar lane = 0; lane < N; lane++) begin : lanes
        skew_buffer #(.DELAY(lane)) a_skew (
            .clk, .rst_n, .clear(tile_start),
            .in_data(a_vector[lane]),
            .in_valid(accept_vector && (lane < tile_rows)),
            .out_data(a_in[lane]), .out_valid(a_valid[lane])
        );
        skew_buffer #(.DELAY(lane)) b_skew (
            .clk, .rst_n, .clear(tile_start),
            .in_data(b_vector[lane]),
            .in_valid(accept_vector && (lane < tile_cols)),
            .out_data(b_in[lane]), .out_valid(b_valid[lane])
        );
    end
endmodule
