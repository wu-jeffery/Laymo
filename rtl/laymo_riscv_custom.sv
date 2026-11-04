`timescale 1ns/1ps

// Adapter for a RV32 core that forwards custom-0 instructions to Laymo.
// The core supplies decoded rs1/rs2 values and waits for inst_done.
module laymo_riscv_custom #(
    parameter int N = 128,
    parameter int MAX_M = 256,
    parameter int MAX_P = 256,
    parameter int MAX_K = 256
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        inst_valid,
    output logic        inst_ready,
    input  logic [31:0] inst_word,
    output logic [4:0]  rs1_index,
    output logic [4:0]  rs2_index,
    input  logic [31:0] rs1_value,
    input  logic [31:0] rs2_value,
    output logic        inst_done,
    output logic        inst_error,
    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [63:0] mem_req_addr,
    output logic [63:0] mem_req_wdata,
    input  logic        mem_rsp_valid,
    input  logic [31:0] mem_rsp_rdata
);
    import laymo_command_pkg::*;
    localparam logic [6:0] CUSTOM_0 = 7'h0b;
    localparam logic [6:0] SET_MP     = 7'd0;
    localparam logic [6:0] SET_K      = 7'd1;
    localparam logic [6:0] SET_A      = 7'd2;
    localparam logic [6:0] SET_B      = 7'd3;
    localparam logic [6:0] SET_C      = 7'd4;
    localparam logic [6:0] SET_EXT    = 7'd5;
    localparam logic [6:0] SET_STRIDE = 7'd6;
    localparam logic [6:0] ISSUE_A    = 7'd16;
    localparam logic [6:0] ISSUE_B    = 7'd17;
    localparam logic [6:0] ISSUE_GEMM = 7'd18;
    localparam logic [6:0] ISSUE_C    = 7'd19;

    logic [31:0] m_reg, p_reg, k_reg;
    logic [31:0] a_row_reg, a_k_reg, b_k_reg, b_col_reg;
    logic [31:0] c_row_reg, c_col_reg, stride_reg;
    logic [63:0] ext_reg;
    logic [2:0] command_opcode;
    logic command_valid, command_ready, command_busy;
    logic command_done, command_error;
    logic pending;
    logic issue_instruction;
    logic valid_encoding;

    assign issue_instruction = (inst_word[31:25] == ISSUE_A) ||
                               (inst_word[31:25] == ISSUE_B) ||
                               (inst_word[31:25] == ISSUE_GEMM) ||
                               (inst_word[31:25] == ISSUE_C);
    assign valid_encoding = (inst_word[6:0] == CUSTOM_0) &&
                            (inst_word[14:12] == 3'b000) &&
                            (inst_word[11:7] == 5'b00000);
    assign rs1_index = inst_word[19:15];
    assign rs2_index = inst_word[24:20];
    assign inst_ready = command_ready && !command_busy && !pending;
    assign command_valid = inst_valid && inst_ready && valid_encoding &&
                           issue_instruction;

    always_comb begin
        case (inst_word[31:25])
            ISSUE_A: command_opcode = LAYMO_LOAD_A;
            ISSUE_B: command_opcode = LAYMO_LOAD_B;
            ISSUE_GEMM: command_opcode = LAYMO_GEMM;
            ISSUE_C: command_opcode = LAYMO_STORE_C;
            default: command_opcode = '0;
        endcase
    end

    laymo_accelerator #(.N(N), .MAX_M(MAX_M), .MAX_P(MAX_P),
                        .MAX_K(MAX_K)) accelerator (
        .clk, .rst_n,
        .cmd_valid(command_valid), .cmd_ready(command_ready),
        .cmd_opcode(command_opcode),
        .cmd_m(m_reg), .cmd_p(p_reg), .cmd_k(k_reg),
        .cmd_ext_addr(ext_reg), .cmd_ext_stride_bytes(stride_reg),
        .cmd_a_row(a_row_reg), .cmd_a_k(a_k_reg),
        .cmd_b_k(b_k_reg), .cmd_b_col(b_col_reg),
        .cmd_c_row(c_row_reg), .cmd_c_col(c_col_reg),
        .cmd_busy(command_busy), .cmd_done(command_done),
        .cmd_error(command_error),
        .mem_req_valid, .mem_req_ready, .mem_req_write,
        .mem_req_addr, .mem_req_wdata, .mem_rsp_valid, .mem_rsp_rdata
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_reg <= '0;
            p_reg <= '0;
            k_reg <= '0;
            a_row_reg <= '0;
            a_k_reg <= '0;
            b_k_reg <= '0;
            b_col_reg <= '0;
            c_row_reg <= '0;
            c_col_reg <= '0;
            ext_reg <= '0;
            stride_reg <= '0;
            pending <= 1'b0;
            inst_done <= 1'b0;
            inst_error <= 1'b0;
        end else begin
            inst_done <= 1'b0;
            inst_error <= 1'b0;
            if (pending && command_done) begin
                pending <= 1'b0;
                inst_done <= 1'b1;
                inst_error <= command_error;
            end
            if (inst_valid && inst_ready) begin
                if (!valid_encoding) begin
                    inst_done <= 1'b1;
                    inst_error <= 1'b1;
                end else begin
                    case (inst_word[31:25])
                        SET_MP: begin
                            m_reg <= rs1_value;
                            p_reg <= rs2_value;
                            inst_done <= 1'b1;
                        end
                        SET_K: begin
                            k_reg <= rs1_value;
                            inst_done <= 1'b1;
                        end
                        SET_A: begin
                            a_row_reg <= rs1_value;
                            a_k_reg <= rs2_value;
                            inst_done <= 1'b1;
                        end
                        SET_B: begin
                            b_k_reg <= rs1_value;
                            b_col_reg <= rs2_value;
                            inst_done <= 1'b1;
                        end
                        SET_C: begin
                            c_row_reg <= rs1_value;
                            c_col_reg <= rs2_value;
                            inst_done <= 1'b1;
                        end
                        SET_EXT: begin
                            ext_reg <= {rs2_value, rs1_value};
                            inst_done <= 1'b1;
                        end
                        SET_STRIDE: begin
                            stride_reg <= rs1_value;
                            inst_done <= 1'b1;
                        end
                        ISSUE_A, ISSUE_B, ISSUE_GEMM, ISSUE_C:
                            pending <= 1'b1;
                        default: begin
                            inst_done <= 1'b1;
                            inst_error <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end
endmodule
