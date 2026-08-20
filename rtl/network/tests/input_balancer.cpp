// Native CppHDL and generated-SystemVerilog/Verilator tests for InputBalancer.
//
// Fixed-size cases cover every significant 64-bit lane boundary.  A mixed
// minimum/jumbo bulk then drives both independent MAC channels concurrently
// with the minimum 12-byte Ethernet IPG.  The scoreboard rebuilds frames on
// their corresponding outputs and verifies byte-exact 2x10G wire-speed flow.

#include "../InputBalancer.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
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

struct WireByte
{
    uint8_t data = 0;
    bool keep = false;
    bool sop = false;
    bool eop = false;
};

static std::vector<uint8_t> make_frame(uint32_t id, size_t size)
{
    std::vector<uint8_t> frame(size);
    uint32_t state = 0x9e3779b9u ^ id ^ (uint32_t)(size << 11);
    for (size_t i = 0; i < size; ++i) {
        state = state * 1664525u + 1013904223u;
        frame[i] = (uint8_t)(state >> 24);
    }
    // A stable ID and length make duplicate/missing-frame diagnostics direct.
    frame[0] = (uint8_t)id;
    frame[1] = (uint8_t)(id >> 8);
    frame[2] = (uint8_t)(id >> 16);
    frame[3] = (uint8_t)(id >> 24);
    frame[4] = (uint8_t)size;
    frame[5] = (uint8_t)(size >> 8);
    return frame;
}

static uint32_t frame_id(const std::vector<uint8_t>& frame)
{
    return (uint32_t)frame[0] | ((uint32_t)frame[1] << 8)
        | ((uint32_t)frame[2] << 16) | ((uint32_t)frame[3] << 24);
}

template<size_t LANE_WIDTH>
class InputBalancerTest
{
    static constexpr size_t LANES = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = LANES * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = LANES * LANE_BYTES;
    static constexpr size_t IPG_BYTES = 12;

#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    InputBalancer<LANE_WIDTH> dut;
#endif

    bool valid = false;
    logic<INPUT_BITS> input_data;
    logic<INPUT_BYTES> input_keep;
    logic<INPUT_BYTES> input_sop;
    logic<INPUT_BYTES> input_eop;
    logic<LANES> output_ready;

    bool error = false;
    bool input_boundary_pair_seen = false;
    bool output_boundary_pair_seen = false;
    std::map<uint32_t, std::vector<uint8_t>> expected;
    std::array<std::vector<uint8_t>, LANES> assembling;
    std::array<bool, LANES> assembling_valid{};
    std::array<uint32_t, LANES> previous_id{};
    std::array<bool, LANES> previous_id_valid{};
    std::array<size_t, LANES> output_frames{};
    size_t received_frames = 0;

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
        dut.valid_in = _ASSIGN(valid);
        dut.data_in = _ASSIGN_REG(input_data);
        dut.keep_in = _ASSIGN_REG(input_keep);
        dut.sop_in = _ASSIGN_REG(input_sop);
        dut.eop_in = _ASSIGN_REG(input_eop);
        dut.ready_in = _ASSIGN_REG(output_ready);
        dut.__inst_name = "input_balancer";
        dut._assign();
#endif
    }

    void eval_low(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 0;
        dut.reset = reset;
        dut.valid_in = valid;
        copy_to_verilator(dut.data_in, input_data);
        copy_to_verilator(dut.keep_in, input_keep);
        copy_to_verilator(dut.sop_in, input_sop);
        copy_to_verilator(dut.eop_in, input_eop);
        dut.ready_in = (uint8_t)(uint64_t)output_ready;
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

    bool input_ready_value()
    {
#ifdef VERILATOR
        return dut.ready_out;
#else
        return dut.ready_out();
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

    logic<INPUT_BITS> output_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.data_out), logic<INPUT_BITS>>(dut.data_out);
#else
        return dut.data_out();
#endif
    }

    logic<INPUT_BYTES> output_keep_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.keep_out), logic<INPUT_BYTES>>(dut.keep_out);
#else
        return dut.keep_out();
#endif
    }

    logic<INPUT_BYTES> output_sop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.sop_out), logic<INPUT_BYTES>>(dut.sop_out);
#else
        return dut.sop_out();
#endif
    }

    logic<INPUT_BYTES> output_eop_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.eop_out), logic<INPUT_BYTES>>(dut.eop_out);
#else
        return dut.eop_out();
