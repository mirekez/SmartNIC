// Native CppHDL and generated-SystemVerilog/Verilator tests for OutputMerger.
// The intentionally retained filename follows the requested test path.

#include "../OutputMerger.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <iostream>
#include <map>
#include <print>
#include <string>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

static uint32_t tx_prbs_step(uint32_t state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

struct TxTestPacket
{
    uint32_t id = 0;
    size_t release_cycle = 0;
    std::vector<uint8_t> bytes;
};

static TxTestPacket make_tx_packet(uint32_t id, size_t size,
    size_t release_cycle)
{
    TxTestPacket packet;
    packet.id = id;
    packet.release_cycle = release_cycle;
    packet.bytes.resize(size);
    uint32_t state = 0x51ed270bu ^ id ^ (uint32_t)(size * 0x9e3779b9u);
    for (size_t byte = 0; byte < size; ++byte) {
        state = tx_prbs_step(state + (uint32_t)byte + 1);
        packet.bytes[byte] = (uint8_t)(state >> 24);
    }
    packet.bytes[0] = (uint8_t)id;
    packet.bytes[1] = (uint8_t)(id >> 8);
    packet.bytes[2] = (uint8_t)(id >> 16);
    packet.bytes[3] = (uint8_t)(id >> 24);
    return packet;
}

static uint32_t tx_packet_id(const std::vector<uint8_t>& bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8)
        | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

template<size_t LANE_WIDTH, size_t FIFO_WORDS = 2048>
class OutputMergerTest
{
    static constexpr size_t STREAMS = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t OUTPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t OUTPUT_BYTES = STREAMS * LANE_BYTES;

#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    OutputMerger<LANE_WIDTH, FIFO_WORDS, 12> dut;
#endif

    logic<STREAMS> input_valid;
    logic<STREAMS * LANE_WIDTH> input_data;
    logic<STREAMS * LANE_BYTES> input_keep;
    logic<STREAMS> input_sop;
    logic<STREAMS> input_eop;
    bool output_ready = false;
    bool error = false;

    template<typename T, typename V>
    static void copy_to_verilator(T& target, const V& value)
    {
        std::memset(&target, 0, sizeof(target));
        std::memcpy(&target, &value, std::min(sizeof(target), sizeof(value)));
    }

    template<typename T, typename V>
    static V copy_from_verilator(const T& source)
    {
        V value = 0;
        std::memcpy(&value, &source, std::min(sizeof(source), sizeof(value)));
        return value;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.tx_valid_in = _ASSIGN_REG(input_valid);
        dut.tx_data_in = _ASSIGN_REG(input_data);
        dut.tx_keep_in = _ASSIGN_REG(input_keep);
        dut.tx_sop_in = _ASSIGN_REG(input_sop);
        dut.tx_eop_in = _ASSIGN_REG(input_eop);
        dut.ready_in = _ASSIGN(output_ready);
        dut.__inst_name = "output_merger";
        dut._assign();
#endif
    }

    void eval_low(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 0;
        dut.reset = reset;
        dut.tx_valid_in = (uint8_t)(uint64_t)input_valid;
        copy_to_verilator(dut.tx_data_in, input_data);
        copy_to_verilator(dut.tx_keep_in, input_keep);
        dut.tx_sop_in = (uint8_t)(uint64_t)input_sop;
        dut.tx_eop_in = (uint8_t)(uint64_t)input_eop;
        dut.ready_in = output_ready;
        dut.eval();
#else
        (void)reset;
#endif
    }

    void rising_edge(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 1;
        dut.reset = reset;
        dut.eval();
#else
        dut._work(reset);
        dut._strobe();
#endif
        ++_system_clock;
    }

    logic<STREAMS> input_ready_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.tx_ready_out);
#else
        return dut.tx_ready_out();
#endif
    }

    bool output_valid_value()
    {
#ifdef VERILATOR
        return dut.valid_out;
#else
        return dut.valid_out();
#endif
    }

    logic<OUTPUT_BITS> output_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.data_out),
            logic<OUTPUT_BITS>>(dut.data_out);
#else
        return dut.data_out();
#endif
    }

    logic<OUTPUT_BYTES> output_keep_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.keep_out),
            logic<OUTPUT_BYTES>>(dut.keep_out);
#else
        return dut.keep_out();
#endif
    }

    logic<OUTPUT_BYTES> output_sop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.sop_out),
            logic<OUTPUT_BYTES>>(dut.sop_out);
#else
        return dut.sop_out();
#endif
    }

    logic<OUTPUT_BYTES> output_eop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.eop_out),
            logic<OUTPUT_BYTES>>(dut.eop_out);
