// Full-SoC learning-switch regression. Real Tribe firmware learns ten MACs on
// each ingress, fetches packets coherently into L2, forces dirty-line DDR4
// writeback, and forwards known destinations through the selected TX port.

#include "SmartNICTest.h"
#include "../rtl/testing/GenEthStream.h"
#ifndef DEMO_VIDEO
#define DEMO_VIDEO 0
#endif
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
#include <vector>

namespace
{

#ifndef SUSTAINED_SWITCH
#define SUSTAINED_SWITCH 0
#endif
#ifndef CPU_LOOPBACK_TEST
#define CPU_LOOPBACK_TEST 0
#endif
#ifndef DEMO_TRAFFIC_REPEATS
#define DEMO_TRAFFIC_REPEATS 10
#endif
#ifndef DEMO_VIDEO_DECIMATION
#define DEMO_VIDEO_DECIMATION 48
#endif

constexpr size_t TRAFFIC_DEPTH = SUSTAINED_SWITCH ? 16384 : 4096;
using Dut = SmartNICTest<NET_LANE_WIDTH, CPUS_USED, TRAFFIC_DEPTH>;
using Generator = GenEthStream<NET_LANE_WIDTH>;
#if DEMO_VIDEO
using Beat = Generator::Beat;
using Visualizer = smartnic_demo::Visualizer<Dut, Beat>;
using smartnic_demo::Canvas;
#endif

struct Elf32Header
{
    unsigned char ident[16];
    uint16_t type, machine;
    uint32_t version, entry, phoff, shoff, flags;
    uint16_t ehsize, phentsize, phnum, shentsize, shnum, shstrndx;
};

struct Elf32ProgramHeader
{
    uint32_t type, offset, vaddr, paddr, filesz, memsz, flags, align;
};

struct Expected
{
    std::vector<uint8_t> packet;
    uint32_t port = 0;
};

static std::string header_hex(const std::vector<uint8_t>& packet)
{
    std::string result;
    const size_t bytes = std::min<size_t>(14, packet.size());
    for (size_t byte = 0; byte < bytes; ++byte) {
        if (byte != 0) result += ':';
        result += std::format("{:02x}", packet[byte]);
    }
    return result;
}

class L2SwitchTest
{
    Dut dut;
    bool load_valid = false;
    logic<Dut::NET_BITS> load_data = 0;
    logic<Dut::NET_BYTES> load_keep = 0;
    logic<Dut::NET_BYTES> load_sop = 0;
    logic<Dut::NET_BYTES> load_eop = 0;
    bool start = false;
    bool clear = false;
    u<16> repeats = SUSTAINED_SWITCH ? DEMO_TRAFFIC_REPEATS : 1;
    bool host_valid = false;
    bool host_write = false;
    u32 host_address = 0;
    logic<HOST_DATA_WIDTH> host_data = 0;
    logic<HOST_DATA_WIDTH / 8> host_strobe = 0;
    uint64_t net_phase = 0;
    uint64_t l2_phase = 0;
    uint64_t system_phase = 0;
    uint64_t ticks = 0;
    uint64_t measured_net_cycles = 0;
    bool measure_wire = false;
    std::array<uint64_t, NETWORK_PORTS> lane_active_cycles{};
    bool failed = false;
    std::vector<Expected> expected;
    std::vector<Expected> forwarded;
    std::vector<uint32_t> descriptor_ports;
    std::array<std::vector<uint8_t>, NETWORK_PORTS> assembling;
    std::array<bool, NETWORK_PORTS> tx_in_frame{};
#if DEMO_VIDEO
    uint32_t video_decimation_phase = 0;
    std::vector<uint8_t> firmware_image;
    std::vector<Beat> traffic_beats;
    std::unique_ptr<Visualizer> visualizer;
#endif

    void fail(const std::string& text)
    {
        std::cerr << "l2_switch: " << text << '\n';
        failed = true;
    }

