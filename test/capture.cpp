// Full-system capture test. A finite but uninterrupted minimum-IPG burst is
// injected at 400G or 800G. Capture firmware running on the Tribe clusters
// Functional mode loads every packet through PacketDMA into its cluster-private
// L2 and DDR circular buffer. Sustained mode uses discard/direct-host commands
// to isolate 400G network throughput. Both verify sampled host packets; the
// functional test also checks the final contents of all eight DDR rings.

#include "SmartNICTest.h"
#include "../rtl/testing/GenEthStream.h"
#include "../rtl/system/Controller.h"
#if DEMO_VIDEO
#include "../demo/Visualizer.h"
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <print>
#include <string>
#include <vector>

namespace
{

#ifndef SUSTAINED_CAPTURE
#define SUSTAINED_CAPTURE 0
#endif
#ifndef DEMO_VIDEO
#define DEMO_VIDEO 0
#endif
#ifndef DEMO_VIDEO_DECIMATION
#define DEMO_VIDEO_DECIMATION 32
#endif

constexpr size_t TRAFFIC_DEPTH = 1024;
constexpr size_t TEST_RX_RAM_DEPTH = RX_RAM_BANK_DEPTH;
using Dut = SmartNICTest<NET_LANE_WIDTH, CPUS_USED, TRAFFIC_DEPTH, 4096,
    4 * 1024 * 1024, TEST_RX_RAM_DEPTH>;
using Generator = GenEthStream<NET_LANE_WIDTH>;
#if DEMO_VIDEO
using Beat = Generator::Beat;
using Visualizer = smartnic_demo::Visualizer<Dut, Beat>;
using smartnic_demo::Canvas;
#endif

constexpr uint64_t HOST_PACKET_BASE = 0x00100000;
constexpr uint32_t HOST_PACKET_STRIDE = 2048;
// Sustained mode replays an exactly aggregate-word-aligned image. Functional
// mode retains the original compact mixed-size coverage.
constexpr uint32_t BASE_FRAME_COUNT = SUSTAINED_CAPTURE ? 40 : 32;
// The 400G throughput run carries more than all receive-side buffering. It
// therefore cannot pass by absorbing a finite burst and
// draining it later; RxRAM must recycle consumed packet allocations while the
// non-stallable wire source is still active.
constexpr uint32_t TRAFFIC_REPEATS = SUSTAINED_CAPTURE
    ? (ENABLE_800G ? 24 : 64) : 20;
constexpr uint32_t FRAME_COUNT = BASE_FRAME_COUNT * TRAFFIC_REPEATS;
constexpr uint32_t HOST_SAMPLE_PERIOD = 10;
constexpr uint32_t PACKET_RING_BASE = 0x00010000;
constexpr uint32_t PACKET_RING_STRIDE = 2048;
constexpr uint32_t PACKET_RING_SLOT_MASK = 511;
constexpr uint32_t PACKET_RING_SLOTS = PACKET_RING_SLOT_MASK + 1;
static_assert(FRAME_COUNT % CPUS_USED == 0);
constexpr uint32_t FRAMES_PER_CPU = FRAME_COUNT / CPUS_USED;
constexpr uint32_t HOST_FRAMES_PER_CPU =
    (FRAMES_PER_CPU + HOST_SAMPLE_PERIOD - 1) / HOST_SAMPLE_PERIOD;
constexpr uint32_t HOST_FRAME_COUNT = HOST_FRAMES_PER_CPU * CPUS_USED;
constexpr uint64_t MAX_CPU_TICKS = ENABLE_800G ? 30000000 : 15000000;
constexpr uint64_t PROGRESS_INTERVAL = 10000;
constexpr uint64_t BALANCER_BYTES = 8ull * 1024 * (NET_LANE_WIDTH / 8);
constexpr uint64_t RX_RAM_BYTES = 8ull * TEST_RX_RAM_DEPTH * 2
    * (NET_LANE_WIDTH / 8);
constexpr uint64_t RX_DESCRIPTOR_BYTES = 8ull * 64 * 160 + 16ull * 160;
constexpr uint64_t SYSTEM_RX_QUEUE_BYTES = 8ull * 256 * 32;
constexpr uint64_t TOTAL_RX_BUFFER_BYTES = BALANCER_BYTES + RX_RAM_BYTES
    + RX_DESCRIPTOR_BYTES + SYSTEM_RX_QUEUE_BYTES;
constexpr uint64_t ABSORPTION_NET_CYCLES =
    (TOTAL_RX_BUFFER_BYTES + Dut::NET_BYTES - 1) / Dut::NET_BYTES;
constexpr uint32_t MAX_RETIREMENT_LAG_PACKETS = 128;

struct Elf32Header
{
    unsigned char ident[16];
    uint16_t type;
    uint16_t machine;
    uint32_t version;
    uint32_t entry;
    uint32_t phoff;
    uint32_t shoff;
    uint32_t flags;
    uint16_t ehsize;
    uint16_t phentsize;
    uint16_t phnum;
    uint16_t shentsize;
    uint16_t shnum;
    uint16_t shstrndx;
};

struct Elf32ProgramHeader
{
    uint32_t type;
    uint32_t offset;
    uint32_t vaddr;
    uint32_t paddr;
    uint32_t filesz;
    uint32_t memsz;
    uint32_t flags;
    uint32_t align;
};

class CaptureTest
{
    Dut dut;
    bool traffic_load_valid = false;
    logic<Dut::NET_BITS> traffic_load_data = 0;
    logic<Dut::NET_BYTES> traffic_load_keep = 0;
    logic<Dut::NET_BYTES> traffic_load_sop = 0;
    logic<Dut::NET_BYTES> traffic_load_eop = 0;
    bool traffic_start = false;
    bool traffic_clear = false;
    u<16> traffic_repeat_count = TRAFFIC_REPEATS;
    bool host_read = false;
    bool host_write = false;
    u32 host_address = 0;
    logic<HOST_DATA_WIDTH> host_writedata = 0;
    logic<HOST_DATA_WIDTH / 8> host_byteenable = 0;
    uint64_t net_phase = 0;
    uint64_t l2_phase = 0;
    uint64_t system_phase = 0;
    uint64_t ticks = 0;
    uint64_t net_cycles = 0;
    uint64_t wire_start_cycle = 0;
    uint64_t wire_stop_cycle = 0;
    bool wire_started = false;
    bool wire_midpoint_seen = false;
    uint32_t wire_midpoint_completed = 0;
    uint32_t wire_end_completed = 0;
    uint32_t traffic_image_beats = 0;
    bool backpressure_reported = false;
    bool error = false;
#if DEMO_VIDEO
    uint32_t video_decimation_phase = 0;
    uint32_t video_host_consumer = 0;
    std::vector<uint8_t> firmware_image;
    std::vector<Beat> traffic_beats;
    std::unique_ptr<Visualizer> visualizer;
#endif

