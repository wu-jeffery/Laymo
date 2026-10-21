#include <bit>
#include <cstdint>

// Keep the multiply and add as separate binary32 operations, matching the RTL.
extern "C" std::uint32_t fp32_reference(std::uint32_t acc_bits,
                                          std::uint32_t a_bits,
                                          std::uint32_t b_bits) {
    const float acc = std::bit_cast<float>(acc_bits);
    const float a = std::bit_cast<float>(a_bits);
    const float b = std::bit_cast<float>(b_bits);
    volatile float product = a * b;
    const float result = acc + product;
    return std::bit_cast<std::uint32_t>(result);
}