#else
        return dut.eop_out();
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

    logic<STREAMS> fifo_error_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.tx_protocol_error_out);
#else
        return dut.tx_protocol_error_out();
#endif
    }

    void fail(const std::string& message)
    {
        if (!error) std::print("\n{} at cycle {}\n", message, _system_clock);
        error = true;
    }

    bool run_case(const std::string& name,
        std::array<std::vector<TxTestPacket>, STREAMS> schedules,
        bool prefill, bool exact_ipg, bool random_backpressure)
    {
        std::array<size_t, STREAMS> packet_index{};
        std::array<size_t, STREAMS> word_index{};
        std::map<uint32_t, std::vector<uint8_t>> expected;
        std::vector<uint8_t> assembling;
        bool in_frame = false;
        bool saw_frame = false;
        size_t idle_bytes = 0;
        size_t received = 0;
        size_t cycle = 0;
        size_t input_words = 0;
        size_t output_words = 0;
        uint32_t random_state = 0x31415926u + LANE_WIDTH;

        for (size_t stream = 0; stream < STREAMS; ++stream) {
            for (const TxTestPacket& packet : schedules[stream]) {
                expected.emplace(packet.id, packet.bytes);
            }
        }
        const size_t expected_packets = expected.size();
        input_valid = 0;
        input_data = 0;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;
        output_ready = false;
        error = false;
        for (size_t reset_cycle = 0; reset_cycle < 2; ++reset_cycle) {
            eval_low(true);
            rising_edge(true);
        }

        while (!error && received < expected_packets && cycle < 200000) {
            bool all_input_done = true;
            input_valid = 0;
            input_data = 0;
            input_keep = 0;
            input_sop = 0;
            input_eop = 0;
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if (packet_index[stream] >= schedules[stream].size()) continue;
                all_input_done = false;
                const TxTestPacket& packet =
                    schedules[stream][packet_index[stream]];
                if (cycle < packet.release_cycle) continue;
                size_t offset = word_index[stream] * LANE_BYTES;
                size_t bytes = std::min(LANE_BYTES,
                    packet.bytes.size() - offset);
                input_valid[stream] = 1;
                input_sop[stream] = word_index[stream] == 0;
                input_eop[stream] = offset + bytes == packet.bytes.size();
                for (size_t byte = 0; byte < bytes; ++byte) {
                    input_data.bits(stream * LANE_WIDTH + byte * 8 + 7,
                        stream * LANE_WIDTH + byte * 8) =
                        packet.bytes[offset + byte];
                    input_keep[stream * LANE_BYTES + byte] = 1;
                }
            }

            if (prefill) {
                output_ready = all_input_done;
            }
            else if (random_backpressure) {
                random_state = tx_prbs_step(random_state + (uint32_t)cycle);
                output_ready = (random_state & 7) != 0;
            }
            else {
                output_ready = true;
            }

            eval_low(false);
            logic<STREAMS> ready = input_ready_value();
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if (!(bool)input_valid[stream] || !(bool)ready[stream]) continue;
                ++input_words;
                const TxTestPacket& packet =
                    schedules[stream][packet_index[stream]];
                size_t words = (packet.bytes.size() + LANE_BYTES - 1)
                    / LANE_BYTES;
                ++word_index[stream];
                if (word_index[stream] == words) {
                    word_index[stream] = 0;
                    ++packet_index[stream];
                }
            }

            if (output_valid_value() && output_ready) {
                ++output_words;
                logic<OUTPUT_BITS> data = output_data_value();
                logic<OUTPUT_BYTES> keep = output_keep_value();
                logic<OUTPUT_BYTES> sop = output_sop_value();
                logic<OUTPUT_BYTES> eop = output_eop_value();
                for (size_t byte = 0; byte < OUTPUT_BYTES; ++byte) {
                    if (!(bool)keep[byte]) {
                        if ((bool)sop[byte] || (bool)eop[byte]) {
                            fail("boundary asserted on an idle byte");
                            break;
                        }
                        if (in_frame) {
                            fail("idle byte inserted inside a frame");
                            break;
                        }
                        if (saw_frame) ++idle_bytes;
                        continue;
                    }
                    if ((bool)sop[byte]) {
                        if (in_frame) {
                            fail("nested output SOP at aggregate byte "
                                + std::to_string(byte)
                                + ", partial frame bytes="
                                + std::to_string(assembling.size()));
                            break;
                        }
                        if (saw_frame && idle_bytes < 12) {
                            fail("output IPG shorter than 12 bytes");
                            break;
                        }
                        if (saw_frame && exact_ipg && idle_bytes != 12) {
                            fail("prefilled burst did not use minimum IPG");
                            break;
                        }
                        assembling.clear();
                        in_frame = true;
                        idle_bytes = 0;
                    }
                    else if (!in_frame) {
                        fail("output data without SOP");
                        break;
                    }
                    assembling.push_back((uint8_t)data.bits(
                        byte * 8 + 7, byte * 8));
                    if ((bool)eop[byte]) {
                        if (!in_frame || assembling.size() < 4) {
                            fail("malformed output EOP");
                            break;
                        }
                        uint32_t id = tx_packet_id(assembling);
                        auto found = expected.find(id);
                        if (found == expected.end()) {
                            fail("duplicate or unknown output packet");
                            break;
                        }
                        if (assembling != found->second) {
                            fail("PRBS packet mismatch for "
                                + std::to_string(id));
                            break;
                        }
                        expected.erase(found);
                        ++received;
                        in_frame = false;
                        saw_frame = true;
                        idle_bytes = 0;
                    }
                }
            }
            rising_edge(false);
            ++cycle;
        }

        if (protocol_error_value()) {
            fail("OutputMerger raised protocol_error_out; fifo mask="
                + std::to_string((uint32_t)(uint64_t)fifo_error_value()));
        }
        if (!expected.empty() || received != expected_packets) {
            fail("OutputMerger did not return every packet");
        }
        if (in_frame) fail("OutputMerger retained a partial output frame");
        std::print("    {:<16} packets={:<3} input_words={:<5} output_words={:<4} cycles={:<6} {}\n",
            name, expected_packets, input_words, output_words, cycle,
            error ? "FAILED" : "PASSED");
        return !error;
    }

