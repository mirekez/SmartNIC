#if !defined(SYNTHESIS)

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <print>
#include <random>
#include <string>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

namespace
{

template<typename T, typename V>
static void queue_copy_to_verilator(T& target, const V& value)
{
    std::memset(&target, 0, sizeof(target));
    std::memcpy(&target, &value, std::min(sizeof(target), sizeof(value)));
}

template<typename V, typename T>
static V queue_copy_from_verilator(const T& source)
{
    V value = 0;
    std::memcpy(&value, &source, std::min(sizeof(source), sizeof(value)));
    return value;
}

class PacketQueueTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    TestedQueue dut;
#endif
    bool write_valid = false;
    logic<256> write_data = 0;
    logic<32> write_keep = 0;
    bool write_sop = false;
    bool write_eop = false;
    bool read_ready = false;
    bool clear = false;
    bool error = false;
    std::mt19937 random{0x71de5eed};

    void fail(const char* message)
    {
        std::print("{} {}: {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            QUEUE_LABEL, message);
        error = true;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.write_valid_in = _ASSIGN(write_valid);
        dut.write_data_in = _ASSIGN(write_data);
        dut.write_keep_in = _ASSIGN(write_keep);
        dut.write_sop_in = _ASSIGN(write_sop);
        dut.write_eop_in = _ASSIGN(write_eop);
        dut.read_ready_in = _ASSIGN(read_ready);
        dut.clear_in = _ASSIGN(clear);
        dut.__inst_name = QUEUE_LABEL;
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.reset = reset;
        dut.write_valid_in = write_valid;
        queue_copy_to_verilator(dut.write_data_in, write_data);
        dut.write_keep_in = (uint32_t)(uint64_t)write_keep;
        dut.write_sop_in = write_sop;
        dut.write_eop_in = write_eop;
        dut.read_ready_in = read_ready;
        dut.clear_in = clear;
        dut.eval();
#else
        (void)reset;
        (void)clock;
#endif
    }

    void cycle(bool reset = false)
    {
#ifdef VERILATOR
        drive_verilator(reset, false);
        drive_verilator(reset, true);
        drive_verilator(reset, false);
#else
        dut._work(reset);
        dut._strobe();
#endif
        ++_system_clock;
    }

    bool write_ready_value()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.write_ready_out;
#else
        return dut.write_ready_out();
#endif
    }
    bool read_valid_value()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.read_valid_out;
#else
        return dut.read_valid_out();
#endif
    }
    logic<256> read_data_value()
    {
#ifdef VERILATOR
        return queue_copy_from_verilator<logic<256>>(dut.read_data_out);
#else
        return dut.read_data_out();
#endif
    }
    logic<32> read_keep_value()
    {
#ifdef VERILATOR
        return logic<32>(dut.read_keep_out);
#else
        return dut.read_keep_out();
#endif
    }
    bool read_sop_value()
    {
#ifdef VERILATOR
        return dut.read_sop_out;
#else
        return dut.read_sop_out();
#endif
    }
    bool read_eop_value()
    {
#ifdef VERILATOR
        return dut.read_eop_out;
#else
        return dut.read_eop_out();
#endif
    }
    uint32_t packet_length_value()
    {
#ifdef VERILATOR
        return dut.packet_length_out;
#else
        return (uint32_t)dut.packet_length_out();
#endif
    }
    uint32_t packet_count_value()
    {
#ifdef VERILATOR
        return dut.packet_count_out;
#else
        return (uint32_t)dut.packet_count_out();
#endif
    }
    bool empty_value()
    {
#ifdef VERILATOR
        return dut.empty_out;
#else
        return dut.empty_out();
#endif
    }
    bool protocol_error_value()
    {
#ifdef VERILATOR
        return dut.protocol_error_out;
#else
        return dut.protocol_error_out();
#endif
    }

    void send_beat(const std::vector<uint8_t>& packet, size_t offset,
        size_t bytes, bool sop, bool eop)
    {
        write_data = 0;
        write_keep = 0;
        for (size_t byte = 0; byte < bytes; ++byte) {
            write_data.bits(byte * 8 + 7, byte * 8) = packet[offset + byte];
            write_keep[byte] = 1;
        }
        write_valid = true;
        write_sop = sop;
        write_eop = eop;
        while (!write_ready_value()) cycle();
        cycle();
        write_valid = false;
        write_sop = false;
        write_eop = false;
    }

    void send_packet(const std::vector<uint8_t>& packet,
        bool pause_before_eop = false)
    {
        size_t offset = 0;
        while (offset < packet.size()) {
            size_t bytes = std::min<size_t>(32, packet.size() - offset);
            bool eop = offset + bytes == packet.size();
            send_beat(packet, offset, bytes, offset == 0, eop);
            offset += bytes;
            if (pause_before_eop && !eop) {
                // An incomplete packet must remain invisible to its reader.
                if (read_valid_value()) fail("exposed a packet before EOP");
                for (int i = 0; i < 5; ++i) cycle();
            }
        }
    }

    std::vector<uint8_t> receive_packet()
    {
        std::vector<uint8_t> packet;
        bool first = true;
        bool done = false;
        for (uint32_t timeout = 0; timeout < 2000 && !done; ++timeout) {
            read_ready = (random() & 3u) != 0;
            if (read_valid_value() && read_ready) {
                logic<256> data = read_data_value();
                logic<32> keep = read_keep_value();
                if (read_sop_value() != first) fail("incorrect SOP position");
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (keep[byte]) packet.push_back(
                        (uint8_t)data.bits(byte * 8 + 7, byte * 8));
                }
                done = read_eop_value();
                first = false;
            }
            cycle();
        }
        read_ready = false;
        if (!done) fail("timed out receiving a packet");
        return packet;
    }

