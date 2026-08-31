#include "VUARTProbe.h"
#include "verilated.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {
constexpr unsigned clocks_per_bit = 10;

void tick(VUARTProbe& dut)
{
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

void wait_ticks(VUARTProbe& dut, unsigned count)
{
    while (count-- != 0) tick(dut);
}

uint8_t receive_byte(VUARTProbe& dut)
{
    unsigned timeout = 10000;
    while ((bool)dut.uart_tx_out && timeout-- != 0) tick(dut);
    if ((bool)dut.uart_tx_out) {
        std::fprintf(stderr, "autonomous UART response timeout\n");
        std::exit(1);
    }
    wait_ticks(dut, clocks_per_bit + clocks_per_bit / 2);
    uint8_t value = 0;
    for (unsigned bit = 0; bit < 8; ++bit) {
        value |= (uint8_t)((bool)dut.uart_tx_out) << bit;
        wait_ticks(dut, clocks_per_bit);
    }
    if (!(bool)dut.uart_tx_out) {
        std::fprintf(stderr, "autonomous UART stop bit is low\n");
        std::exit(1);
    }
    wait_ticks(dut, clocks_per_bit / 2);
    return value;
}

uint32_t le32(const uint8_t* data)
{
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

uint32_t crc32(const uint8_t* data, size_t size)
{
    uint32_t crc = 0xffffffffU;
    for (size_t index = 0; index < size; ++index) {
        crc ^= data[index];
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320U : 0);
    }
    return crc ^ 0xffffffffU;
}
} // namespace

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    VUARTProbe dut;
    dut.uart_rx_in = 1;
    dut.dump_trigger_in = 0;
    dut.probe_in[0] = 0x12345678U;
    dut.reset = 1;
    wait_ticks(dut, 4);
    dut.reset = 0;

    const std::array<uint8_t, 4> magic{'U', 'P', 'R', 'B'};
    std::vector<uint8_t> window;
    while (true) {
        window.push_back(receive_byte(dut));
        while (window.size() > magic.size()) window.erase(window.begin());
        if (window.size() == magic.size()
            && std::equal(window.begin(), window.end(), magic.begin()))
            break;
    }

    constexpr size_t response_size = 32 + 4 * 16 + 8;
    std::vector<uint8_t> response(response_size);
    std::copy(magic.begin(), magic.end(), response.begin());
    for (size_t index = 4; index < response.size(); ++index)
        response[index] = receive_byte(dut);

    const uint8_t* payload = response.data() + 32;
    const uint8_t* trailer = payload + 4 * 16;
    if (le32(response.data() + 8) != 4
        || std::memcmp(trailer, "END!", 4) != 0
        || le32(trailer + 4) != crc32(payload, 4 * 16)) {
        std::fprintf(stderr, "autonomous UART dump framing/CRC mismatch\n");
        return 1;
    }

    std::printf("UART_PROBE_AUTO_TEST_PASS bytes=%zu crc=%08x\n",
        response.size(), le32(trailer + 4));
    dut.final();
    return 0;
}