    static constexpr uint64_t CPU_CLOCK_HZ = L2_CLK_HZ * 4;

    uint64_t wire_elapsed_cycles() const
    {
        const uint64_t end = wire_stop_cycle != 0
            ? wire_stop_cycle : net_cycles;
        return wire_started ? end - wire_start_cycle : 0;
    }

    uint32_t completed_packets()
    {
        uint32_t completed = 0;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            if constexpr (SUSTAINED_CAPTURE) {
                completed += (uint32_t)dut.processing.packet_dma[cluster]
                    .completed_count_out();
            }
            else {
                completed += (uint32_t)dut.processing.packet_dma[cluster]
                    .cache_completed_count_out();
            }
        }
        return completed;
    }

    void fail(const std::string& message)
    {
        std::cerr << (ENABLE_800G ? "800G" : "400G")
                  << " capture: " << message << '\n';
        error = true;
    }

    void bind()
    {
        dut.traffic_load_valid_in = _ASSIGN(traffic_load_valid);
        dut.traffic_load_data_in = _ASSIGN(traffic_load_data);
        dut.traffic_load_keep_in = _ASSIGN(traffic_load_keep);
        dut.traffic_load_sop_in = _ASSIGN(traffic_load_sop);
        dut.traffic_load_eop_in = _ASSIGN(traffic_load_eop);
        dut.traffic_start_in = _ASSIGN(traffic_start);
        dut.traffic_clear_in = _ASSIGN(traffic_clear);
        dut.traffic_repeat_count_in = _ASSIGN(traffic_repeat_count);
        dut.host_read_in = _ASSIGN(host_read);
        dut.host_write_in = _ASSIGN(host_write);
        dut.host_address_in = _ASSIGN(host_address);
        dut.host_writedata_in = _ASSIGN(host_writedata);
        dut.host_byteenable_in = _ASSIGN(host_byteenable);
        dut.__inst_name = "capture";
        dut._assign();
    }

    struct Edges
    {
        bool net = false;
        bool l2 = false;
        bool system = false;
    };