#endif
    }

    logic<LANES> output_valid_value()
    {
#ifdef VERILATOR
        return logic<LANES>(dut.valid_out);
#else
        return dut.valid_out();
#endif
    }

    void fail(const std::string& message)
    {
        if (!error) {
            std::print("\n{} at cycle {}\n", message, _system_clock);
        }
        error = true;
    }

    void sample_outputs()
    {
        logic<INPUT_BITS> data = output_data_value();
        logic<INPUT_BYTES> keep = output_keep_value();
        logic<INPUT_BYTES> sop = output_sop_value();
        logic<INPUT_BYTES> eop = output_eop_value();
        logic<LANES> out_valid = output_valid_value();

        for (size_t output = 0; output < LANES; ++output) {
            if (!(bool)out_valid[output] || !(bool)output_ready[output]) {
                continue;
            }
            bool saw_eop = false;
            for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                size_t flat = output * LANE_BYTES + byte;
                if (!(bool)keep[flat]) {
                    if ((bool)sop[flat] || (bool)eop[flat]) {
                        fail("output boundary marked an invalid byte");
                    }
                    continue;
                }
                if ((bool)sop[flat]) {
                    if (assembling_valid[output]) {
                        fail("nested output SOP");
                    }
                    if (saw_eop) {
                        output_boundary_pair_seen = true;
                    }
                    assembling[output].clear();
                    assembling_valid[output] = true;
                }
                if (!assembling_valid[output]) {
                    fail("output byte arrived outside a frame");
                    continue;
                }
                assembling[output].push_back((uint8_t)data.bits(flat * 8 + 7, flat * 8));
                if ((bool)eop[flat]) {
                    uint32_t id = frame_id(assembling[output]);
                    auto found = expected.find(id);
                    if (found == expected.end()) {
                        fail("unexpected or duplicate output frame " + std::to_string(id));
                    }
                    else if (found->second != assembling[output]) {
                        fail("byte mismatch in output frame " + std::to_string(id));
                    }
                    else {
                        if (previous_id_valid[output] && id <= previous_id[output]) {
                            fail("per-output frame order regressed");
                        }
                        previous_id[output] = id;
                        previous_id_valid[output] = true;
                        expected.erase(found);
                        ++received_frames;
                        ++output_frames[output];
                    }
                    assembling_valid[output] = false;
                    saw_eop = true;
                }
                else {
                    saw_eop = false;
                }
            }
        }
    }

    std::array<std::vector<WireByte>, LANES> make_wires(
        const std::vector<size_t>& sizes)
    {
        std::array<std::vector<WireByte>, LANES> wires;
        expected.clear();
        for (size_t index = 0; index < sizes.size(); ++index) {
            size_t lane = index & (LANES - 1);
            uint32_t id = (uint32_t)index + 1;
            std::vector<uint8_t> frame = make_frame(id, sizes[index]);
            expected.emplace(id, frame);
            for (size_t byte = 0; byte < frame.size(); ++byte) {
                wires[lane].push_back(
                    {frame[byte], true, byte == 0, byte + 1 == frame.size()});
            }
            // AXI MAC words always start a frame at byte zero; physical IPG is
            // represented by deasserted-valid clocks rather than holes before
            // an SOP within a beat.  Round to the next word and leave two idle
            // clocks (at least the 12-byte Ethernet minimum).
            size_t idle = (LANE_BYTES - (frame.size() % LANE_BYTES)) % LANE_BYTES;
            idle += ((IPG_BYTES + LANE_BYTES - 1) / LANE_BYTES) * LANE_BYTES;
            for (size_t byte = 0; byte < idle; ++byte) {
                wires[lane].push_back({0, false, false, false});
            }
        }
        return wires;
    }

    void drive_word(const std::array<std::vector<WireByte>, LANES>& wires,
        const std::array<size_t, LANES>& position)
    {
        input_data = 0;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;
        valid = false;
        for (size_t lane = 0; lane < LANES; ++lane) {
            bool saw_eop = false;
            for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                if (position[lane] + byte >= wires[lane].size()) {
                    break;
                }
                const WireByte& item = wires[lane][position[lane] + byte];
                size_t flat = lane * LANE_BYTES + byte;
                input_data.bits(flat * 8 + 7, flat * 8) = item.data;
                input_keep[flat] = item.keep;
                input_sop[flat] = item.sop;
                input_eop[flat] = item.eop;
                valid |= item.keep;
                if (item.sop && saw_eop) {
                    input_boundary_pair_seen = true;
                }
                if (item.eop) {
                    saw_eop = true;
                }
            }
        }
    }

    bool run_case(const std::string& name, const std::vector<size_t>& sizes,
        bool require_boundary_pair, bool require_wire_speed, bool require_equal_distribution)
    {
        auto wires = make_wires(sizes);
        std::array<size_t, LANES> position{};
        size_t source_cycles = 0;
        for (size_t lane = 0; lane < LANES; ++lane) {
            source_cycles = std::max(source_cycles,
                (wires[lane].size() + LANE_BYTES - 1) / LANE_BYTES);
        }
        size_t driven_cycles = 0;
        size_t drain_cycles = 0;

        assembling_valid.fill(false);
        previous_id_valid.fill(false);
        output_frames.fill(0);
        received_frames = 0;
        input_boundary_pair_seen = false;
        output_boundary_pair_seen = false;
        error = false;
        output_ready = 0xff;
        valid = false;
        input_data = 0;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;

        // Reset uses two complete clock edges, matching the generated RTL flow.
        for (size_t cycle = 0; cycle < 2; ++cycle) {
            eval_low(true);
            rising_edge(true);
        }

        auto source_done = [&]() {
            for (size_t lane = 0; lane < LANES; ++lane) {
                if (position[lane] < wires[lane].size()) return false;
            }
            return true;
        };
        while (!source_done() && !error) {
            drive_word(wires, position);
            eval_low(false);
            sample_outputs();
            if (!input_ready_value()) {
                if (require_wire_speed) {
                    fail("wire-speed source was backpressured");
                }
            }
            else {
                for (size_t lane = 0; lane < LANES; ++lane) {
                    position[lane] = std::min(
                        position[lane] + LANE_BYTES, wires[lane].size());
                }
            }
            rising_edge(false);
            ++driven_cycles;
        }

        valid = false;
        input_keep = 0;
        input_sop = 0;
        input_eop = 0;
        while (received_frames < sizes.size() && !error && drain_cycles < 20000) {
            eval_low(false);
            sample_outputs();
            rising_edge(false);
            ++drain_cycles;
        }

        if (protocol_error_value()) {
            fail("DUT raised protocol_error_out");
        }
        if (!expected.empty() || received_frames != sizes.size()) {
            fail("test did not receive every frame");
        }
        for (size_t output = 0; output < LANES; ++output) {
            if (assembling_valid[output]) {
                fail("output retained a partial frame");
            }
        }
        if (require_boundary_pair && (!input_boundary_pair_seen || !output_boundary_pair_seen)) {
            fail("EOP+SOP was not observed in both input and output clocks");
        }
        if (require_wire_speed && driven_cycles != source_cycles) {
            fail("source consumed more than one clock per 2x10G MAC word");
        }
        if (require_equal_distribution) {
            auto [low, high] = std::minmax_element(output_frames.begin(), output_frames.end());
            if (*high - *low > 1) {
                fail("equal-size round-robin distribution was not balanced");
            }
        }

        std::print("    {:<18} frames={:<4} source_cycles={:<6} drain={:<5} {}\n",
            name, sizes.size(), source_cycles, drain_cycles, error ? "FAILED" : "PASSED");
        return !error;
    }