    void bind()
    {
        dut.traffic_load_valid_in = _ASSIGN(load_valid);
        dut.traffic_load_data_in = _ASSIGN(load_data);
        dut.traffic_load_keep_in = _ASSIGN(load_keep);
        dut.traffic_load_sop_in = _ASSIGN(load_sop);
        dut.traffic_load_eop_in = _ASSIGN(load_eop);
        dut.traffic_start_in = _ASSIGN(start);
        dut.traffic_clear_in = _ASSIGN(clear);
        dut.traffic_repeat_count_in = _ASSIGN(repeats);
        dut.host_request_valid_in = _ASSIGN(host_valid);
        dut.host_request_write_in = _ASSIGN(host_write);
        dut.host_address_in = _ASSIGN(host_address);
        dut.host_writedata_in = _ASSIGN(host_data);
        dut.host_wstrb_in = _ASSIGN(host_strobe);
        dut.__inst_name = "l2_switch";
        dut._assign();
    }

    void observe_forwarding()
    {
        if (!dut.smartnic.net_tx_valid_out()
            || !dut.smartnic.net_tx_ready_in()) return;
        const auto data = dut.smartnic.net_tx_data_out();
        const auto keep = dut.smartnic.net_tx_keep_out();
        const auto sop = dut.smartnic.net_tx_sop_out();
        const auto eop = dut.smartnic.net_tx_eop_out();
        constexpr uint32_t PORT_BYTES = Dut::NET_BYTES / NETWORK_PORTS;
        for (uint32_t port = 0; port < NETWORK_PORTS; ++port) {
            for (uint32_t lane_byte = 0; lane_byte < PORT_BYTES; ++lane_byte) {
                const uint32_t byte = port * PORT_BYTES + lane_byte;
                if (!keep[byte]) continue;
                if (sop[byte]) {
                    assembling[port].clear();
                    tx_in_frame[port] = true;
                }
                if (!tx_in_frame[port]) {
                    fail(std::format("MAC TX data without SOP on port {}", port));
                    return;
                }
                assembling[port].push_back((uint8_t)data.bits(
                    byte * 8 + 7, byte * 8));
                if (eop[byte]) {
                    forwarded.push_back({assembling[port], port});
                    assembling[port].clear();
                    tx_in_frame[port] = false;
                }
            }
        }
    }

    bool cycle(bool reset = false)
    {
        bool net = false;
        bool l2 = false;
        bool system = false;
        net_phase += NET_CLK_HZ;
        if (net_phase >= PROCESSING_CLK_HZ) {
            net_phase -= PROCESSING_CLK_HZ;
            net = true;
        }
        l2_phase += L2_CLK_HZ;
        if (l2_phase >= PROCESSING_CLK_HZ) {
            l2_phase -= PROCESSING_CLK_HZ;
            l2 = true;
        }
        system_phase += SYSTEM_CLK_HZ;
        if (system_phase >= PROCESSING_CLK_HZ) {
            system_phase -= PROCESSING_CLK_HZ;
            system = true;
        }
        if (net) observe_forwarding();
#if DEMO_VIDEO
        if (visualizer) {
            visualizer->observe_cpu_before(dut);
            if (net) visualizer->observe_net_before(dut);
            if (l2) visualizer->observe_l2_before(dut);
            if (system) visualizer->observe_system_before(dut);
        }
#endif
        if (l2 && dut.smartnic.l2_descriptor_valid_out()
            && dut.smartnic.l2_descriptor_ready_in()
            && (uint32_t)dut.smartnic.l2_descriptor_word_out() == 0) {
            descriptor_ports.push_back((uint32_t)dut.smartnic
                .l2_descriptor_data_out().bits(71, 64));
        }
        if (net && measure_wire && dut.traffic.valid_out()) {
            ++measured_net_cycles;
            const auto keep = dut.traffic.keep_out();
            constexpr uint32_t PORT_BYTES = Dut::NET_BYTES / NETWORK_PORTS;
            for (uint32_t port = 0; port < NETWORK_PORTS; ++port) {
                bool active = false;
                for (uint32_t byte = 0; byte < PORT_BYTES; ++byte)
                    active |= keep[port * PORT_BYTES + byte];
                if (active) ++lane_active_cycles[port];
            }
        }
        if (net && dut.traffic.valid_out()
            && !dut.smartnic.net_rx_ready_out()) {
            fail("wire ingress backpressured");
        }
        dut._work_cpu_clk(reset);
        if (net) dut._work_net_clk(reset);
        if (l2) dut._work_l2_clk(reset);
        if (system) dut._work_system_clk(reset);
        dut._strobe_cpu_clk();
        if (net) dut._strobe_net_clk();
        if (l2) dut._strobe_l2_clk();
        if (system) dut._strobe_system_clk();
#if DEMO_VIDEO
        if (visualizer && net) {
            if (video_decimation_phase == 0)
                visualizer->frame(dut, ticks, 0, l2, system);
            video_decimation_phase = (video_decimation_phase + 1)
                % DEMO_VIDEO_DECIMATION;
        }
#endif
        ++ticks;
        ++_system_clock;
        return net;
    }