    Edges cycle(bool reset = false)
    {
        Edges edges;
#if DEMO_VIDEO
        if (visualizer) visualizer->observe_cpu_before(dut);
#endif
        dut._work_cpu_clk(reset);
        dut._strobe_cpu_clk();

        net_phase += NET_CLK_HZ;
        if (net_phase >= CPU_CLOCK_HZ) {
            net_phase -= CPU_CLOCK_HZ;
            const bool video_wire_active = dut.traffic.valid_out();
            if (dut.traffic.valid_out()) {
                if (!wire_started) {
                    wire_started = true;
                    wire_start_cycle = net_cycles;
                }
                if (!dut.smartnic.net_rx_ready_out()
                    && !backpressure_reported) {
                    backpressure_reported = true;
                    fail(std::format(
                        "wire-speed assertion: ingress backpressured at "
                        "network cycle {}, emitted beat {}",
                        net_cycles - wire_start_cycle,
                        (uint32_t)dut.traffic_emitted_beats_out()));
                }
            }
#if DEMO_VIDEO
            if (visualizer) visualizer->observe_net_before(dut);
#endif
            dut._work_net_clk(reset);
            dut._strobe_net_clk();
            if (wire_started && !wire_midpoint_seen
                && traffic_image_beats != 0
                && (uint32_t)dut.traffic_emitted_beats_out()
                    >= (traffic_image_beats * TRAFFIC_REPEATS) / 2) {
                wire_midpoint_seen = true;
                wire_midpoint_completed = completed_packets();
            }
            if (wire_started && dut.traffic.done_out()
                && wire_stop_cycle == 0) {
                wire_stop_cycle = net_cycles + 1;
                wire_end_completed = completed_packets();
            }
            ++net_cycles;
            edges.net = true;
#if DEMO_VIDEO
            if (visualizer) {
                // Every AVI frame is one active network cycle. Continue the
                // functional simulation after ingress ends, but do not append
                // idle drain frames that make a continuous burst look sparse.
                if (video_wire_active) {
                    visualizer->frame(dut, ticks, video_host_consumer,
                        true, false);
                }
            }
#endif
        }
        l2_phase += L2_CLK_HZ;
        if (l2_phase >= CPU_CLOCK_HZ) {
            l2_phase -= CPU_CLOCK_HZ;
#if DEMO_VIDEO
            if (visualizer) visualizer->observe_l2_before(dut);
#endif
            dut._work_l2_clk(reset);
            dut._strobe_l2_clk();
            edges.l2 = true;
        }
        system_phase += SYSTEM_CLK_HZ;
        if (system_phase >= CPU_CLOCK_HZ) {
            system_phase -= CPU_CLOCK_HZ;
#if DEMO_VIDEO
            if (visualizer) visualizer->observe_system_before(dut);
#endif
            dut._work_system_clk(reset);
            dut._strobe_system_clk();
            edges.system = true;
        }
        ++ticks;
        ++_system_clock;
        return edges;
    }

    void wait_net_edge(bool reset = false)
    {
        while (!cycle(reset).net) {}
    }

    void wait_system_edge(bool reset = false)
    {
        while (!cycle(reset).system) {}
    }

    bool load_elf(const std::filesystem::path& path)
    {
        std::ifstream input(path, std::ios::binary);
        if (!input) {
            fail("cannot open firmware " + path.string());
            return false;
        }
        const std::vector<uint8_t> image{
            std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
        if (image.size() < sizeof(Elf32Header)) {
            fail("capture.elf is truncated");
            return false;
        }
        Elf32Header header{};
        std::memcpy(&header, image.data(), sizeof(header));
        if (std::memcmp(header.ident, "\x7f" "ELF", 4) != 0
            || header.ident[4] != 1 || header.ident[5] != 1
            || header.machine != 243) {
            fail("capture.elf is not little-endian RV32 ELF");
            return false;
        }
        if ((uint64_t)header.phoff
            + (uint64_t)header.phnum * header.phentsize > image.size()
            || header.phentsize < sizeof(Elf32ProgramHeader)) {
            fail("capture.elf program header table is invalid");
            return false;
        }
        uint32_t loaded = 0;
        for (uint32_t index = 0; index < header.phnum; ++index) {
            Elf32ProgramHeader segment{};
            std::memcpy(&segment, image.data() + header.phoff
                + index * header.phentsize, sizeof(segment));
            if (segment.type != 1) continue;
            if ((uint64_t)segment.offset + segment.filesz > image.size()) {
                fail("capture.elf load segment is invalid");
                return false;
            }
            const uint32_t address = segment.paddr ? segment.paddr : segment.vaddr;
#if DEMO_VIDEO
            if (firmware_image.size() < (size_t)address + segment.memsz) {
                firmware_image.resize((size_t)address + segment.memsz, 0);
            }
#endif
            for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
                for (uint32_t byte = 0; byte < segment.memsz; ++byte) {
                    const uint8_t value = byte < segment.filesz
                        ? image[segment.offset + byte] : 0;
                    dut.load_cpu_byte(cluster, address + byte, value);
#if DEMO_VIDEO
                    firmware_image[address + byte] = value;
#endif
                }
            }
            loaded += segment.memsz;
        }
        if (loaded == 0 || header.entry != 0) {
            fail("capture.elf has no loadable reset image at address zero");
            return false;
        }
        return true;
    }

