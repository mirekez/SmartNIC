// Native CppHDL and generated-SystemVerilog/Verilator tests for RxRAM.
// The traffic includes every one of the 256 simultaneous eight-stream
// EOP+SOP masks, followed by PRBS packets at protocol boundary sizes and jumbo.

#include "../RxRAM.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <iostream>
#include <optional>
#include <print>
#include <string>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

struct RxWireByte
{
    uint8_t data = 0;
    bool keep = false;
    bool sop = false;
    bool eop = false;
};

struct ExpectedFrame
{
    uint32_t id = 0;
    std::vector<uint8_t> bytes;
};

struct StoredFrame
{
    uint32_t handle = 0;
    uint32_t length = 0;
    uint32_t stream = 0;
    ExpectedFrame expected;
};

static uint32_t prbs_step(uint32_t state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static ExpectedFrame make_prbs_frame(uint32_t id, size_t size)
{
    ExpectedFrame frame;
    frame.id = id;
    frame.bytes.resize(size);
    uint32_t state = 0x9e3779b9u ^ id ^ (uint32_t)(size * 0x45d9f3bu);
    for (size_t i = 0; i < size; ++i) {
        state = prbs_step(state + (uint32_t)i + 1);
        frame.bytes[i] = (uint8_t)(state >> 24);
    }
    frame.bytes[0] = (uint8_t)id;
    frame.bytes[1] = (uint8_t)(id >> 8);
    frame.bytes[2] = (uint8_t)(id >> 16);
    frame.bytes[3] = (uint8_t)(id >> 24);
    return frame;
}

template<size_t LANE_WIDTH, size_t READ_PORTS = 4, size_t BANK_DEPTH = 4096>
class RxRAMTest
{
    static constexpr size_t STREAMS = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t LOGICAL_ROWS = BANK_DEPTH * 2;
    static constexpr size_t LOGICAL_ROW_BITS = clog2(LOGICAL_ROWS);
    static constexpr size_t HANDLE_BITS = LOGICAL_ROW_BITS + 3;
    static constexpr size_t FRAME_LENGTH_BITS = 14;

#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    RxRAM<LANE_WIDTH, READ_PORTS, BANK_DEPTH> dut;
#endif

    logic<STREAMS> valid;
    logic<INPUT_BITS> data;
    logic<INPUT_BYTES> keep;
    logic<INPUT_BYTES> sop;
    logic<INPUT_BYTES> eop;
    logic<STREAMS> packet_ready;
    logic<READ_PORTS> read_request_valid;
    logic<READ_PORTS * HANDLE_BITS> read_request_handle;
    logic<READ_PORTS * LOGICAL_ROW_BITS> read_request_word;
    logic<READ_PORTS> read_response_ready;

    std::array<std::vector<RxWireByte>, STREAMS> wire;
    std::array<size_t, STREAMS> position{};
    std::array<std::deque<ExpectedFrame>, STREAMS> completion_expected;
    std::vector<StoredFrame> stored;
    std::array<bool, 256> boundary_masks_seen{};
    size_t expected_packets = 0;
    bool error = false;

    struct ReadState
    {
        std::optional<StoredFrame> frame;
        uint32_t next_word = 0;
        bool waiting = false;
    };
    std::array<ReadState, READ_PORTS> readers;
    std::deque<StoredFrame> read_jobs;

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
        dut.valid_in = _ASSIGN_REG(valid);
        dut.data_in = _ASSIGN_REG(data);
        dut.keep_in = _ASSIGN_REG(keep);
        dut.sop_in = _ASSIGN_REG(sop);
        dut.eop_in = _ASSIGN_REG(eop);
        dut.packet_ready_in = _ASSIGN_REG(packet_ready);
        dut.read_valid_in = _ASSIGN_REG(read_request_valid);
        dut.read_handle_in = _ASSIGN_REG(read_request_handle);
        dut.read_word_in = _ASSIGN_REG(read_request_word);
        dut.read_ready_in = _ASSIGN_REG(read_response_ready);
        dut.__inst_name = "rx_ram";
        dut._assign();
#endif
    }

    void eval_low(bool reset)
    {
#ifdef VERILATOR
        dut.clk = 0;
        dut.reset = reset;
        dut.valid_in = (uint8_t)(uint64_t)valid;
        copy_to_verilator(dut.data_in, data);
        copy_to_verilator(dut.keep_in, keep);
        copy_to_verilator(dut.sop_in, sop);
        copy_to_verilator(dut.eop_in, eop);
        dut.packet_ready_in = (uint8_t)(uint64_t)packet_ready;
        dut.read_valid_in = (uint8_t)(uint64_t)read_request_valid;
        copy_to_verilator(dut.read_handle_in, read_request_handle);
        copy_to_verilator(dut.read_word_in, read_request_word);
        dut.read_ready_in = (uint8_t)(uint64_t)read_response_ready;
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
        return logic<STREAMS>(dut.ready_out);
#else
        return dut.ready_out();
#endif
    }

    logic<STREAMS> packet_valid_value()
    {
#ifdef VERILATOR
        return logic<STREAMS>(dut.packet_valid_out);
#else
        return dut.packet_valid_out();
#endif
    }

    logic<STREAMS * HANDLE_BITS> packet_handle_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.packet_handle_out),
            logic<STREAMS * HANDLE_BITS>>(dut.packet_handle_out);