public:
    bool run()
    {
        bind_native();
        for (int i = 0; i < 4; ++i) cycle(true);
        if (!empty_value()) fail("queue was not empty after reset");

        std::vector<uint8_t> first(45);
        std::vector<uint8_t> second(64);
        for (uint32_t i = 0; i < first.size(); ++i) first[i] = i ^ 0x5a;
        for (uint32_t i = 0; i < second.size(); ++i) second[i] = i ^ 0xc3;

        // Test 1: store-and-forward visibility and exact front packet length.
        send_packet(first, true);
        if (!read_valid_value() || packet_length_value() != first.size()) {
            fail("committed packet or length was not visible");
        }

        // Test 2: back-to-back packets retain boundaries under read stalls.
        send_packet(second);
        if (packet_count_value() != 2) fail("packet count did not reach two");
        if (receive_packet() != first || receive_packet() != second) {
            fail("packet contents changed across the FIFO");
        }
        if (!empty_value() || packet_count_value() != 0) {
            fail("queue did not become empty after both packets");
        }

        // Test 3: synchronous clear resets queue metadata as well as data.
        send_packet(first);
        clear = true;
        cycle();
        clear = false;
        if (!empty_value() || packet_count_value() != 0) fail("clear failed");
        if (protocol_error_value()) fail("well-formed traffic set protocol error");

        std::print("{} {} test {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            QUEUE_LABEL, error ? "FAILED" : "PASSED");
        return !error;
    }
};

static bool build_queue_verilator()
{
#ifdef VERILATOR
    return true;
#else
    namespace fs = std::filesystem;
    fs::path generated = fs::current_path() / QUEUE_GENERATED_DIR;
    std::vector<std::string> includes = {
        fs::path(QUEUE_SOURCE_FILE).parent_path().string(),
        fs::path(QUEUE_SOURCE_FILE).parent_path().parent_path().string(),
        fs::path(QUEUE_SOURCE_FILE).parent_path().parent_path().parent_path().string(),
        (fs::path(QUEUE_SOURCE_FILE).parent_path().parent_path().parent_path()
            .parent_path() / "cpphdl" / "include").string()};
    return VerilatorCompileInExactFolderFromGenerated(QUEUE_SOURCE_FILE,
        std::string(QUEUE_TOP) + "_verilator", QUEUE_TOP, generated,
        {"SmartNicMemory", "Fifo", "PacketQueue"}, includes);
#endif
}

} // namespace

int main(int argc, char** argv)
{
#ifdef VERILATOR
    Verilated::commandArgs(argc, argv);
#endif
    bool noveril = false;
    for (int i = 1; i < argc; ++i) noveril |= std::strcmp(argv[i], "--noveril") == 0;
    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        ok = build_queue_verilator();
        if (ok) ok = std::system((std::string(QUEUE_TOP) +
            "_verilator/obj_dir/V" + QUEUE_TOP + " --noveril").c_str()) == 0;
    }
#endif
    return PacketQueueTest().run() && ok ? 0 : 1;
}

#endif