    void write32(uint32_t address, uint32_t value)
    {
        const uint32_t lane = address & (HOST_DATA_WIDTH / 8 - 1);
        host_address = address;
        host_writedata = 0;
        host_byteenable = 0;
        host_writedata.bits(lane * 8 + 31, lane * 8) = value;
        host_byteenable.bits(lane + 3, lane) = 0xf;
        host_write = true;
        do {
            wait_system_edge();
        } while (dut.host_waitrequest_out());
        host_write = false;
        host_writedata = 0;
        host_byteenable = 0;
    }

    uint32_t read32(uint32_t address)
    {
        const uint32_t lane = address & (HOST_DATA_WIDTH / 8 - 1);
        host_address = address;
        host_read = true;
        do {
            wait_system_edge();
        } while (dut.host_waitrequest_out());
        host_read = false;
        if (dut.host_readdatavalid_out()) {
            return (uint32_t)dut.host_readdata_out().bits(
                lane * 8 + 31, lane * 8);
        }
        for (uint32_t timeout = 0; timeout < 1000; ++timeout) {
            cycle();
            if (dut.host_readdatavalid_out()) {
                return (uint32_t)dut.host_readdata_out().bits(
                    lane * 8 + 31, lane * 8);
            }
        }
        fail("Avalon host register read timed out");
        return 0;
    }

    void write_ring_descriptor(uint32_t index, uint64_t address,
        uint32_t length, uint32_t queue)
    {
        const uint32_t base = Controller<>::REG_RX_RING_BASE
            + index * Controller<>::RING_ENTRY_BYTES;
        write32(base, (uint32_t)address);
        write32(base + 4, (uint32_t)(address >> 32));
        write32(base + 8, length | (queue << 16));
        write32(base + 12, 0);
    }

    std::vector<std::vector<uint8_t>> make_frames()
    {
        static constexpr std::array<uint32_t, 8> functional_sizes = {
            64, 128, 256, 512, 1024, 1516, 768, 300};
#if DEMO_VIDEO
        static constexpr std::array<uint16_t, 16> patterns = {
            0x000f, 0x00f0, 0x0f00, 0x00ff,
            0x0f0f, 0x0ff0, 0x0fff, 0x00cc,
            0x0c0c, 0x0cc0, 0x1099, 0x1909,
            0x1990, 0x2066, 0x2606, 0x2660};
#endif
        std::vector<std::vector<uint8_t>> frames;
        for (uint32_t frame_index = 0;
            frame_index < BASE_FRAME_COUNT; ++frame_index) {
            const uint32_t size = SUSTAINED_CAPTURE ? 1516
                : functional_sizes[frame_index % functional_sizes.size()];
            std::vector<uint8_t> frame(size);
#if DEMO_VIDEO
            const uint16_t pattern = patterns[frame_index % patterns.size()];
            for (uint32_t byte = 0; byte < frame.size(); byte += 2) {
                frame[byte] = (uint8_t)pattern;
                if (byte + 1 < frame.size()) frame[byte + 1] = pattern >> 8;
            }
#else
            for (uint32_t byte = 0; byte < frame.size(); ++byte) {
                frame[byte] = (uint8_t)(frame_index * 29 + byte * 17 + 3);
            }
#endif
            const uint8_t header[14] = {
                0x02, 0, 0, 0, 0, (uint8_t)frame_index,
                0x02, 1, 2, 3, 4, (uint8_t)(0x80 + frame_index),
                0x08, 0x00};
            std::copy(std::begin(header), std::end(header), frame.begin());
            // Keep every packet bytewise unique after the one-byte MAC fields
            // wrap, so long-run loss/duplication checking remains unambiguous.
            frame[14] = (uint8_t)frame_index;
            frame[15] = (uint8_t)(frame_index >> 8);
            frame[16] = (uint8_t)(frame_index >> 16);
            frame[17] = (uint8_t)(frame_index >> 24);
            frames.push_back(std::move(frame));
        }
        return frames;
    }

    static std::vector<std::vector<uint8_t>> repeated_frames(
        const std::vector<std::vector<uint8_t>>& base)
    {
        std::vector<std::vector<uint8_t>> frames;
        frames.reserve(FRAME_COUNT);
        for (uint32_t repeat = 0; repeat < TRAFFIC_REPEATS; ++repeat) {
            frames.insert(frames.end(), base.begin(), base.end());
        }
        return frames;
    }

