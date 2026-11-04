#include "Vlaymo_riscv_custom.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

// A small CPU and external-memory model for the RTL instruction port. It
// sends the same custom-0 instruction words that RV32 software would emit.
class Bench {
public:
    Vlaymo_riscv_custom dut;
    std::array<uint64_t, 512> memory{};
    uint64_t cycles = 0;

    void tick() {
        dut.clk = 0;
        dut.mem_req_ready = (cycles % 4 != 1);
        dut.mem_rsp_valid = response_valid_;
        dut.mem_rsp_rdata = response_data_;
        dut.eval();

        const bool request = dut.mem_req_valid && dut.mem_req_ready;
        const bool write = dut.mem_req_write;
        const uint64_t address = dut.mem_req_addr;
        const uint64_t data = dut.mem_req_wdata;

        dut.clk = 1;
        dut.eval();

        response_valid_ = false;
        if (request) {
            if ((address & 7) != 0 || address / 8 >= memory.size())
                throw std::runtime_error("invalid external-memory address");
            if (write) {
                memory[address / 8] = data;
            } else {
                response_data_ = static_cast<uint32_t>(memory[address / 8]);
                response_valid_ = true;  // Returned on the following cycle.
            }
        }
        ++cycles;
    }

    void reset() {
        dut.rst_n = 0;
        dut.inst_valid = 0;
        dut.inst_word = 0;
        dut.rs1_value = 0;
        dut.rs2_value = 0;
        response_valid_ = false;
        response_data_ = 0;
        for (int i = 0; i < 3; ++i) tick();
        dut.rst_n = 1;
    }

    void instruction(uint32_t funct7, uint32_t rs1, uint32_t rs2,
                     bool expect_error = false) {
        // R type: funct7 | rs2=x2 | rs1=x1 | funct3=0 | rd=x0 | custom-0.
        dut.inst_word = (funct7 << 25) | (2u << 20) | (1u << 15) | 0x0bu;
        dut.rs1_value = rs1;
        dut.rs2_value = rs2;
        dut.inst_valid = 1;
        dut.clk = 0;
        dut.eval();
        if (!dut.inst_ready || dut.rs1_index != 1 || dut.rs2_index != 2)
            throw std::runtime_error("CPU instruction handshake failed");

        tick();
        dut.inst_valid = 0;
        for (int timeout = 0; timeout < 2000; ++timeout) {
            if (dut.inst_done) {
                if (static_cast<bool>(dut.inst_error) != expect_error)
                    throw std::runtime_error("unexpected instruction error");
                return;
            }
            tick();
        }
        throw std::runtime_error("instruction timed out");
    }

private:
    bool response_valid_ = false;
    uint32_t response_data_ = 0;
};

static int32_t make_a(int row, int k) { return row * 3 - k - 4; }
static int32_t make_b(int k, int col) { return k * 2 + col - 3; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    try {
        constexpr int rows = 5, cols = 3, inner = 5;
        constexpr int a_word = 16, b_word = 128, c_word = 256;
        Bench bench;
        for (int r = 0; r < rows; ++r)
            for (int k = 0; k < inner; ++k)
                bench.memory[a_word + r * 8 + k] =
                    static_cast<uint64_t>(static_cast<int64_t>(make_a(r, k)));
        for (int k = 0; k < inner; ++k)
            for (int c = 0; c < cols; ++c)
                bench.memory[b_word + k * 6 + c] =
                    static_cast<uint64_t>(static_cast<int64_t>(make_b(k, c)));
        bench.reset();

        bench.instruction(0, rows, cols);       // SET_MP
        bench.instruction(1, inner, 0);         // SET_K
        bench.instruction(2, 2, 1);             // SET_A: A[2][1]
        bench.instruction(3, 2, 3);             // SET_B: B[2][3]
        bench.instruction(4, 1, 4);             // SET_C: C[1][4]
        bench.instruction(5, a_word * 8, 0);    // SET_EXT A
        bench.instruction(6, 64, 0);            // SET_STRIDE A
        bench.instruction(16, 0, 0);            // LOAD_A
        bench.instruction(5, b_word * 8, 0);    // SET_EXT B
        bench.instruction(6, 48, 0);            // SET_STRIDE B
        bench.instruction(17, 0, 0);            // LOAD_B
        bench.instruction(18, 0, 0);            // GEMM
        bench.instruction(5, c_word * 8, 0);    // SET_EXT C
        bench.instruction(6, 40, 0);            // SET_STRIDE C
        bench.instruction(19, 0, 0);            // STORE_C

        for (int r = 0; r < rows; ++r) {
            for (int c = 0; c < cols; ++c) {
                int64_t expected = 0;
                for (int k = 0; k < inner; ++k)
                    expected += static_cast<int64_t>(make_a(r, k)) *
                                static_cast<int64_t>(make_b(k, c));
                const auto got = static_cast<int64_t>(
                    bench.memory[c_word + r * 5 + c]);
                if (got != expected)
                    throw std::runtime_error("C[" + std::to_string(r) + "][" +
                                             std::to_string(c) + "] mismatch");
            }
        }

        // Software cannot increase the built scratchpad capacities.
        bench.instruction(0, 11, cols);
        bench.instruction(2, 0, 0);
        bench.instruction(16, 0, 0, true);
        bench.instruction(0, rows, 11);
        bench.instruction(3, 0, 0);
        bench.instruction(17, 0, 0, true);
        bench.instruction(0, rows, cols);
        bench.instruction(1, 9, 0);
        bench.instruction(16, 0, 0, true);
        std::cout << "PASS C++ custom-instruction RTL test: " << rows * cols
                  << " outputs, M/P/K capacity errors checked, cycles="
                  << bench.cycles << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL C++ custom-instruction RTL test: " << error.what()
                  << '\n';
        return 1;
    }
}
