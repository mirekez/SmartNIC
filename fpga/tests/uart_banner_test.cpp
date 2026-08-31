#include "Vuart_banner_tx.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <string_view>

namespace {
constexpr unsigned clocks_per_bit = 10;
constexpr std::string_view expected =
    "KLUSTERLAB2 UART_USB_RXD A17 115200 8N1\r\n";

void tick(Vuart_banner_tx& dut)
{
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

bool sample_bit(Vuart_banner_tx& dut, bool expected_bit,
    size_t byte_index, unsigned bit_index)
{
    for (unsigned cycle = 0; cycle < clocks_per_bit; ++cycle) {
        if ((bool)dut.tx != expected_bit) {
            std::fprintf(stderr,
                "UART byte %zu bit %u cycle %u: got %u, expected %u\n",
                byte_index, bit_index, cycle, (unsigned)dut.tx,
                (unsigned)expected_bit);
            return false;
        }
        tick(dut);
    }
    return true;
}
} // namespace

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Vuart_banner_tx dut;

    dut.reset = 1;
    for (unsigned cycle = 0; cycle < 5; ++cycle) tick(dut);
    dut.reset = 0;

    // The first banner begins on the first baud tick after reset release.
    unsigned wait_cycles = 0;
    while ((bool)dut.tx && wait_cycles < 2 * clocks_per_bit) {
        tick(dut);
        ++wait_cycles;
    }
    if ((bool)dut.tx) {
        std::fprintf(stderr, "UART start bit did not appear\n");
        return 1;
    }

    for (size_t byte_index = 0; byte_index < expected.size(); ++byte_index) {
        const uint8_t value = (uint8_t)expected[byte_index];
        if (!sample_bit(dut, false, byte_index, 0)) return 1;
        for (unsigned data_bit = 0; data_bit < 8; ++data_bit) {
            if (!sample_bit(dut, (value >> data_bit) & 1u,
                    byte_index, data_bit + 1))
                return 1;
        }
        if (!sample_bit(dut, true, byte_index, 9)) return 1;
    }

    // REPEAT_GAP_BITS is three in this simulation. It must remain idle for at
    // least two complete bit periods after the banner's stop bit.
    for (unsigned cycle = 0; cycle < 2 * clocks_per_bit; ++cycle) {
        if (!(bool)dut.tx) {
            std::fprintf(stderr, "UART did not hold idle high in repeat gap\n");
            return 1;
        }
        tick(dut);
    }

    std::printf("UART_BANNER_TEST_PASS bytes=%zu clocks_per_bit=%u\n",
        expected.size(), clocks_per_bit);
    dut.final();
    return 0;
}