    static std::vector<std::vector<uint8_t>> sampled_host_frames(
        const std::vector<std::vector<uint8_t>>& frames)
    {
        std::vector<std::vector<uint8_t>> sampled;
        sampled.reserve(HOST_FRAME_COUNT);
        // Processing distributes descriptors round-robin.  Each cluster's
        // firmware forwards local packet 0, 10, 20, ...; the host ring uses
        // the same queue order for deterministic byte-exact checking.
        for (uint32_t local = 0; local < FRAMES_PER_CPU;
            local += HOST_SAMPLE_PERIOD) {
            for (uint32_t queue = 0; queue < CPUS_USED; ++queue) {
                sampled.push_back(frames[local * CPUS_USED + queue]);
            }
        }
        return sampled;
    }

    bool load_traffic(const std::vector<std::vector<uint8_t>>& frames)
    {
        Generator generator;
#if DEMO_VIDEO
        traffic_beats.clear();
#endif
        generator.clear();
        for (const auto& frame : frames) generator.push(frame, 12);
        generator.finalize();
        traffic_image_beats = generator.size();
        if (generator.size() > TRAFFIC_DEPTH) {
            fail("traffic image exceeds harness generator depth");
            return false;
        }
        while (!generator.empty()) {
            if (!dut.traffic_load_ready_out()) {
                fail("traffic generator refused a setup beat");
                return false;
            }
            const auto& beat = generator.front();
#if DEMO_VIDEO
            traffic_beats.push_back(beat);
#endif
            traffic_load_data = beat.data;
            traffic_load_keep = beat.keep;
            traffic_load_sop = beat.sop;
            traffic_load_eop = beat.eop;
            traffic_load_valid = true;
            wait_net_edge();
            traffic_load_valid = false;
            generator.pop();
        }
        traffic_load_data = 0;
        traffic_load_keep = 0;
        traffic_load_sop = 0;
        traffic_load_eop = 0;
        return true;
    }