public:
    bool run()
    {
#ifdef VERILATOR
        std::print("VERILATOR OutputMerger<{}>\n", LANE_WIDTH);
#else
        std::print("CppHDL OutputMerger<{}>\n", LANE_WIDTH);
#endif
        bind_native();
        bool ok = true;
        const std::array<size_t, 8> sizes = {
            64, 65, 79, 127, 255, 511, 1518, 9000};

        std::array<std::vector<TxTestPacket>, STREAMS> burst;
        uint32_t id = 1;
        for (size_t round = 0; round < 6; ++round) {
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                burst[stream].push_back(make_tx_packet(id++,
                    sizes[(round + stream) & 7], 0));
            }
        }
        ok &= run_case("prefilled-burst", burst, true, true, false);

        std::array<std::vector<TxTestPacket>, STREAMS> paused;
        uint32_t release_state = 0xabcdef01u + LANE_WIDTH;
        id = 0x1000;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            size_t release = stream * 3;
            for (size_t packet = 0; packet < 12; ++packet) {
                release_state = tx_prbs_step(release_state + id);
                release += 1 + (release_state % 37);
                paused[stream].push_back(make_tx_packet(id++,
                    sizes[(packet * 3 + stream) & 7], release));
            }
        }
        ok &= run_case("random-pauses", paused, false, false, true);
        return ok;
    }
};

int main(int argc, char** argv)
{
    bool noveril = false;
    std::vector<std::string> positional;
    for (int arg = 1; arg < argc; ++arg) {
        if (std::strcmp(argv[arg], "--noveril") == 0) noveril = true;
        else positional.emplace_back(argv[arg]);
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building OutputMerger Verilator simulations =========================\n";
        const std::filesystem::path generated =
            std::filesystem::current_path() / "generated_output_merger";
        const std::filesystem::path source = std::filesystem::absolute(__FILE__);
        const std::filesystem::path project_root = source.parent_path()
            .parent_path().parent_path().parent_path();
        const std::vector<std::string> includes = {
            source.parent_path().string(),
            source.parent_path().parent_path().string(),
            (project_root / "cpphdl" / "include").string(),
            project_root.string()};
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__,
            "OutputMerger_64", "OutputMerger", generated,
            {"Predef_pkg", "TxFifo"}, includes, 64, 2048, 12);
        if (ok) {
            ok &= std::system("OutputMerger_64/obj_dir/VOutputMerger 64") == 0;
        }
    }
#else
    Verilated::commandArgs(argc, argv);
#endif

    if (!positional.empty()) {
        size_t width = std::stoull(positional[0]);
        if (width == 64) return !(ok && OutputMergerTest<64>().run());
        std::print("unsupported OutputMerger lane width {}\n", width);
        return 1;
    }
    ok = ok && OutputMergerTest<64>().run();
    return ok ? 0 : 1;
}

#endif