#else
        return dut.packet_handle_out();
#endif
    }

    logic<STREAMS * FRAME_LENGTH_BITS> packet_length_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.packet_length_out),
            logic<STREAMS * FRAME_LENGTH_BITS>>(dut.packet_length_out);
#else
        return dut.packet_length_out();
#endif
    }

    logic<READ_PORTS> read_request_ready_value()
    {
#ifdef VERILATOR
        return logic<READ_PORTS>(dut.read_ready_out);
#else
        return dut.read_ready_out();
#endif
    }

    logic<READ_PORTS> read_response_valid_value()
    {
#ifdef VERILATOR
        return logic<READ_PORTS>(dut.read_valid_out);
#else
        return dut.read_valid_out();
#endif
    }

    logic<READ_PORTS * LANE_WIDTH> read_data_value()
    {
#ifdef VERILATOR
        return copy_from_verilator<decltype(dut.read_data_out),
            logic<READ_PORTS * LANE_WIDTH>>(dut.read_data_out);
#else
        return dut.read_data_out();
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

    bool storage_full_value()
    {
#ifdef VERILATOR
        return dut.storage_full_out;
#else
        return dut.storage_full_out();
#endif
    }

    void fail(const std::string& message)
    {
        if (!error) {
            std::print("\n{} at cycle {}\n", message, _system_clock);
        }
        error = true;
    }

    void place_frame(size_t stream, size_t start, const ExpectedFrame& frame)
    {
        if (wire[stream].size() < start + frame.bytes.size()) {
            wire[stream].resize(start + frame.bytes.size());
        }
        for (size_t i = 0; i < frame.bytes.size(); ++i) {
            RxWireByte& item = wire[stream][start + i];
            if (item.keep) {
                fail("test traffic frames overlap");
            }
            item = {frame.bytes[i], true, i == 0,
                i + 1 == frame.bytes.size()};
        }
        completion_expected[stream].push_back(frame);
        ++expected_packets;
    }

    void build_traffic()
    {
        uint32_t id = 1;
        const size_t segment_bytes = 10 * LANE_BYTES;
        for (uint32_t mask = 0; mask < 256; ++mask) {
            size_t base = mask * segment_bytes;
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if (wire[stream].size() < base + segment_bytes) {
                    wire[stream].resize(base + segment_bytes);
                }
                size_t start = base + 1 + ((stream * 3 + mask) % 7);
                size_t target_eop = base + 4 * LANE_BYTES
                    + ((stream * 5 + mask) % (LANE_BYTES / 2));
                bool boundary = ((mask >> stream) & 1) != 0;
                if (boundary) {
                    ExpectedFrame first = make_prbs_frame(id++, target_eop - start + 1);
                    place_frame(stream, start, first);
                    size_t gap = (stream + mask) % 3;
                    size_t second_start = target_eop + 1 + gap;
                    size_t second_size = 64 + ((mask * 7 + stream * 11)
                        % (2 * LANE_BYTES + 1));
                    ExpectedFrame second = make_prbs_frame(id++, second_size);
                    place_frame(stream, second_start, second);
                }
                else {
                    size_t end = base + 5 * LANE_BYTES
                        + ((mask + stream * 7) % LANE_BYTES);
                    ExpectedFrame frame = make_prbs_frame(id++, end - start + 1);
                    place_frame(stream, start, frame);
                }
            }
        }

        const std::array<size_t, 14> sizes = {
            64, 65, 79, 80, 81, 127, 128, 129,
            255, 256, 511, 1518, 4096, 9216};
        size_t bulk_base = 256 * segment_bytes;
        size_t maximum_end = bulk_base;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            size_t cursor = bulk_base + ((stream * 13 + 5) % LANE_BYTES);
            for (size_t item = 0; item < sizes.size(); ++item) {
                size_t size = sizes[(item + stream * 3) % sizes.size()];
                ExpectedFrame frame = make_prbs_frame(id++, size);
                place_frame(stream, cursor, frame);
                cursor += size + ((item * 11 + stream * 7) % 24);
            }
            maximum_end = std::max(maximum_end, cursor);
        }
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            wire[stream].resize(maximum_end + LANE_BYTES);
        }
    }

    void drive_write_inputs()
    {
        valid = 0;
        data = 0;
        keep = 0;
        sop = 0;
        eop = 0;
        uint32_t boundary_mask = 0;
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            bool saw_eop = false;
            bool saw_pair = false;
            for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                if (position[stream] + byte >= wire[stream].size()) {
                    break;
                }
                const RxWireByte& item = wire[stream][position[stream] + byte];
                size_t flat = stream * LANE_BYTES + byte;
                data.bits(flat * 8 + 7, flat * 8) = item.data;
                keep[flat] = item.keep;
                sop[flat] = item.sop;
                eop[flat] = item.eop;
                valid[stream] = (bool)valid[stream] || item.keep;
                if (item.sop && saw_eop) saw_pair = true;
                if (item.eop) saw_eop = true;
            }
            if (saw_pair) boundary_mask |= 1u << stream;
        }
        if (boundary_mask != 0) {
            boundary_masks_seen[boundary_mask] = true;
        }
    }

    void sample_completions()
    {
        logic<STREAMS> out_valid = packet_valid_value();
        logic<STREAMS * HANDLE_BITS> handles = packet_handle_value();
        logic<STREAMS * FRAME_LENGTH_BITS> lengths = packet_length_value();
        for (size_t stream = 0; stream < STREAMS; ++stream) {
            if (!(bool)out_valid[stream] || !(bool)packet_ready[stream]) {
                continue;
            }
            if (completion_expected[stream].empty()) {
                fail("unexpected packet completion on stream "
                    + std::to_string(stream));
                continue;
            }
            ExpectedFrame frame = completion_expected[stream].front();
            completion_expected[stream].pop_front();
            uint32_t handle = (uint32_t)handles.bits(
                stream * HANDLE_BITS + HANDLE_BITS - 1,
                stream * HANDLE_BITS);
            uint32_t length = (uint32_t)lengths.bits(
                stream * FRAME_LENGTH_BITS + FRAME_LENGTH_BITS - 1,
                stream * FRAME_LENGTH_BITS);
            if ((handle & 7) != stream || ((handle >> 3) & 1) != 0) {
                fail("packet handle alignment/home-bank mismatch");
            }
            if (length != frame.bytes.size()) {
                fail("packet length mismatch for PRBS frame "
                    + std::to_string(frame.id));
            }
            stored.push_back({handle, length, (uint32_t)stream, frame});
        }
    }

    void prepare_read_inputs()
    {
        read_request_valid = 0;
        read_request_handle = 0;
        read_request_word = 0;
        for (size_t port = 0; port < READ_PORTS; ++port) {
            if (!readers[port].frame && !read_jobs.empty()) {
                readers[port].frame = read_jobs.front();
                read_jobs.pop_front();
                readers[port].next_word = 0;
                readers[port].waiting = false;
            }
            if (readers[port].frame && !readers[port].waiting) {
                read_request_valid[port] = 1;
                uint32_t handle = readers[port].frame->handle;
                for (size_t bit = 0; bit < HANDLE_BITS; ++bit) {
                    read_request_handle[port * HANDLE_BITS + bit] =
                        (handle >> bit) & 1;
                }
                for (size_t bit = 0; bit < LOGICAL_ROW_BITS; ++bit) {
                    read_request_word[port * LOGICAL_ROW_BITS + bit] =
                        (readers[port].next_word >> bit) & 1;
                }
            }
        }
    }

    void sample_read_responses()
    {
        logic<READ_PORTS> response_valid = read_response_valid_value();
        logic<READ_PORTS * LANE_WIDTH> response_data = read_data_value();
        for (size_t port = 0; port < READ_PORTS; ++port) {
            if (!(bool)response_valid[port]
                || !(bool)read_response_ready[port]) {
                continue;
            }
            if (!readers[port].frame || !readers[port].waiting) {
                fail("orphan read response on port " + std::to_string(port));
                continue;
            }
            const StoredFrame& frame = *readers[port].frame;
            logic<LANE_WIDTH> got = response_data.bits(
                port * LANE_WIDTH + LANE_WIDTH - 1,
                port * LANE_WIDTH);
            logic<LANE_WIDTH> reference = 0;
            size_t start = readers[port].next_word * LANE_BYTES;
            for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                if (start + byte < frame.expected.bytes.size()) {
                    reference.bits(byte * 8 + 7, byte * 8) =
                        frame.expected.bytes[start + byte];
                }
            }
            if (got != reference) {
                fail("PRBS data mismatch for frame "
                    + std::to_string(frame.expected.id) + " word "
                    + std::to_string(readers[port].next_word));
                std::print("    stream={} handle=0x{:x} got:",
                    frame.stream, frame.handle);
                for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                    std::print(" {:02x}", (uint32_t)got.bits(
                        byte * 8 + 7, byte * 8));
                }
                std::print("\n    expected:");
                for (size_t byte = 0; byte < LANE_BYTES; ++byte) {
                    std::print(" {:02x}", (uint32_t)reference.bits(
                        byte * 8 + 7, byte * 8));
                }
                std::print("\n");
            }
            readers[port].waiting = false;
            ++readers[port].next_word;
            size_t words = (frame.length + LANE_BYTES - 1) / LANE_BYTES;
            if (readers[port].next_word == words) {
                readers[port].frame.reset();
            }
        }
    }