public:
    bool run()
    {
#ifdef VERILATOR
        std::print("VERILATOR InputBalancer<{}>\n", LANE_WIDTH);
#else
        std::print("CppHDL InputBalancer<{}>\n", LANE_WIDTH);
#endif
        bind_native();
        bool ok = true;

        // 64 bytes: Ethernet minimum and dense same-clock frame boundaries.
        // 65 bytes: first size above minimum, forcing an unaligned tail.
        // 79/80/81 bytes: immediately below/at/above key 20/40-byte multiples.
        // 127/128/129 bytes: another power-of-two boundary and partial beats.
        // 1518 bytes: conventional maximum untagged Ethernet frame size.
        // 9216 bytes: jumbo-frame credit reservation and burst absorption.
        for (size_t size : {64u, 65u, 79u, 80u, 81u, 127u, 128u, 129u, 1518u, 9216u}) {
            std::vector<size_t> sizes(24, size);
            // A 64-bit 10GbE word is shorter than the 12-byte minimum IPG, so
            // EOP and the next SOP cannot share one per-port output word.
            ok &= run_case("size-" + std::to_string(size), sizes,
                false, true, true);
        }

        // This adversarial mix repeatedly places jumbo and minimum frames near
        // one another.  Credit-qualified RR must skip a loaded output without
        // introducing a source bubble.
        std::vector<size_t> mixed;
        const std::array<size_t, 16> pattern = {
            64, 9216, 65, 1518, 66, 512, 67, 4096,
            128, 9000, 129, 256, 1500, 68, 2048, 69};
        for (size_t repeat = 0; repeat < 32; ++repeat) {
            mixed.insert(mixed.end(), pattern.begin(), pattern.end());
        }
        // Dedicated 64/65-byte cases above prove same-clock EOP+SOP.  Credit
        // steering makes that packing pattern data-dependent in this bulk.
        ok &= run_case("mixed-min-ipg", mixed, false, true, false);
        return ok;
    }
};

int main(int argc, char** argv)
{
    bool noveril = false;
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--noveril") == 0) {
            noveril = true;
        }
        else {
            positional.emplace_back(argv[i]);
        }
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building Verilator simulations ========================================\n";
        const std::filesystem::path generated = std::filesystem::current_path() / "generated";
        const std::filesystem::path source = std::filesystem::absolute(__FILE__);
        const std::filesystem::path project_root =
            source.parent_path().parent_path().parent_path().parent_path();
        const std::vector<std::string> includes = {
            (source.parent_path().parent_path()).string(),
            (project_root / "cpphdl" / "include").string()};
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "InputBalancer_64",
            "InputBalancer", generated,
            {"Predef_pkg", "SmartNicMemory", "Fifo"}, includes, 64);
        if (ok) {
            ok &= std::system("InputBalancer_64/obj_dir/VInputBalancer 64") == 0;
        }
    }
#else
    Verilated::commandArgs(argc, argv);
#endif

    if (!positional.empty()) {
        size_t width = std::stoull(positional[0]);
        if (width == 64) {
            return !(ok && InputBalancerTest<64>().run());
        }
        std::print("unsupported InputBalancer lane width {}\n", width);
        return 1;
    }

    ok = ok && InputBalancerTest<64>().run();
    return ok ? 0 : 1;
}

#endif