    bool verify_packets(const std::vector<std::vector<uint8_t>>& frames,
        uint32_t slots)
    {
        std::vector<bool> captured(frames.size(), false);
        for (uint32_t slot = 0; slot < slots; ++slot) {
            const uint64_t base = HOST_PACKET_BASE + slot * HOST_PACKET_STRIDE;
            uint32_t match = frames.size();
            for (uint32_t frame = 0; frame < frames.size(); ++frame) {
                if (captured[frame]) continue;
                bool equal = true;
                for (uint32_t byte = 0; byte < frames[frame].size(); ++byte) {
                    if (dut.host_byte(base + byte) != frames[frame][byte]) {
                        equal = false;
                        break;
                    }
                }
                if (equal) {
                    match = frame;
                    break;
                }
            }
            if (match == frames.size()) {
                std::cerr << "host slot " << slot << " prefix:";
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    std::cerr << std::format(" {:02x}",
                        dut.host_byte(base + byte));
                }
                std::cerr << "\nexpected prefix:";
                for (uint32_t byte = 0; byte < 32; ++byte)
                    std::cerr << std::format(" {:02x}", frames[0][byte]);
                std::cerr << '\n';
                fail(std::format(
                    "host slot {} is corrupt, duplicated, or not an injected packet",
                    slot));
                return false;
            }
            captured[match] = true;
        }
        return true;
    }

    bool verify_ddr_rings(const std::vector<std::vector<uint8_t>>& frames)
    {
        std::array<uint32_t, BASE_FRAME_COUNT> expected_count{};
        std::array<uint32_t, BASE_FRAME_COUNT> seen_count{};
        for (const auto& frame : frames) {
            const uint32_t packet_id = (uint32_t)frame[14]
                | ((uint32_t)frame[15] << 8)
                | ((uint32_t)frame[16] << 16)
                | ((uint32_t)frame[17] << 24);
            if (packet_id >= BASE_FRAME_COUNT) {
                fail("generated packet ID is outside the compact image");
                return false;
            }
            ++expected_count[packet_id];
        }
        const uint32_t packets_per_cluster = frames.size() / CPUS_USED;
        const uint32_t occupied_slots = std::min<uint32_t>(
            packets_per_cluster, PACKET_RING_SLOTS);

        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            for (uint32_t slot = 0; slot < occupied_slots; ++slot) {
                const uint32_t address = PACKET_RING_BASE
                    + slot * PACKET_RING_STRIDE;
                const uint32_t packet_id =
                    (uint32_t)dut.cpu_memory_byte(cluster, address + 14)
                    | ((uint32_t)dut.cpu_memory_byte(cluster, address + 15) << 8)
                    | ((uint32_t)dut.cpu_memory_byte(cluster, address + 16) << 16)
                    | ((uint32_t)dut.cpu_memory_byte(cluster, address + 17) << 24);
                uint32_t frame = BASE_FRAME_COUNT;
                for (uint32_t candidate = 0;
                    candidate < BASE_FRAME_COUNT; ++candidate) {
                    if ((uint32_t)frames[candidate][14]
                            == (packet_id & 0xffu)
                        && (uint32_t)frames[candidate][15]
                            == ((packet_id >> 8) & 0xffu)
                        && (uint32_t)frames[candidate][16]
                            == ((packet_id >> 16) & 0xffu)
                        && (uint32_t)frames[candidate][17]
                            == ((packet_id >> 24) & 0xffu)) {
                        frame = candidate;
                        break;
                    }
                }
                if (frame == BASE_FRAME_COUNT) {
                    fail(std::format(
                        "CPU {} DDR ring slot {} contains unknown packet id {}",
                        cluster, slot, packet_id));
                    return false;
                }
                ++seen_count[frame];
                for (uint32_t byte = 0; byte < frames[frame].size(); ++byte) {
                    const uint8_t actual = dut.cpu_memory_byte(
                        cluster, address + byte);
                    if (actual != frames[frame][byte]) {
                        fail(std::format(
                            "CPU {} DDR ring slot {} differs from packet {} "
                            "at byte {}: got {:02x}, expected {:02x}",
                            cluster, slot, frame, byte, actual,
                            frames[frame][byte]));
                        return false;
                    }
                }
            }
            // The programmed mask must wrap before the following slot. This
            // byte is outside both firmware and the 64-slot packet region.
            const uint32_t guard = PACKET_RING_BASE
                + PACKET_RING_SLOTS * PACKET_RING_STRIDE;
            if (dut.cpu_memory_byte(cluster, guard) != 0) {
                fail(std::format(
                    "CPU {} DDR packet ring wrote beyond its slot mask",
                    cluster));
                return false;
            }
        }
        if (!SUSTAINED_CAPTURE) {
            for (uint32_t packet = 0; packet < BASE_FRAME_COUNT; ++packet) {
                if (seen_count[packet] != expected_count[packet]) {
                    fail(std::format(
                        "packet ID {} occurs {} times in DDR rings, expected {}",
                        packet, seen_count[packet], expected_count[packet]));
                    return false;
                }
            }
        }
        return true;
    }

    void report_progress(uint32_t host_consumer)
    {
        std::cerr << (ENABLE_800G ? "800G" : "400G")
                  << " capture progress: ticks=" << ticks
                  << " host=" << host_consumer << '/' << HOST_FRAME_COUNT;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            std::cerr << " c" << cluster
                      << "{descriptors="
                      << (uint32_t)dut.processing.descriptor_fetcher[cluster]
                          .descriptor_count_out()
                      << ",loaded="
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .cache_completed_count_out()
                      << ",commands="
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .command_completed_count_out()
                      << ",ddr_pending="
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .backing_pending_count_out()
                      << ",busy="
                      << dut.processing.packet_dma[cluster].busy_out()
                      << '}';
        }
        std::cerr << '\n';
    }

    void report_protocol_errors()
    {
        std::cerr << "protocol sources: smartnic="
                  << dut.smartnic.protocol_error_out()
                  << " network{balancer="
                  << dut.smartnic.debug_network_balancer_error()
                  << ",parser="
                  << dut.smartnic.debug_network_parser_error()
                  << ",rxram="
                  << dut.smartnic.debug_network_rx_ram_error()
                  << ",join="
                  << dut.smartnic.debug_network_join_error() << '}'
                  << " system=" << dut.system.protocol_error_out()
                  << " traffic=" << dut.traffic.protocol_error_out()
                  << " host=" << dut.host.protocol_error_out();
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            std::cerr << " fetch" << cluster << '='
                      << dut.processing.descriptor_fetcher[cluster]
                          .protocol_error_out()
                      << " dma" << cluster << '='
                      << dut.processing.packet_dma[cluster]
                          .protocol_error_out()
                      << ':'
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .protocol_error_reason_out();
        }
        std::cerr << '\n';
    }

    void report_backpressure_state(uint32_t host_consumer)
    {
        uint32_t dma_operations = 0;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            dma_operations += (uint32_t)dut.processing
                .packet_dma[cluster].cache_completed_count_out();
        }
        const uint64_t elapsed_cycles = wire_elapsed_cycles();
        const double elapsed_seconds = (double)elapsed_cycles / NET_CLK_HZ;
        const double offered_gbps = elapsed_seconds == 0 ? 0
            : (double)(uint32_t)dut.traffic_emitted_beats_out()
                * Dut::NET_BYTES * 8.0 / elapsed_seconds / 1e9;
        const double packet_dma_gbps = elapsed_seconds == 0 ? 0
            : (double)dma_operations * 1516.0 * 8.0
                / elapsed_seconds / 1e9;
        const double host_gbps = elapsed_seconds == 0 ? 0
            : (double)host_consumer * 1516.0 * 8.0
                / elapsed_seconds / 1e9;
        std::cerr << "ingress stall state: balancer_words="
                  << dut.smartnic.debug_network_balancer_words()
                  << " balancer_max_stream="
                  << dut.smartnic.debug_network_balancer_max_words()
                  << "/1024 rx_fifo_descriptors="
                  << dut.smartnic.debug_network_rx_fifo_descriptors()
                  << "/512 rx_ram_completions="
                  << dut.smartnic.debug_network_rx_ram_completions()
                  << "/32";
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            std::cerr << " cpu" << cluster << "{descriptors="
                      << (uint32_t)dut.processing
                          .descriptor_fetcher[cluster].descriptor_count_out()
                      << ",dma=" << (uint32_t)dut.processing
                          .packet_dma[cluster].completed_count_out() << '}';
        }
        std::cerr << std::format(
            " offered={:.1f}Gb/s packet_dma={:.1f}Gb/s host={:.1f}Gb/s\n",
            offered_gbps, packet_dma_gbps, host_gbps);
    }