public:
    bool run()
    {
#ifdef VERILATOR
        std::print("VERILATOR RxRAM<{}, {}, {}>\n",
            LANE_WIDTH, READ_PORTS, BANK_DEPTH);
#else
        std::print("CppHDL RxRAM<{}, {}, {}>\n",
            LANE_WIDTH, READ_PORTS, BANK_DEPTH);
#endif
        bind_native();
        build_traffic();
        packet_ready = 0xff;
        read_response_ready = ~logic<READ_PORTS>(0);
        read_request_valid = 0;
        read_request_handle = 0;
        read_request_word = 0;
        for (size_t cycle = 0; cycle < 2; ++cycle) {
            eval_low(true);
            rising_edge(true);
        }

        size_t write_cycles = 0;
        size_t completed = 0;
        while (!error && completed < expected_packets && write_cycles < 100000) {
            drive_write_inputs();
            eval_low(false);
            size_t before = stored.size();
            sample_completions();
            completed += stored.size() - before;
            logic<STREAMS> ready = input_ready_value();
            for (size_t stream = 0; stream < STREAMS; ++stream) {
                if ((bool)ready[stream] && position[stream] < wire[stream].size()) {
                    position[stream] += LANE_BYTES;
                }
            }
            rising_edge(false);
            ++write_cycles;
        }
        if (completed != expected_packets) {
            fail("write phase did not complete every frame");
        }
        if (protocol_error_value()) fail("DUT raised protocol_error_out");
        if (storage_full_value()) fail("DUT exhausted configured storage");
        for (size_t mask = 1; mask < boundary_masks_seen.size(); ++mask) {
            if (!boundary_masks_seen[mask]) {
                fail("missing simultaneous EOP+SOP mask "
                    + std::to_string(mask));
            }
        }

        // Group jobs by home stream.  Adjacent logical read ports therefore
        // frequently contend for the same two physical sub-banks.
        std::stable_sort(stored.begin(), stored.end(),
            [](const StoredFrame& a, const StoredFrame& b) {
                return a.stream < b.stream;
            });
        for (const StoredFrame& frame : stored) read_jobs.push_back(frame);

        valid = 0;
        keep = 0;
        sop = 0;
        eop = 0;
        size_t read_cycles = 0;
        while (!error && read_cycles < 200000) {
            prepare_read_inputs();
            eval_low(false);
            sample_read_responses();
            logic<READ_PORTS> request_ready = read_request_ready_value();
            for (size_t port = 0; port < READ_PORTS; ++port) {
                if ((bool)read_request_valid[port]
                    && (bool)request_ready[port]) {
                    readers[port].waiting = true;
                }
            }
            rising_edge(false);
            ++read_cycles;

            bool active = !read_jobs.empty();
            for (const ReadState& reader : readers) {
                active |= reader.frame.has_value() || reader.waiting;
            }
            if (!active && (uint64_t)read_response_valid_value() == 0) {
                break;
            }
        }
        if (!read_jobs.empty()) fail("read job queue did not drain");
        for (size_t port = 0; port < READ_PORTS; ++port) {
            if (readers[port].frame || readers[port].waiting) {
                fail("read port did not finish its packet");
            }
        }
        std::print("    packets={} write_cycles={} read_cycles={} {}\n",
            stored.size(), write_cycles, read_cycles,
            error ? "FAILED" : "PASSED");
        return !error;
    }
};

