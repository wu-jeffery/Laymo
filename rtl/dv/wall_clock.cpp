#include <chrono>

// DPI timer for per-case host runtime. SystemVerilog $time is simulated time.
extern "C" unsigned long long wall_clock_ns() {
    using clock = std::chrono::steady_clock;
    return static_cast<unsigned long long>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            clock::now().time_since_epoch()).count());
}
