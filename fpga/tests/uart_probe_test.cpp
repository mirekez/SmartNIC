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

void send_byte(VUARTProbe& dut, uint8_t value)
{
    dut.uart_rx_in = 0;
    wait_ticks(dut, clocks_per_bit);
    for (unsigned bit = 0; bit < 8; ++bit) {
        dut.uart_rx_in = (value >> bit) & 1u;
        wait_ticks(dut, clocks_per_bit);
    }
    dut.uart_rx_in = 1;
    wait_ticks(dut, clocks_per_bit);
}

uint8_t receive_byte(VUARTProbe& dut)
{
    unsigned timeout = 1000;
    while ((bool)dut.uart_tx_out && timeout-- != 0) tick(dut);
    if ((bool)dut.uart_tx_out) {
        std::fprintf(stderr, "UART probe response timeout\n");
        std::exit(1);
    }

    // Move from the observed start edge to the center of data bit zero.
    wait_ticks(dut, clocks_per_bit + clocks_per_bit / 2);
    uint8_t value = 0;
    for (unsigned bit = 0; bit < 8; ++bit) {
        value |= (uint8_t)((bool)dut.uart_tx_out) << bit;
        wait_ticks(dut, clocks_per_bit);
    }
    if (!(bool)dut.uart_tx_out) {
        std::fprintf(stderr, "UART probe stop bit is low\n");
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
    dut.reset = 1;
    wait_ticks(dut, 4);
    dut.reset = 0;

    constexpr std::array<uint8_t, 18> heartbeat{
        'U', 'A', 'R', 'T', '_', 'P', 'R', 'O', 'B', 'E',
        '_', 'R', 'E', 'A', 'D', 'Y', '\r', '\n'};
    for (uint8_t expected : heartbeat) {
        uint8_t received = receive_byte(dut);
        if (received != expected) {
            std::fprintf(stderr,
                "UART probe heartbeat mismatch: got %02x expected %02x\n",
                received, expected);
            return 1;
        }
    }

    // Vary the low probe word while the four-entry circular memory fills.
    for (uint32_t cycle = 0; cycle < 40; ++cycle) {
        dut.probe_in[0] = 0xa5000000U | cycle;
        tick(dut);
    }
    for (uint8_t byte : std::array<uint8_t, 4>{'D', 'U', 'M', 'P'})
        send_byte(dut, byte);

    constexpr size_t expected_size = 32 + 4 * 16 + 8;
    std::vector<uint8_t> response;
    const std::array<uint8_t, 4> magic{'U', 'P', 'R', 'B'};
    while (true) {
        response.push_back(receive_byte(dut));
        while (response.size() > magic.size()) response.erase(response.begin());
        if (response.size() == magic.size()
            && std::equal(response.begin(), response.end(), magic.begin()))
            break;
    }
    response.resize(expected_size);
    for (size_t index = 4; index < response.size(); ++index)
        response[index] = receive_byte(dut);

    if (std::memcmp(response.data(), "UPRB", 4) != 0
        || response[4] != 1 || response[5] != 32 || response[6] != 16
        || le32(&response[8]) != 4 || le32(&response[12]) != 4
        || le32(&response[16]) != 1000 || le32(&response[24]) != 4
        || std::memcmp(&response[28], "ETH2", 4) != 0) {
        std::fprintf(stderr,
            "UART probe header mismatch: magic=%02x%02x%02x%02x "
            "version=%u header=%u record=%u count=%u div=%u hz=%u depth=%u "
            "schema=%c%c%c%c\n",
            response[0], response[1], response[2], response[3], response[4],
            response[5], response[6], le32(&response[8]), le32(&response[12]),
            le32(&response[16]), le32(&response[24]), response[28], response[29],
            response[30], response[31]);
        return 1;
    }

    const uint8_t* payload = &response[32];
    for (unsigned record = 1; record < 4; ++record) {
        if (le32(payload + record * 16)
            <= le32(payload + (record - 1) * 16)) {
            std::fprintf(stderr,
                "UART probe records are not chronological: %u %u %u %u\n",
                le32(payload), le32(payload + 16), le32(payload + 32),
                le32(payload + 48));
            return 1;
        }
    }
    const uint8_t* trailer = payload + 4 * 16;
    if (std::memcmp(trailer, "END!", 4) != 0
        || le32(trailer + 4) != crc32(payload, 4 * 16)) {
        std::fprintf(stderr, "UART probe CRC/trailer mismatch\n");
        return 1;
    }

    // The USB RTS input is an independent command fallback. Its synchronized
    // transition must start another dump without UART RX data.
    wait_ticks(dut, 40);
    dut.dump_trigger_in = 1;
    bool external_trigger_seen = false;
    for (unsigned cycle = 0; cycle < 16; ++cycle) {
        tick(dut);
        external_trigger_seen |= (bool)dut.dumping_out;
    }
    if (!external_trigger_seen) {
        std::fprintf(stderr, "UART probe external trigger was not accepted\n");
        return 1;
    }

    std::printf("UART_PROBE_TEST_PASS bytes=%zu crc=%08x\n",
        response.size(), le32(trailer + 4));
    dut.final();
    return 0;
}