int main(int argc, char** argv)
{
    bool noveril = false;
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--noveril") == 0) noveril = true;
        else positional.emplace_back(argv[i]);
    }

    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        std::cout << "Building RxRAM Verilator simulations ================================\n";
        const std::filesystem::path generated =
            std::filesystem::current_path() / "generated_rx_ram";
        const std::filesystem::path source = std::filesystem::absolute(__FILE__);
        const std::filesystem::path project_root =
            source.parent_path().parent_path().parent_path().parent_path();
        const std::vector<std::string> includes = {
            (source.parent_path().parent_path()).string(),
            (project_root / "cpphdl" / "include").string(),
            (project_root / "cpphdl" / "tribe_cpu" / "common").string(),
            project_root.string()};
        const std::vector<std::string> modules = {"Predef_pkg", "SmartNicRAM"};
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "RxRAM_160",
            "RxRAM", generated, modules, includes, 160, 4, 4096);
        ok &= VerilatorCompileInExactFolderFromGenerated(__FILE__, "RxRAM_320",
            "RxRAM", generated, modules, includes, 320, 4, 4096);
        if (ok) {
            ok &= std::system("RxRAM_160/obj_dir/VRxRAM 160") == 0;
            ok &= std::system("RxRAM_320/obj_dir/VRxRAM 320") == 0;
        }
    }
#else
    Verilated::commandArgs(argc, argv);
#endif
    if (!positional.empty()) {
        size_t width = std::stoull(positional[0]);
        if (width == 160) return !(ok && RxRAMTest<160>().run());
        if (width == 320) return !(ok && RxRAMTest<320>().run());
        std::print("unsupported RxRAM lane width {}\n", width);
        return 1;
    }
    ok = ok && RxRAMTest<160>().run();
    ok = ok && RxRAMTest<320>().run();
#ifndef VERILATOR
    // Exercise both ends of the configurable N<8 read-port range in native
    // simulation; the four-port configurations above also run as RTL.
    ok = ok && RxRAMTest<160, 1>().run();
    ok = ok && RxRAMTest<160, 7>().run();
#endif
    return ok ? 0 : 1;
}

#endif