    void wait_net()
    {
        while (!cycle()) {}
    }

    bool load_elf(const std::filesystem::path& path)
    {
        std::ifstream input(path, std::ios::binary);
        const std::vector<uint8_t> image{
            std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
        if (!input && image.empty()) {
            fail("cannot open firmware " + path.string());
            return false;
        }
        if (image.size() < sizeof(Elf32Header)) {
            fail("firmware is truncated");
            return false;
        }
        Elf32Header header{};
        std::memcpy(&header, image.data(), sizeof(header));
        for (uint32_t index = 0; index < header.phnum; ++index) {
            Elf32ProgramHeader segment{};
            const size_t position = header.phoff + index * header.phentsize;
            if (position + sizeof(segment) > image.size()) {
                fail("bad ELF program header");
                return false;
            }
            std::memcpy(&segment, image.data() + position, sizeof(segment));
            if (segment.type != 1) continue;
            if ((uint64_t)segment.offset + segment.filesz > image.size()) {
                fail("bad ELF load segment");
                return false;
            }
#if DEMO_VIDEO
            if (firmware_image.size() < (size_t)segment.paddr + segment.memsz)
                firmware_image.resize((size_t)segment.paddr + segment.memsz, 0);
#endif
            for (uint32_t byte = 0; byte < segment.memsz; ++byte) {
                const uint8_t value = byte < segment.filesz
                    ? image[segment.offset + byte] : 0;
                dut.load_cpu_byte(0, segment.paddr + byte, value);
#if DEMO_VIDEO
                firmware_image[segment.paddr + byte] = value;
#endif
            }
        }
        return true;
    }

    static std::array<uint8_t, 6> mac(uint32_t port, uint32_t station)
    {
        return {0x02, 0x10, 0x00, (uint8_t)port, 0x40,
            (uint8_t)(0x10 + station)};
    }

    static std::vector<uint8_t> packet(const std::array<uint8_t, 6>& dst,
        const std::array<uint8_t, 6>& src, uint32_t sequence)
    {
        std::vector<uint8_t> frame(SUSTAINED_SWITCH ? 1516 : 128);
        std::copy(dst.begin(), dst.end(), frame.begin());
        std::copy(src.begin(), src.end(), frame.begin() + 6);
        frame[12] = 0x08;
        frame[13] = 0x00;
#if DEMO_VIDEO
        static constexpr std::array<uint16_t, 16> patterns = {
            0x00ff, 0x0f0f, 0x0ff0, 0x0fff,
            0x00cc, 0x0c0c, 0x0cc0, 0x0ccc,
            0x009f, 0x00f9, 0x090f, 0x0f09,
            0x09f0, 0x0f90, 0x1990, 0x2660};
        const uint16_t pattern = patterns[sequence % patterns.size()];
        for (uint32_t byte = 14; byte < frame.size(); byte += 2) {
            frame[byte] = (uint8_t)pattern;
            if (byte + 1 < frame.size()) frame[byte + 1] = pattern >> 8;
        }
#else
        for (uint32_t byte = 14; byte < frame.size(); ++byte) {
            frame[byte] = (uint8_t)(sequence * 37u + byte * 11u);
        }
#endif
        frame[14] = (uint8_t)sequence;
        frame[15] = (uint8_t)(sequence >> 8);
        frame[16] = (uint8_t)(sequence >> 16);
        frame[17] = (uint8_t)(sequence >> 24);
        return frame;
    }

    std::vector<std::vector<uint8_t>> make_learning_traffic()
    {
        std::vector<std::vector<uint8_t>> frames;
        const std::array<uint8_t, 6> multicast = {1, 0, 0x5e, 0, 0, 1};
        uint32_t sequence = 0;
        for (uint32_t station = 0; station < 10; ++station) {
            for (uint32_t port = 0; port < NETWORK_PORTS; ++port) {
                frames.push_back(packet(multicast, mac(port, station), sequence++));
            }
        }
        return frames;
    }

    std::vector<std::vector<uint8_t>> make_traffic()
    {
        std::vector<std::vector<uint8_t>> frames;
        uint32_t sequence = 20;
#if CPU_LOOPBACK_TEST
        for (uint32_t transfer = 0; transfer < 8; ++transfer) {
            const uint32_t ingress = transfer & 1u;
            const std::array<uint8_t, 6> destination =
                {0x02, 0x31, 0, (uint8_t)(ingress ^ 1u), 0x55,
                    (uint8_t)transfer};
            auto frame = packet(destination,
                mac(ingress, transfer % 10u), sequence++);
            // cpu_loopback.S always swaps the physical ingress port.
            expected.push_back({frame, ingress ^ 1u});
            frames.push_back(std::move(frame));
        }
        return frames;
#else
#if !SUSTAINED_SWITCH
        frames = make_learning_traffic();
#endif
        // Then exercise same-port return and cross-port forwarding equally.
        for (uint32_t transfer = 0; transfer < 40; ++transfer) {
            const uint32_t ingress = transfer & 1u;
            const uint32_t destination_port = (transfer & 2u)
                ? (ingress ^ 1u) : ingress;
            auto frame = packet(mac(destination_port,
                    (transfer * 3u + 1u) % 10u),
                mac(ingress, transfer % 10u), sequence++);
#if !SUSTAINED_SWITCH
            expected.push_back({frame, destination_port});
#endif
            frames.push_back(std::move(frame));
        }
        return frames;
#endif
    }

    static std::vector<std::vector<uint8_t>> repeat_traffic(
        const std::vector<std::vector<uint8_t>>& base, uint32_t count)
    {
        std::vector<std::vector<uint8_t>> frames;
        frames.reserve(base.size() * count);
        for (uint32_t repeat = 0; repeat < count; ++repeat)
            frames.insert(frames.end(), base.begin(), base.end());
        return frames;
    }

    bool load_traffic(const std::vector<std::vector<uint8_t>>& frames)
    {
        Generator generator;
#if DEMO_VIDEO
        traffic_beats.clear();
#endif
        generator.clear();
        for (const auto& frame : frames)
            generator.push(frame, SUSTAINED_SWITCH ? 384 : 128);
        generator.finalize();
        if (generator.size() > TRAFFIC_DEPTH) {
            fail("traffic image is too large");
            return false;
        }
        while (!generator.empty()) {
            if (!dut.traffic_load_ready_out()) {
                fail("traffic loader refused a beat");
                return false;
            }
            const auto& beat = generator.front();
#if DEMO_VIDEO
            traffic_beats.push_back(beat);
#endif
            load_data = beat.data;
            load_keep = beat.keep;
            load_sop = beat.sop;
            load_eop = beat.eop;
            load_valid = true;
            wait_net();
            load_valid = false;
            generator.pop();
        }
        load_data = 0;
        load_keep = 0;
        load_sop = 0;
        load_eop = 0;
        return true;
    }

    void clear_traffic()
    {
        clear = true;
        wait_net();
        clear = false;
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
        for (uint32_t reset = 0; reset < 512; ++reset) cycle(true);
        std::vector<std::vector<uint8_t>> frames;
#if SUSTAINED_SWITCH
        // Train all twenty MACs first. The long measured phase starts only
        // after software has drained this finite setup traffic and enabled
        // DescriptorFetcher's independent auto-L2 engine.
        repeats = 1;
        const auto learning = make_learning_traffic();
        if (!load_traffic(learning)) return false;
#else
        frames = make_traffic();
        if (!load_traffic(frames)) return false;
#endif
        // Narrow DDR makes instruction-cache refill intentionally visible.
        for (uint32_t boot = 0; boot < 100000; ++boot) cycle();
#if SUSTAINED_SWITCH
        start = true;
        wait_net();
        start = false;
        const uint64_t learning_timeout = ticks + 2000000;
        while (ticks < learning_timeout && !failed
            && (!dut.traffic.done_out()
                || (uint32_t)dut.processing.packet_dma[0]
                    .completed_count_out() < learning.size()
                || (uint32_t)dut.processing.descriptor_fetcher[0]
                    .descriptor_count_out() != 0
                || dut.processing.packet_dma[0].busy_out())) {
            cycle();
            if (dut.protocol_error_out()) fail("RTL protocol_error during learning");
            if (dut.storage_full_out()) fail("receive storage full during learning");
        }
        if ((uint32_t)dut.processing.packet_dma[0].completed_count_out()
            < learning.size()) fail("MAC learning phase did not drain");
        const uint64_t hash_flush_timeout = ticks + 2000000;
        while (ticks < hash_flush_timeout && !failed
            && !dut.processing.descriptor_fetcher[0]
                .auto_l2_enabled_out()) cycle();
        if (!dut.processing.descriptor_fetcher[0].auto_l2_enabled_out())
            fail("firmware did not complete the MAC-hash writeback barrier");
        for (uint32_t settle = 0; settle < 100 && !failed; ++settle) cycle();

        clear_traffic();
        repeats = DEMO_TRAFFIC_REPEATS;
        const auto base_frames = make_traffic();
        frames = repeat_traffic(base_frames, DEMO_TRAFFIC_REPEATS);
        expected.clear();
        for (uint32_t index = DEMO_NETWORK_INTERVAL - 1;
            index < frames.size(); index += DEMO_NETWORK_INTERVAL) {
            expected.push_back({frames[index], frames[index][3]});
        }
        if (!load_traffic(base_frames)) return false;
#endif
#if DEMO_VIDEO
        // Start recording after boot so the animation represents switching,
        // rather than spending most of its duration in the reset/firmware wait.
        visualizer = std::make_unique<Visualizer>(output, frames,
            traffic_beats, firmware_image,
            SUSTAINED_SWITCH ? DEMO_TRAFFIC_REPEATS : 1,
            120, background);
#endif
#if SUSTAINED_SWITCH
        measured_net_cycles = 0;
        lane_active_cycles.fill(0);
        measure_wire = true;
#endif
        start = true;
        wait_net();
        start = false;

        const uint64_t timeout = ticks + (SUSTAINED_SWITCH ? 2000000ull
            : (CPU_LOOPBACK_TEST ? 5000000ull : 30000000ull));
        uint32_t expected_backing_beats = 0;
#if SUSTAINED_SWITCH
        for (const auto& frame : frames)
            expected_backing_beats += (frame.size() + 31) / 32;
        expected_backing_beats += (uint32_t)frames.size();
#endif
        uint64_t next_progress = ticks + 100000;
        while (ticks < timeout && (forwarded.size() < expected.size()
#if SUSTAINED_SWITCH
                || (uint32_t)dut.processing.packet_dma[0]
                    .cache_completed_count_out() < frames.size()
                || (uint32_t)dut.processing.packet_dma[0]
                    .backing_completed_beat_count_out()
                    < expected_backing_beats
                || (uint32_t)dut.processing.packet_dma[0]
                    .clear_completed_count_out() < frames.size()
#endif
                )
            && !failed) {
            cycle();
            if constexpr (CPU_LOOPBACK_TEST) {
                if (ticks >= next_progress) {
                    std::cerr << std::format(
                        "cpu_loopback: ticks={} descriptors={} dma={} "
                        "busy={} rx_read={}/{} rx={}/{} tx={}/{} port={} "
                        "forwarded={}/{}\n",
                        ticks,
                        (uint32_t)dut.processing.descriptor_fetcher[0]
                            .descriptor_count_out(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .command_completed_count_out(),
                        dut.processing.packet_dma[0].busy_out(),
                        dut.processing.packet_dma[0].rx_read_valid_out(),
                        dut.processing.packet_dma[0].rx_read_ready_in(),
                        dut.processing.packet_dma[0].rx_valid_in(),
                        dut.processing.packet_dma[0].rx_ready_out(),
                        dut.processing.packet_dma[0].network_tx_valid_out(),
                        dut.processing.packet_dma[0].network_tx_ready_in(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .network_tx_port_out(),
                        forwarded.size(), expected.size());
                    next_progress += 100000;
                }
            }
            if constexpr (SUSTAINED_SWITCH) {
                if (ticks >= next_progress) {
                    std::cerr << std::format(
                        "l2_switch sustained: ticks={} wire_done={} "
                        "cache={} backing={} clears={} dma={} busy={} descriptors={} "
                        "tx={}/{}\n",
                        ticks, dut.traffic.done_out(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .cache_completed_count_out(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .backing_completed_beat_count_out(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .clear_completed_count_out(),
                        (uint32_t)dut.processing.packet_dma[0]
                            .completed_count_out(),
                        dut.processing.packet_dma[0].busy_out(),
                        (uint32_t)dut.processing.descriptor_fetcher[0]
                            .descriptor_count_out(),
                        forwarded.size(), expected.size());
                    next_progress += 100000;
                }
            }
            if (dut.protocol_error_out()) {
                fail(std::format("RTL protocol_error asserted: smartnic={} "
                    "network{{balancer={},parser={},rxram={},join={}}} "
                    "system={} traffic={} host={} fetcher={} dma={} "
                    "dma_reason={}", dut.smartnic.protocol_error_out(),
                    dut.smartnic.debug_network_balancer_error(),
                    dut.smartnic.debug_network_parser_error(),
                    dut.smartnic.debug_network_rx_ram_error(),
                    dut.smartnic.debug_network_join_error(),
                    dut.system.protocol_error_out(),
                    dut.traffic.protocol_error_out(),
                    dut.host.protocol_error_out(),
                    dut.processing.descriptor_fetcher[0].protocol_error_out(),
                    dut.processing.packet_dma[0].protocol_error_out(),
                    (uint32_t)dut.processing.packet_dma[0]
                        .protocol_error_reason_out()));
            }
            // Full occupancy is legal after accepting the tail of a finite
            // wire-rate burst. cycle() already fails on the actual contract
            // violation: traffic.valid while net_rx_ready is deasserted. Keep
            // draining here so a full-but-lossless RxRAM is not reported as a
            // dropped packet.
        }
#if SUSTAINED_SWITCH
        measure_wire = false;
        if ((uint32_t)dut.processing.packet_dma[0]
            .cache_completed_count_out() != frames.size()) {
            fail(std::format("coherent L2 prefetch completed {} of {} packets",
                (uint32_t)dut.processing.packet_dma[0]
                    .cache_completed_count_out(), frames.size()));
        }
        if ((uint32_t)dut.processing.packet_dma[0]
            .backing_completed_beat_count_out() != expected_backing_beats) {
            fail(std::format("DDR packet backing completed {} of {} beats",
                (uint32_t)dut.processing.packet_dma[0]
                    .backing_completed_beat_count_out(),
                expected_backing_beats));
        }
        if ((uint32_t)dut.processing.packet_dma[0]
            .clear_completed_count_out() != frames.size()) {
            fail(std::format("CPU-requested post-TX clears completed {} of {} "
                "packets",
                (uint32_t)dut.processing.packet_dma[0]
                    .clear_completed_count_out(), frames.size()));
        }
        // Verify the complete resident half-DDR packet-ring image, not merely
        // the sampled headers. This harness has 512 slots, so all 400 measured
        // packets remain resident; the calculation also covers future wraps.
        constexpr uint32_t ring_slots = Dut::DDR_BYTES / 2 / 2048;
        const uint32_t first_resident = frames.size() > ring_slots
            ? (uint32_t)frames.size() - ring_slots : 0;
        for (uint32_t index = first_resident; index < frames.size(); ++index) {
            const uint32_t base = (index & (ring_slots - 1)) * 2048;
            for (uint32_t byte = 0; byte < frames[index].size(); ++byte) {
                const uint8_t expected_byte = byte < CPU::CACHE_LINE_BYTES
                    ? 0 : frames[index][byte];
                if (dut.cpu_memory_byte(0, base + byte) != expected_byte) {
                    fail(std::format("DDR packet ring mismatch packet {} "
                        "byte {} actual=0x{:02x} expected=0x{:02x}", index,
                        byte, dut.cpu_memory_byte(0, base + byte),
                        expected_byte));
                    index = (uint32_t)frames.size();
                    break;
                }
            }
        }
#endif
        if (forwarded.size() != expected.size()) {
            fail(std::format("forwarded {} of {} expected packets",
                forwarded.size(), expected.size()));
        }
        for (size_t index = 0; index < descriptor_ports.size(); ++index) {
            if (descriptor_ports[index] != (index & 1u)) {
                fail(std::format("descriptor {} source port {}, expected {}",
                    index, descriptor_ports[index], index & 1u));
                break;
            }
        }
        std::vector<bool> matched(expected.size(), false);
        for (size_t actual = 0; actual < forwarded.size(); ++actual) {
            size_t match = expected.size();
            for (size_t candidate = 0; candidate < expected.size(); ++candidate) {
                if (!matched[candidate]
                    && forwarded[actual].packet == expected[candidate].packet) {
                    match = candidate;
                    break;
                }
            }
            if (match == expected.size()) {
                fail(std::format("unknown or changed MAC TX packet {} header {}",
                    actual, header_hex(forwarded[actual].packet)));
                break;
            }
            matched[match] = true;
            if (forwarded[actual].port != expected[match].port) {
                fail(std::format("packet {} left MAC port {}, expected {}; "
                    "header {}", match, forwarded[actual].port,
                    expected[match].port, header_hex(forwarded[actual].packet)));
                break;
            }
        }
        if (!std::all_of(matched.begin(), matched.end(), [](bool value) {
                return value;
            })) fail("one or more expected packets never reached MAC TX");
#if !SUSTAINED_SWITCH && !CPU_LOOPBACK_TEST
        // The final known packet was installed dirty by PacketDMA, evicted by
        // firmware, and then refilled for TX. Its byte-exact DDR image proves
        // that the writeback path was exercised rather than only an L2 hit.
        if (!expected.empty()) {
            const uint32_t final_packet_address =
                (uint32_t)(frames.size() - 1) * 2048;
            for (uint32_t byte = 0; byte < expected.back().packet.size(); ++byte) {
                if (dut.cpu_memory_byte(0, final_packet_address + byte)
                    != expected.back().packet[byte]) {
                    fail(std::format("DDR4 writeback mismatch at byte {}", byte));
                    break;
                }
            }
        }
#endif
        if (!dut.traffic.done_out()) fail("long traffic generator did not drain");
        if ((uint32_t)dut.traffic_backpressure_cycles_out() != 0) {
            fail("traffic generator recorded ingress backpressure");
        }
#if SUSTAINED_SWITCH
        for (uint32_t port = 0; port < NETWORK_PORTS; ++port) {
            const double load = measured_net_cycles == 0 ? 0.0
                : 100.0 * lane_active_cycles[port] / measured_net_cycles;
            if (load < 79.0 || load > 81.0) {
                fail(std::format("port {} wire load {:.2f}% is outside 80%",
                    port, load));
            }
        }
        if (failed) {
            auto& packet_backing = dut.processing.packet_dma[0].backing_dma;
            auto& external_ddr = dut.processing.ddr[0];
            auto& adapter = dut.cpu_memory_adapter[0];
            std::print("backing AXI: aw={}/{} w={}/{} b={}/{}; "
                       "DDR AXI: aw={}/{} w={}/{} b={}/{}; "
                       "adapter in: aw={} w={} native={}\n",
                packet_backing.awvalid_out(), packet_backing.awready_in(),
                packet_backing.wvalid_out(), packet_backing.wready_in(),
                packet_backing.bvalid_in(), packet_backing.bready_out(),
                external_ddr.awvalid_out(), external_ddr.awready_in(),
                external_ddr.wvalid_out(), external_ddr.wready_in(),
                external_ddr.bvalid_in(), external_ddr.bready_out(),
                adapter.axi.awvalid_in(), adapter.axi.wvalid_in(),
                adapter.ddr_valid_out());
            std::print("DMA counters: completed={} cache={} commands={} "
                       "backing_beats={} last_op={}\n",
                (uint32_t)dut.processing.packet_dma[0].completed_count_out(),
                (uint32_t)dut.processing.packet_dma[0]
                    .cache_completed_count_out(),
                (uint32_t)dut.processing.packet_dma[0]
                    .command_completed_count_out(),
                (uint32_t)dut.processing.packet_dma[0]
                    .backing_completed_beat_count_out(),
                (uint32_t)dut.processing.packet_dma[0].last_operation_out());
        }
#endif
#if DEMO_VIDEO
        visualizer->frame(dut, ticks, 0, true, true);
        if (!visualizer->mac_tx_ok()
            || visualizer->mac_tx_packet_count() != expected.size()) {
            fail(std::format("video MAC TX verification failed: {} of {}",
                visualizer->mac_tx_packet_count(), expected.size()));
        }
        for (uint32_t port = 0; port < NETWORK_PORTS; ++port) {
            const uint32_t expected_port_packets = (uint32_t)std::count_if(
                expected.begin(), expected.end(), [port](const Expected& item) {
                    return item.port == port;
                });
            if (visualizer->rx_fifo_frame_count(port) == 0
                || visualizer->tx_fifo_frame_count(port) == 0) {
                fail(std::format("video port {} FIFO activity missing: "
                    "RX frames={}, TX frames={}", port,
                    visualizer->rx_fifo_frame_count(port),
                    visualizer->tx_fifo_frame_count(port)));
            }
            if (visualizer->mac_tx_packet_count(port)
                != expected_port_packets) {
                fail(std::format("video MAC port {} transmitted {} of {}",
                    port, visualizer->mac_tx_packet_count(port),
                    expected_port_packets));
            }
        }
        for (uint32_t core = 0; core < CPU::CORES; ++core) {
            if (visualizer->packet_header_read_count(core) == 0) {
                fail(std::format("video core {} never read a packet header",
                    core));
            }
        }
        if (visualizer->simultaneous_packet_core_count() < 2) {
            fail(std::format("video never observed concurrent packet work; "
                "maximum active cores={}",
                visualizer->simultaneous_packet_core_count()));
        }
        visualizer->finish();
#endif
        std::print("l2_switch: learned=20 ingress={} forwarded={}/{} ticks={} "
            "backpressure={} result={}"
#if SUSTAINED_SWITCH
            " lane_load={:.2f}%/{:.2f}%"
#endif
#if DEMO_VIDEO
            " video_frames={} video={}"
#endif
            "\n", frames.size(), forwarded.size(), expected.size(),
            ticks, (uint32_t)dut.traffic_backpressure_cycles_out(),
            failed ? "FAILED" : "PASSED"
#if SUSTAINED_SWITCH
            , 100.0 * lane_active_cycles[0] / measured_net_cycles
            , 100.0 * lane_active_cycles[1] / measured_net_cycles
#endif
#if DEMO_VIDEO
            , visualizer->frame_count(), output.string()
#endif
            );
        return !failed;
    }
};

} // namespace

int main(int argc, char** argv)
{
#if DEMO_VIDEO
    try {
        const std::filesystem::path firmware = argc > 1
            ? argv[1] : "l2_switch.elf";
        const std::filesystem::path output = argc > 2
            ? argv[2] : "smartnic_l2_switch.avi";
        const uint8_t background = argc > 3
            ? (uint8_t)std::stoul(argv[3]) : Canvas::UI_OUTSIDE;
        return L2SwitchTest().run(firmware, output, background) ? 0 : 1;
    }
    catch (const std::exception& exception) {
        std::cerr << "l2_switch video exception: " << exception.what() << '\n';
        return 1;
    }
#else
    return L2SwitchTest().run(argc > 1 ? argv[1] : "l2_switch.elf") ? 0 : 1;
#endif
}
