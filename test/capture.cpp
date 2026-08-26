// Full-system capture test for the 2x10G profile. The single Tribe worker
// releases every descriptor and sends packet 100, 200, ... to the host. The
// test verifies those sampled packets byte-exactly; sustained mode also runs
// long enough to require circular RxRAM allocation reuse.

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
#ifndef DEMO_CAPTURE_INTERVAL
#define DEMO_CAPTURE_INTERVAL 100
#endif
#ifndef DEMO_VIDEO_DECIMATION
#define DEMO_VIDEO_DECIMATION 64
#endif
#ifndef DEMO_BASE_FRAME_COUNT
#define DEMO_BASE_FRAME_COUNT 100
#endif
#ifndef DEMO_TRAFFIC_REPEATS
#define DEMO_TRAFFIC_REPEATS 2
#endif
#ifndef DEMO_FRAME_BYTES
#define DEMO_FRAME_BYTES 0
#endif
#ifndef DEMO_IPG_BYTES
#define DEMO_IPG_BYTES 12
#endif
#ifndef DEMO_NETWORK_INTERVAL
#define DEMO_NETWORK_INTERVAL 10
#endif

// Sustained mode time-serializes each aggregate word into two clocks while
// retaining each MAC word on its original physical channel.  Moving channel 1
// onto channel 0 would interleave two independent packets on one MAC lane.
// The longer inter-packet gap exercises the complete profile for longer than
// its receive buffering at the rate supported by its single RxRAM read engine.
constexpr size_t TRAFFIC_DEPTH = SUSTAINED_CAPTURE ? 131072 : 8192;
using Dut = SmartNICTest<NET_LANE_WIDTH, CPUS_USED, TRAFFIC_DEPTH>;
using Generator = GenEthStream<NET_LANE_WIDTH>;
#if DEMO_VIDEO
using Beat = Generator::Beat;
using Visualizer = smartnic_demo::Visualizer<Dut, Beat>;
using smartnic_demo::Canvas;
#endif

constexpr uint64_t HOST_PACKET_BASE = 0x00100000;
constexpr uint32_t HOST_PACKET_STRIDE = 2048;
constexpr uint32_t CAPTURE_INTERVAL = DEMO_CAPTURE_INTERVAL;
constexpr uint32_t BASE_FRAME_COUNT = DEMO_BASE_FRAME_COUNT;
// Five 100-frame passes exceed the 64 KiB packet store many times, proving
// circular allocation reuse without overrunning the single-cluster firmware
// consumer in cycle-accurate simulation.
constexpr uint32_t TRAFFIC_REPEATS = SUSTAINED_CAPTURE
    ? 5 : DEMO_TRAFFIC_REPEATS;
constexpr uint32_t FRAME_COUNT = BASE_FRAME_COUNT * TRAFFIC_REPEATS;
constexpr uint32_t CAPTURED_FRAME_COUNT = FRAME_COUNT / CAPTURE_INTERVAL;
constexpr uint64_t MAX_CPU_TICKS = 40000000;
constexpr uint64_t PROGRESS_INTERVAL = 25000;
constexpr uint32_t FIRMWARE_BOOT_TICKS = 25000;

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
    bool host_request_valid = false;
    bool host_request_write = false;
    u32 host_address = 0;
    logic<HOST_DATA_WIDTH> host_writedata = 0;
    logic<HOST_DATA_WIDTH / 8> host_wstrb = 0;
    uint64_t net_phase = 0;
    uint64_t l2_phase = 0;
    uint64_t system_phase = 0;
    uint64_t ticks = 0;
    uint64_t net_cycles = 0;
    uint64_t wire_start_cycle = 0;
    uint64_t wire_stop_cycle = 0;
    bool wire_started = false;
    bool backpressure_reported = false;
    bool error = false;
    std::array<uint64_t, NETWORK_PORTS> lane_active_cycles{};
    std::array<uint64_t, NETWORK_PORTS> lane_payload_bytes{};
#if DEMO_VIDEO
    uint32_t video_decimation_phase = 0;
    uint32_t video_host_consumer = 0;
    std::vector<uint8_t> firmware_image;
    std::vector<Beat> traffic_beats;
    std::unique_ptr<Visualizer> visualizer;