public:
#if DEMO_VIDEO
    bool run(const std::filesystem::path& firmware,
        const std::filesystem::path& output, uint8_t background)
#else
    bool run(const std::filesystem::path& firmware)
#endif
    {
        bind();
        if (!load_elf(firmware)) return false;

        // Reset every clock domain, then configure host receive buffers before
        // releasing the first uninterrupted Ethernet burst.
        for (uint32_t cycle_index = 0; cycle_index < 512; ++cycle_index) {
            cycle(true);
        }
        const auto base_frames = make_frames();
        const auto frames = repeated_frames(base_frames);
        const auto host_frames = sampled_host_frames(frames);
        for (uint32_t frame = 0; frame < host_frames.size(); ++frame) {
            write_ring_descriptor(frame,
                HOST_PACKET_BASE + frame * HOST_PACKET_STRIDE,
                HOST_PACKET_STRIDE, frame % CPUS_USED);
        }
        write32(Controller<>::REG_RX_PRODUCER, host_frames.size());
        write32(Controller<>::REG_CONTROL, Controller<>::CONTROL_ENABLE);
        if (!load_traffic(base_frames)) return false;

        // Boot latency is not receive-pipeline throughput. Hold the compact
        // generator image until every cluster has enabled its DescriptorFetcher,
        // then release one uninterrupted 20-pass burst with no warm-up gaps.
        bool workers_ready = false;
        for (uint32_t timeout = 0; timeout < 100000; ++timeout) {
            workers_ready = true;
            for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
                workers_ready &= dut.processing.descriptor_fetcher[cluster]
                    .prefetch_enabled_out();
            }
            if (workers_ready) break;
            cycle();
        }
        if (!workers_ready) {
            fail("capture firmware workers did not become ready");
            return false;
        }
#if DEMO_VIDEO
        visualizer = std::make_unique<Visualizer>(output, frames,
            traffic_beats, firmware_image, TRAFFIC_REPEATS, 60, background);
#endif

        traffic_start = true;
        wait_net_edge();
        traffic_start = false;

        uint32_t consumer = 0;
        uint64_t next_poll = ticks;
        uint64_t next_progress = ticks + PROGRESS_INTERVAL;
        report_progress(consumer);
        while (ticks < MAX_CPU_TICKS
            && (consumer != host_frames.size()
                || completed_packets() != frames.size())
            && !error) {
            cycle();
            if (ticks >= next_poll) {
                consumer = read32(Controller<>::REG_RX_CONSUMER);
#if DEMO_VIDEO
                video_host_consumer = consumer;
#endif
                next_poll = ticks + 20000;
            }
            if (ticks >= next_progress) {
                report_progress(consumer);
                next_progress = ticks + PROGRESS_INTERVAL;
            }
            if (dut.protocol_error_out()) {
                report_protocol_errors();
                fail("RTL protocol_error asserted");
            }
            if (dut.storage_full_out()) {
                report_progress(consumer);
                report_backpressure_state(consumer);
                fail("RxRAM/RxFIFO storage_full asserted");
            }
        }
        consumer = read32(Controller<>::REG_RX_CONSUMER);
#if DEMO_VIDEO
        video_host_consumer = consumer;
