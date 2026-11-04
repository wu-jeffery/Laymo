`timescale 1ns/1ps

module tb_laymo_riscv_custom;
    logic clk;
    logic rst_n;
    logic inst_valid;
    logic inst_ready, inst_done, inst_error;
    logic [31:0] inst_word, rs1_value, rs2_value;
    logic [4:0] rs1_index, rs2_index;
    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [63:0] mem_req_addr, mem_req_wdata;
    logic mem_rsp_valid;
    logic [31:0] mem_rsp_rdata;
    logic signed [63:0] memory [64];

    always #5 clk = ~clk;
    assign mem_req_ready = 1'b1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_rsp_valid <= 1'b0;
            mem_rsp_rdata <= '0;
        end else begin
            mem_rsp_valid <= 1'b0;
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_addr[2:0] != 0 || mem_req_addr / 8 >= 64)
                    $fatal(1, "bad memory address");
                if (mem_req_write)
                    memory[mem_req_addr[8:3]] <= $signed(mem_req_wdata);
                else begin
                    mem_rsp_valid <= 1'b1;
                    mem_rsp_rdata <= memory[mem_req_addr[8:3]][31:0];
                end
            end
        end
    end

    laymo_riscv_custom #(.N(2), .MAX_M(4), .MAX_P(4), .MAX_K(4)) dut (.*);

    task automatic instruction(input logic [6:0] funct7,
                               input logic [31:0] rs1,
                               input logic [31:0] rs2,
                               input bit expected_error);
        bit finished;
        @(negedge clk);
        if (!inst_ready)
            $fatal(1, "instruction port not ready");
        inst_word = {funct7, 5'd2, 5'd1, 3'd0, 5'd0, 7'h0b};
        rs1_value = rs1;
        rs2_value = rs2;
        inst_valid = 1'b1;
        #1;
        if (rs1_index != 1 || rs2_index != 2)
            $fatal(1, "register index decode failed");
        @(posedge clk);
        #1;
        inst_valid = 1'b0;
        finished = inst_done;
        for (int t = 0; t < 100 && !finished; t++) begin
            @(posedge clk);
            #1;
            finished = inst_done;
        end
        if (!finished || inst_error !== expected_error)
            $fatal(1, "instruction %0d done=%0d error=%0d",
                   funct7, finished, inst_error);
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        inst_valid = 1'b0;
        inst_word = '0;
        rs1_value = '0;
        rs2_value = '0;
        for (int i = 0; i < 64; i++)
            memory[i] = '0;
        memory[4] = 3;
        memory[8] = -2;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        instruction(7'd0, 1, 1, 1'b0);   // M=1, P=1
        instruction(7'd1, 1, 0, 1'b0);   // K=1
        instruction(7'd2, 1, 1, 1'b0);   // A scratchpad base
        instruction(7'd3, 1, 1, 1'b0);   // B scratchpad base
        instruction(7'd4, 2, 2, 1'b0);   // C scratchpad base
        instruction(7'd5, 32, 0, 1'b0);  // A external byte address
        instruction(7'd6, 0, 0, 1'b0);   // packed rows
        instruction(7'd16, 0, 0, 1'b0);  // LOAD A
        instruction(7'd5, 64, 0, 1'b0);  // B external byte address
        instruction(7'd17, 0, 0, 1'b0);  // LOAD B
        instruction(7'd18, 0, 0, 1'b0);  // GEMM
        instruction(7'd5, 96, 0, 1'b0);  // C external byte address
        instruction(7'd19, 0, 0, 1'b0);  // STORE C
        if (memory[12] !== -6)
            $fatal(1, "instruction sequence produced %0d, expected -6",
                   memory[12]);
        instruction(7'd127, 0, 0, 1'b1); // unsupported function
        $display("PASS RISC-V custom-0 instruction sequence");
        $finish;
    end
endmodule