#endif

    static constexpr uint64_t CPU_CLOCK_HZ = PROCESSING_CLK_HZ;

    uint64_t wire_elapsed_cycles() const
    {
        const uint64_t end = wire_stop_cycle != 0
            ? wire_stop_cycle : net_cycles;
        return wire_started ? end - wire_start_cycle : 0;
    }

    uint32_t l2_completed_packets()
    {
        uint32_t completed = 0;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            completed += (uint32_t)dut.processing.packet_dma[cluster]
                .cache_completed_count_out();
        }
        return completed;
    }

    void fail(const std::string& message)
    {
        std::cerr << "2x10G capture: " << message << '\n';
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
        dut.host_request_valid_in = _ASSIGN(host_request_valid);
        dut.host_request_write_in = _ASSIGN(host_request_write);
        dut.host_address_in = _ASSIGN(host_address);
        dut.host_writedata_in = _ASSIGN(host_writedata);
        dut.host_wstrb_in = _ASSIGN(host_wstrb);
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
        net_phase += NET_CLK_HZ;
        if (net_phase >= CPU_CLOCK_HZ) {
            net_phase -= CPU_CLOCK_HZ;
            edges.net = true;
            if (dut.traffic.valid_out()) {
                if (!wire_started) {
                    wire_started = true;
                    wire_start_cycle = net_cycles;
                }
                for (uint32_t lane = 0; lane < NETWORK_PORTS; ++lane) {
                    bool active = false;
                    for (uint32_t byte = 0;
                        byte < NET_LANE_WIDTH / 8; ++byte) {
                        const uint32_t flat = lane * (NET_LANE_WIDTH / 8)
                            + byte;
                        if (dut.traffic.keep_out()[flat]) {
                            active = true;
                            ++lane_payload_bytes[lane];
                        }
                    }
                    if (active) ++lane_active_cycles[lane];
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
        }
        l2_phase += L2_CLK_HZ;
        if (l2_phase >= CPU_CLOCK_HZ) {
            l2_phase -= CPU_CLOCK_HZ;
            edges.l2 = true;
        }
        system_phase += SYSTEM_CLK_HZ;
        if (system_phase >= CPU_CLOCK_HZ) {
            system_phase -= CPU_CLOCK_HZ;
            edges.system = true;
        }

#if DEMO_VIDEO
        if (visualizer) {
            visualizer->observe_cpu_before(dut);
            if (edges.net) visualizer->observe_net_before(dut);
            if (edges.l2) visualizer->observe_l2_before(dut);
            if (edges.system) visualizer->observe_system_before(dut);
        }
#endif

        // All 156.25 MHz domains share one edge. Evaluate every domain before
        // committing any registers, matching synchronous RTL semantics.
        dut._work_cpu_clk(reset);
        if (edges.net) dut._work_net_clk(reset);
        if (edges.l2) dut._work_l2_clk(reset);
        if (edges.system) dut._work_system_clk(reset);
        dut._strobe_cpu_clk();
        if (edges.net) dut._strobe_net_clk();
        if (edges.l2) dut._strobe_l2_clk();
        if (edges.system) dut._strobe_system_clk();

        if (edges.net) {
            if (wire_started && dut.traffic.done_out()
                && wire_stop_cycle == 0) {
                wire_stop_cycle = net_cycles + 1;
            }
            ++net_cycles;
#if DEMO_VIDEO
            if (visualizer) {
                if (video_decimation_phase == 0) {
                    visualizer->frame(dut, ticks, video_host_consumer,
                        edges.l2, edges.system);
                }
                video_decimation_phase = (video_decimation_phase + 1)
                    % DEMO_VIDEO_DECIMATION;
            }
#endif
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
        host_wstrb = 0;
        host_writedata.bits(lane * 8 + 31, lane * 8) = value;
        host_wstrb.bits(lane + 3, lane) = 0xf;
        host_request_write = true;
        while (!dut.host_request_ready_out()) wait_system_edge();
        host_request_valid = true;
        wait_system_edge();
        host_request_valid = false;
        for (uint32_t timeout = 0; timeout < 1000; ++timeout) {
            wait_system_edge();
            if (dut.host_response_valid_out()) break;
            if (timeout == 999) fail("AXI4 host register write timed out");
        }
        host_request_write = false;
        host_writedata = 0;
        host_wstrb = 0;
    }

    uint32_t read32(uint32_t address)
    {
        const uint32_t lane = address & (HOST_DATA_WIDTH / 8 - 1);
        host_address = address;
        host_request_write = false;
        while (!dut.host_request_ready_out()) wait_system_edge();
        host_request_valid = true;
        wait_system_edge();
        host_request_valid = false;
        for (uint32_t timeout = 0; timeout < 1000; ++timeout) {
            wait_system_edge();
            if (dut.host_response_valid_out()) {
                return (uint32_t)dut.host_readdata_out().bits(
                    lane * 8 + 31, lane * 8);
            }
        }
        fail("AXI4 host register read timed out");
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
        static constexpr std::array<uint16_t, 32> patterns = {
            0x000f, 0x00f0, 0x0f00, 0x00ff, 0x0f0f, 0x0ff0, 0x0fff, 0x000c,
            0x00c0, 0x0c00, 0x00cc, 0x0c0c, 0x0cc0, 0x0ccc, 0x009f, 0x00f9,
            0x090f, 0x0f09, 0x09f0, 0x0f90, 0x1099, 0x1909, 0x1990, 0x1066,
            0x1606, 0x1660, 0x2066, 0x2606, 0x2660, 0x2048, 0x2480, 0x2804};
#endif
        std::vector<std::vector<uint8_t>> frames;
        for (uint32_t frame_index = 0;
            frame_index < BASE_FRAME_COUNT; ++frame_index) {
            const uint32_t size = DEMO_FRAME_BYTES != 0 ? DEMO_FRAME_BYTES
                : (SUSTAINED_CAPTURE ? 1516
                    : functional_sizes[frame_index % functional_sizes.size()]);
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
            const uint32_t port = frame_index & 1u;
            const uint32_t station = (frame_index / 2u) % 10u;
            const uint32_t destination_port = (frame_index & 2u)
                ? (port ^ 1u) : port;
            const uint8_t header[14] = {
                0x02, 0x20, 0, (uint8_t)destination_port, 0x40,
                    (uint8_t)(0x10 + (station + 1) % 10),
                0x02, 0x20, 0, (uint8_t)port, 0x40,
                    (uint8_t)(0x10 + station),
                0x08, 0x00};
            std::copy(std::begin(header), std::end(header), frame.begin());
            // Keep every packet in the loaded base image bytewise unique.
            frame[14] = (uint8_t)frame_index;
            frame[15] = (uint8_t)(frame_index >> 8);
            frame[16] = (uint8_t)(frame_index >> 16);
            frame[17] = (uint8_t)(frame_index >> 24);
            frames.push_back(std::move(frame));
        }
        return frames;
    }

    static std::vector<std::vector<uint8_t>> sampled_frames(
        const std::vector<std::vector<uint8_t>>& frames)
    {
        std::vector<std::vector<uint8_t>> sampled;
        for (uint32_t frame = CAPTURE_INTERVAL - 1;
            frame < frames.size(); frame += CAPTURE_INTERVAL) {
            sampled.push_back(frames[frame]);
        }
        return sampled;
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

    bool load_traffic(const std::vector<std::vector<uint8_t>>& frames)
    {
        Generator generator;
#if DEMO_VIDEO
        traffic_beats.clear();
#endif
        generator.clear();
        for (const auto& frame : frames) {
            generator.push(frame,
                SUSTAINED_CAPTURE ? 8192 : DEMO_IPG_BYTES);
        }
        generator.finalize();
        const size_t load_words = generator.size()
            * (SUSTAINED_CAPTURE ? 2 : 1);
        if (load_words > TRAFFIC_DEPTH) {
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
            const uint32_t words = SUSTAINED_CAPTURE ? 2 : 1;
            for (uint32_t word = 0; word < words; ++word) {
                traffic_load_data = 0;
                traffic_load_keep = 0;
                traffic_load_sop = 0;
                traffic_load_eop = 0;
                if (SUSTAINED_CAPTURE) {
                    traffic_load_data.bits((word + 1) * NET_LANE_WIDTH - 1,
                        word * NET_LANE_WIDTH) =
                        beat.data.bits((word + 1) * NET_LANE_WIDTH - 1,
                            word * NET_LANE_WIDTH);
                    traffic_load_keep.bits(
                        (word + 1) * (NET_LANE_WIDTH / 8) - 1,
                        word * (NET_LANE_WIDTH / 8)) =
                        beat.keep.bits((word + 1) * (NET_LANE_WIDTH / 8) - 1,
                            word * (NET_LANE_WIDTH / 8));
                    traffic_load_sop.bits(
                        (word + 1) * (NET_LANE_WIDTH / 8) - 1,
                        word * (NET_LANE_WIDTH / 8)) =
                        beat.sop.bits((word + 1) * (NET_LANE_WIDTH / 8) - 1,
                            word * (NET_LANE_WIDTH / 8));
                    traffic_load_eop.bits(
                        (word + 1) * (NET_LANE_WIDTH / 8) - 1,
                        word * (NET_LANE_WIDTH / 8)) =
                        beat.eop.bits((word + 1) * (NET_LANE_WIDTH / 8) - 1,
                            word * (NET_LANE_WIDTH / 8));
                }
                else {
                    traffic_load_data = beat.data;
                    traffic_load_keep = beat.keep;
                    traffic_load_sop = beat.sop;
                    traffic_load_eop = beat.eop;
                }
                traffic_load_valid = true;
                wait_net_edge();
                traffic_load_valid = false;
            }
            generator.pop();
        }
        traffic_load_data = 0;
        traffic_load_keep = 0;
        traffic_load_sop = 0;
        traffic_load_eop = 0;
        return true;
    }

    bool verify_packets(const std::vector<std::vector<uint8_t>>& injected,
        uint32_t captured_count)
    {
        std::vector<bool> captured(injected.size(), false);
        for (uint32_t slot = 0; slot < captured_count; ++slot) {
            const uint64_t base = HOST_PACKET_BASE + slot * HOST_PACKET_STRIDE;
            uint32_t match = injected.size();
            for (uint32_t frame = 0; frame < injected.size(); ++frame) {
                if (captured[frame]) continue;
                bool equal = true;
                for (uint32_t byte = 0; byte < injected[frame].size(); ++byte) {
                    if (dut.host_byte(base + byte) != injected[frame][byte]) {
                        equal = false;
                        break;
                    }
                }
                if (equal) {
                    match = frame;
                    break;
                }
            }
            if (match == injected.size()) {
                fail(std::format(
                    "sampled host slot {} is not a unique injected packet", slot));
                return false;
            }
            captured[match] = true;
        }
        return true;
    }

    void report_progress(uint32_t host_consumer)
    {
        std::cerr << "2x10G capture progress: ticks=" << ticks
                  << " host=" << host_consumer << '/' << CAPTURED_FRAME_COUNT;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            std::cerr << " c" << cluster
                      << "{descriptors="
                      << (uint32_t)dut.processing.descriptor_fetcher[cluster]
                          .descriptor_count_out()
                      << ",dma="
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .completed_count_out()
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
                  << ":" << dut.system.controller_protocol_error()
                  << ":" << dut.system.dma_protocol_error()
                  << "(" << dut.system.dma_protocol_error_code() << ")"
                  << " dma_cmd{valid="
                  << dut.system.dma_command_valid()
                  << ",addr="
                  << dut.system.dma_command_address()
                  << ",len="
                  << dut.system.dma_command_length()
                  << ",dir="
                  << dut.system.dma_command_direction() << '}'
                  << ":" << dut.system.rx_protocol_error(0)
                  << ":" << dut.system.tx_protocol_error(0)
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
                .packet_dma[cluster].completed_count_out();
        }
        const uint64_t elapsed_cycles = wire_elapsed_cycles();
        const double elapsed_seconds = (double)elapsed_cycles / NET_CLK_HZ;
        const double offered_gbps = elapsed_seconds == 0 ? 0
            : (double)(uint32_t)dut.traffic_emitted_beats_out()
                * Dut::NET_BYTES * 8.0 / elapsed_seconds / 1e9;
        const double packet_dma_gbps = elapsed_seconds == 0 ? 0
            : (double)(dma_operations / 2) * 1516.0 * 8.0
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
        const auto expected = sampled_frames(frames);
        for (uint32_t slot = 0; slot < expected.size(); ++slot) {
            write_ring_descriptor(slot,
                HOST_PACKET_BASE + slot * HOST_PACKET_STRIDE,
                HOST_PACKET_STRIDE, 0);
        }
        write32(Controller<>::REG_RX_PRODUCER, expected.size());
        write32(Controller<>::REG_CONTROL, Controller<>::CONTROL_ENABLE);
        if (!load_traffic(base_frames)) return false;
#if DEMO_VIDEO
        visualizer = std::make_unique<Visualizer>(output, frames,
            traffic_beats, firmware_image, TRAFFIC_REPEATS, 120, background);
#endif

        // The 2x10G profile has one processing cluster. Let its firmware
        // finish initialization before releasing a non-stallable sustained
        // burst, so the test measures steady-state datapath throughput rather
        // than boot latency against finite receive buffering.
        for (uint32_t tick = 0; tick < FIRMWARE_BOOT_TICKS; ++tick) cycle();

        traffic_start = true;
        wait_net_edge();
        traffic_start = false;

        uint32_t consumer = 0;
        uint64_t next_poll = ticks;
        uint64_t next_progress = ticks + PROGRESS_INTERVAL;
        report_progress(consumer);
        while (ticks < MAX_CPU_TICKS
            && (consumer != expected.size()
#if DEMO_VIDEO
                || l2_completed_packets() != FRAME_COUNT)
#else
                )
#endif
            && !error) {
            cycle();
            if (ticks >= next_poll) {
                consumer = read32(Controller<>::REG_RX_CONSUMER);
#if DEMO_VIDEO
                video_host_consumer = consumer;
#endif
                next_poll = ticks + (DEMO_VIDEO ? 512 : 20000);
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
                fail("RxRAM/RxFIFO storage_full asserted");
            }
        }
        consumer = read32(Controller<>::REG_RX_CONSUMER);
#if DEMO_VIDEO
        video_host_consumer = consumer;
        // Record one final settled frame after the last host completion.
        visualizer->frame(dut, ticks, video_host_consumer, true, true);
        if (!visualizer->mac_tx_ok()
            || visualizer->mac_tx_packet_count()
                != FRAME_COUNT / DEMO_NETWORK_INTERVAL) {
            fail(std::format("MAC TX verification failed: {} of {} packets",
                visualizer->mac_tx_packet_count(),
                FRAME_COUNT / DEMO_NETWORK_INTERVAL));
        }
        if (visualizer->rx_fifo_frame_count() == 0
            || visualizer->tx_fifo_frame_count() == 0) {
            fail(std::format("video FIFO activity missing: RX frames={}, "
                "TX frames={}", visualizer->rx_fifo_frame_count(),
                visualizer->tx_fifo_frame_count()));
        }
#endif
        if (backpressure_reported) report_backpressure_state(consumer);
        if (consumer != expected.size()) {
            fail(std::format("capture timed out: {} of {} packets reached host",
                consumer, expected.size()));
        }
#if DEMO_VIDEO
        if (l2_completed_packets() != FRAME_COUNT) {
            fail(std::format("processing throughput failure: {} of {} packets "
                "reached coherent L2", l2_completed_packets(), FRAME_COUNT));
        }
#endif
        if (!dut.traffic_done_out()) fail("traffic source did not drain");
        if ((uint32_t)dut.traffic_backpressure_cycles_out() != 0) {
            fail(std::format("wire-speed violation: {} network cycles backpressured",
                (uint32_t)dut.traffic_backpressure_cycles_out()));
        }
#if DEMO_VIDEO
        const uint64_t elapsed = wire_elapsed_cycles();
        for (uint32_t lane = 0; lane < NETWORK_PORTS; ++lane) {
            const double load = elapsed == 0 ? 0.0
                : 100.0 * lane_active_cycles[lane] / elapsed;
            if (load < 79.0 || load > 81.0) {
                fail(std::format(
                    "channel {} load {:.2f}% is outside the 80% target",
                    lane, load));
            }
        }
#endif
        if (!error) verify_packets(frames, expected.size());
#if DEMO_VIDEO
        visualizer->finish();
#endif

        std::print("2x10G capture: injected={} sampled={} beats={} net_cycles={} CPU ticks={} "
            "l2_packets={} backpressure={} result={}"
#if DEMO_VIDEO
            " lane_load={:.2f}%/{:.2f}% video_frames={} video={}"
#endif
            "\n",
            frames.size(), expected.size(),
            (uint32_t)dut.traffic_emitted_beats_out(),
            wire_elapsed_cycles(), ticks,
            l2_completed_packets(),
            (uint32_t)dut.traffic_backpressure_cycles_out(),
            error ? "FAILED" : "PASSED"
#if DEMO_VIDEO
            , 100.0 * lane_active_cycles[0] / wire_elapsed_cycles()
            , 100.0 * lane_active_cycles[1] / wire_elapsed_cycles()
            , visualizer->frame_count(), output.string()
#endif
            );
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
            ? argv[2] : "smartnic_2x10g_capture.avi";
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
