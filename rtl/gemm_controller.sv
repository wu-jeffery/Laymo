`timescale 1ns/1ps

// Sequences output tiles. The array scheduler owns timing within a tile.
module gemm_controller #(
    parameter int N = 128
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [31:0] m,
    input  logic [31:0] p,
    input  logic [31:0] k,
    input  logic        read_stall,
    input  logic        vector_ready,
    input  logic        feed_done,
    input  logic        compute_done,
    input  logic        buffer_in_ready,
    input  logic        buffer_out_valid,
    output logic        busy,
    output logic        done,
    output logic        array_clear,
    output logic        array_drain,
    output logic        tile_start,
    output logic [31:0] tile_m0,
    output logic [31:0] tile_p0,
    output logic [31:0] tile_rows,
    output logic [31:0] tile_cols,
    output logic [31:0] k_len,
    output logic        read_req,
    output logic [31:0] read_k,
    output logic        buffer_in_valid,
    output logic [31:0] buffer_in_row
);
    localparam int unsigned N_U = N;
    typedef enum logic [2:0] {
        IDLE, CLEAR_TILE, START_TILE, FETCH, WAIT_COMPUTE, DRAIN
    } state_t;
    state_t state;
    logic [31:0] m_reg, p_reg, k_reg;
    logic [31:0] request_k, drain_row;

    assign busy = (state != IDLE);
    assign array_clear = (state == CLEAR_TILE);
    assign tile_start = (state == START_TILE);
    assign k_len = k_reg;
    assign tile_rows = ((m_reg - tile_m0) < N_U) ? (m_reg - tile_m0) : N_U;
    assign tile_cols = ((p_reg - tile_p0) < N_U) ? (p_reg - tile_p0) : N_U;
    assign read_req = (state == FETCH) && (request_k < k_reg) &&
                      !read_stall && vector_ready;
    assign read_k = request_k;
    assign buffer_in_valid = (state == DRAIN) && (drain_row < tile_rows);
    assign buffer_in_row = (drain_row < tile_rows) ? drain_row : 32'b0;
    assign array_drain = buffer_in_valid && buffer_in_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            m_reg <= '0;
            p_reg <= '0;
            k_reg <= '0;
            tile_m0 <= '0;
            tile_p0 <= '0;
            request_k <= '0;
            drain_row <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    m_reg <= m;
                    p_reg <= p;
                    k_reg <= k;
                    tile_m0 <= '0;
                    tile_p0 <= '0;
                    if ((m == 0) || (p == 0))
                        done <= 1'b1;
                    else
                        state <= CLEAR_TILE;
                end
                CLEAR_TILE: state <= START_TILE;
                START_TILE: begin
                    request_k <= '0;
                    drain_row <= '0;
                    state <= (k_reg == 0) ? DRAIN : FETCH;
                end
                FETCH: begin
                    if (read_req)
                        request_k <= request_k + 1;
                    if (feed_done)
                        state <= WAIT_COMPUTE;
                end
                WAIT_COMPUTE: if (compute_done)
                    state <= DRAIN;
                DRAIN: begin
                    if (buffer_in_valid && buffer_in_ready)
                        drain_row <= drain_row + 1;
                    if ((drain_row == tile_rows) && !buffer_out_valid) begin
                        if (tile_p0 + N_U < p_reg) begin
                            tile_p0 <= tile_p0 + N_U;
                            state <= CLEAR_TILE;
                        end else if (tile_m0 + N_U < m_reg) begin
                            tile_m0 <= tile_m0 + N_U;
                            tile_p0 <= '0;
                            state <= CLEAR_TILE;
                        end else begin
                            done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