#endif
        if (backpressure_reported) report_backpressure_state(consumer);
        if (consumer != host_frames.size()) {
            fail(std::format("capture timed out: {} of {} packets reached host",
                consumer, host_frames.size()));
        }
        if (completed_packets() != frames.size()) {
            fail(std::format("processing drained {} of {} ingress packets",
                completed_packets(), frames.size()));
        }
        if (!dut.traffic_done_out()) fail("traffic source did not drain");
        if ((uint32_t)dut.traffic_backpressure_cycles_out() != 0) {
            fail(std::format("wire-speed violation: {} network cycles backpressured",
                (uint32_t)dut.traffic_backpressure_cycles_out()));
        }
        if (!SUSTAINED_CAPTURE && TRAFFIC_REPEATS > 1) {
            if (!wire_midpoint_seen) {
                fail("functional burst midpoint was not observed");
            }
            const uint32_t second_half_retired = wire_end_completed
                - wire_midpoint_completed;
            // A long capture must make measurable forward progress while the
            // latter half of the wire burst is still arriving. This prevents
            // the test from passing by buffering the complete input and only
            // processing it after the generator stops.
            if (second_half_retired < FRAME_COUNT / 8) {
                fail(std::format(
                    "processing did not keep working during the long burst: "
                    "only {} packets retired during its second half",
                    second_half_retired));
            }
            std::print(
                "long-burst progress: midpoint_retired={} wire_end_retired={} "
                "second_half_retired={}\n",
                wire_midpoint_completed, wire_end_completed,
                second_half_retired);
        }
        if (SUSTAINED_CAPTURE && !ENABLE_800G) {
            if (wire_elapsed_cycles() <= ABSORPTION_NET_CYCLES) {
                fail(std::format(
                    "throughput interval {} cycles did not exceed the complete "
                    "receive-buffer absorption interval of {} cycles",
                    wire_elapsed_cycles(), ABSORPTION_NET_CYCLES));
            }
            if (!wire_midpoint_seen) {
                fail("throughput midpoint was not observed while ingress ran");
            }
            const uint32_t second_half_retired = wire_end_completed
                - wire_midpoint_completed;
            if (second_half_retired + MAX_RETIREMENT_LAG_PACKETS
                < FRAME_COUNT / 2) {
                fail(std::format(
                    "processing fell behind during sustained ingress: retired "
                    "{} of {} second-half packets before wire end",
                    second_half_retired, FRAME_COUNT / 2));
            }
            std::print(
                "400G sustained proof: wire_bytes={} modeled_rx_buffer_bytes={} "
                "wire_cycles={} absorption_cycles={} midpoint_retired={} "
                "wire_end_retired={}\n",
                (uint64_t)(uint32_t)dut.traffic_emitted_beats_out()
                    * Dut::NET_BYTES,
                TOTAL_RX_BUFFER_BYTES, wire_elapsed_cycles(),
                ABSORPTION_NET_CYCLES, wire_midpoint_completed,
                wire_end_completed);
        }
        // Fetchers become enabled by independently booting CPUs, so their
        // initial descriptor-to-cluster phase is intentionally unspecified.
        // Verify the sampled output against the complete injected population.
        if (!error) verify_packets(frames, host_frames.size());
        if (!error && !SUSTAINED_CAPTURE) verify_ddr_rings(frames);
#if DEMO_VIDEO
        visualizer->finish();
#endif

        std::print("{} capture: ingress_packets={} host_packets={} beats={} "
            "net_cycles={} CPU ticks={} backpressure={} result={}\n",
            ENABLE_800G ? "800G" : "400G", frames.size(), host_frames.size(),
            (uint32_t)dut.traffic_emitted_beats_out(),
            wire_elapsed_cycles(), ticks,
            (uint32_t)dut.traffic_backpressure_cycles_out(),
            error ? "FAILED" : "PASSED");
        return !error;
    }
};

} // namespace

int main(int argc, char** argv)
{
    const std::filesystem::path firmware = argc > 1 ? argv[1] : "capture.elf";
#if DEMO_VIDEO
    try {
        const std::filesystem::path output = argc > 2
            ? argv[2] : "smartnic_capture_8cpu_32core.avi";
        uint8_t background = Canvas::UI_OUTSIDE;
        if (argc > 3) {
            std::string color = argv[3];
            if (!color.empty() && color.front() == '#') color.erase(0, 1);
            size_t consumed = 0;
            const unsigned long rgb = std::stoul(color, &consumed, 16);
            if (color.size() != 6 || consumed != color.size()
                || rgb > 0xfffffful) {
                throw std::runtime_error(
                    "background must be a six-digit #RRGGBB color");
            }
            background = Canvas::rgb332((uint8_t)(rgb >> 16),
                (uint8_t)(rgb >> 8), (uint8_t)rgb);
        }
        return CaptureTest().run(firmware, output, background) ? 0 : 1;
    }
    catch (const std::exception& exception) {
        std::cerr << "capture video exception: " << exception.what() << '\n';
        return 1;
    }
#else
    return CaptureTest().run(firmware) ? 0 : 1;
#endif
}
