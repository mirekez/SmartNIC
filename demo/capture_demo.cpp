// Full 800G capture demonstration. This is the production capture test with
// visualization observers attached to every public datapath boundary. Packet
// payloads, including their first bytes, use repeating two-byte color words.

#include "../test/SmartNICTest.h"
#include "../rtl/testing/GenEthStream.h"
#include "../rtl/system/Controller.h"
#include "Visualizer.h"

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

constexpr uint32_t DEMO_TRAFFIC_DEPTH = 2048;
constexpr uint32_t DEMO_CPU_RAM_WORDS = 8192;
using Dut = SmartNICTest<NET_LANE_WIDTH, CPUS_USED, DEMO_TRAFFIC_DEPTH,
    DEMO_CPU_RAM_WORDS>;
using Generator = GenEthStream<NET_LANE_WIDTH>;
using Beat = Generator::Beat;
using Visualizer = smartnic_demo::Visualizer<Dut, Beat>;
using smartnic_demo::Canvas;

constexpr uint64_t HOST_PACKET_BASE = 0x00100000;
constexpr uint32_t HOST_PACKET_STRIDE = 2048;
constexpr uint32_t BASE_FRAME_COUNT = 32;
constexpr uint32_t TRAFFIC_MULTIPLIER = 20;
constexpr uint32_t FRAME_COUNT = BASE_FRAME_COUNT * TRAFFIC_MULTIPLIER;
constexpr uint32_t VIDEO_DECIMATION = TRAFFIC_MULTIPLIER;
// Twenty times the original traffic is sampled every twentieth Network clock;
// 140-fps playback absorbs the host-drain tail and stays near 36 seconds.
constexpr uint32_t VIDEO_FPS = 140;
constexpr uint64_t MAX_CPU_TICKS = 30000000;
constexpr uint64_t PROGRESS_INTERVAL = 25000;

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

class CaptureDemo
{
    Dut dut;
    bool traffic_load_valid = false;
    logic<Dut::NET_BITS> traffic_load_data = 0;
    logic<Dut::NET_BYTES> traffic_load_keep = 0;
    logic<Dut::NET_BYTES> traffic_load_sop = 0;
    logic<Dut::NET_BYTES> traffic_load_eop = 0;
    bool traffic_start = false;
    bool traffic_clear = false;
    u<16> traffic_repeat_count = 1;
    bool host_read = false;
    bool host_write = false;
    u32 host_address = 0;
    logic<HOST_DATA_WIDTH> host_writedata = 0;
    logic<HOST_DATA_WIDTH / 8> host_byteenable = 0;
    uint64_t net_phase = 0;
    uint64_t l2_phase = 0;
    uint64_t system_phase = 0;
    uint64_t ticks = 0;
    uint32_t video_decimation_phase = 0;
    uint32_t host_consumer = 0;
    bool error = false;
    std::vector<uint8_t> firmware_image;
    std::unique_ptr<Visualizer> visualizer;

    static constexpr uint64_t CPU_CLOCK_HZ = L2_CLK_HZ * 4;

    struct Edges
    {
        bool net = false;
        bool l2 = false;
        bool system = false;
    };

    void fail(const std::string& message)
    {
        std::cerr << "800G demo: " << message << '\n';
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
        dut.__inst_name = "capture_demo";
        dut._assign();
    }

    Edges cycle(bool reset = false)
    {
        Edges edges;
        if (visualizer) visualizer->observe_cpu_before(dut);
        dut._work_cpu_clk(reset);
        dut._strobe_cpu_clk();

        net_phase += NET_CLK_HZ;
        if (net_phase >= CPU_CLOCK_HZ) {
            net_phase -= CPU_CLOCK_HZ;
            if (visualizer) visualizer->observe_net_before(dut);
            dut._work_net_clk(reset);
            dut._strobe_net_clk();
            edges.net = true;
        }
        l2_phase += L2_CLK_HZ;
        if (l2_phase >= CPU_CLOCK_HZ) {
            l2_phase -= CPU_CLOCK_HZ;
            if (visualizer) visualizer->observe_l2_before(dut);
            dut._work_l2_clk(reset);
            dut._strobe_l2_clk();
            edges.l2 = true;
        }
        system_phase += SYSTEM_CLK_HZ;
        if (system_phase >= CPU_CLOCK_HZ) {
            system_phase -= CPU_CLOCK_HZ;
            if (visualizer) visualizer->observe_system_before(dut);
            dut._work_system_clk(reset);
            dut._strobe_system_clk();
            edges.system = true;
        }
        ++ticks;
        ++_system_clock;
        if (edges.net && visualizer) {
            if (video_decimation_phase == 0) {
                visualizer->frame(ticks, host_consumer, edges.l2, edges.system);
            }
            video_decimation_phase = (video_decimation_phase + 1)
                % VIDEO_DECIMATION;
        }
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
            if (firmware_image.size() < (size_t)address + segment.memsz) {
                firmware_image.resize((size_t)address + segment.memsz, 0);
            }
            for (uint32_t byte = 0; byte < segment.memsz; ++byte) {
                const uint8_t value = byte < segment.filesz
                    ? image[segment.offset + byte] : 0;
                firmware_image[address + byte] = value;
                for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
                    dut.load_cpu_byte(cluster, address + byte, value);
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
        do { wait_system_edge(); } while (dut.host_waitrequest_out());
        host_write = false;
        host_writedata = 0;
        host_byteenable = 0;
    }

    uint32_t read32(uint32_t address)
    {
        const uint32_t lane = address & (HOST_DATA_WIDTH / 8 - 1);
        host_address = address;
        host_read = true;
        do { wait_system_edge(); } while (dut.host_waitrequest_out());
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

    static std::vector<std::vector<uint8_t>> make_frames()
    {
        static constexpr std::array<uint32_t, 8> sizes = {
            64, 128, 256, 512, 1024, 1516, 768, 300};
        // High component nibbles and modest gain values produce vivid packet
        // bands against the neutral gray block backgrounds.
        static constexpr std::array<uint16_t, BASE_FRAME_COUNT> patterns = {
            0x000f, 0x00f0, 0x0f00, 0x00ff, 0x0f0f, 0x0ff0, 0x0fff, 0x000c,
            0x00c0, 0x0c00, 0x00cc, 0x0c0c, 0x0cc0, 0x0ccc, 0x009f, 0x00f9,
            0x090f, 0x0f09, 0x09f0, 0x0f90, 0x1099, 0x1909, 0x1990, 0x1066,
            0x1606, 0x1660, 0x2066, 0x2606, 0x2660, 0x2048, 0x2480, 0x2804};
        std::vector<std::vector<uint8_t>> frames;
        for (uint32_t index = 0; index < FRAME_COUNT; ++index) {
            std::vector<uint8_t> frame(sizes[index % sizes.size()]);
            const uint16_t pattern = patterns[index % patterns.size()];
            for (uint32_t byte = 0; byte < frame.size(); byte += 2) {
                frame[byte] = (uint8_t)pattern;
                if (byte + 1 < frame.size()) frame[byte + 1] = pattern >> 8;
            }
            frames.push_back(std::move(frame));
        }
        return frames;
    }

    static std::vector<Beat> pack_traffic(
        const std::vector<std::vector<uint8_t>>& frames)
    {
        Generator generator;
        generator.clear();
        for (const auto& frame : frames) generator.push(frame, 12);
        generator.finalize();
        std::vector<Beat> beats;
        beats.reserve(generator.size());
        while (!generator.empty()) {
            beats.push_back(generator.front());
            generator.pop();
        }
        return beats;
    }

    bool load_traffic(const std::vector<Beat>& beats)
    {
        if (beats.size() > DEMO_TRAFFIC_DEPTH) {
            fail("traffic image exceeds harness generator depth");
            return false;
        }
        for (const Beat& beat : beats) {
            if (!dut.traffic_load_ready_out()) {
                fail("traffic generator refused a setup beat");
                return false;
            }
            traffic_load_data = beat.data;
            traffic_load_keep = beat.keep;
            traffic_load_sop = beat.sop;
            traffic_load_eop = beat.eop;
            traffic_load_valid = true;
            wait_net_edge();
            traffic_load_valid = false;
        }
        traffic_load_data = 0;
        traffic_load_keep = 0;
        traffic_load_sop = 0;
        traffic_load_eop = 0;
        return true;
    }

    bool verify_packets(const std::vector<std::vector<uint8_t>>& frames)
    {
        std::vector<bool> captured(frames.size(), false);
        for (uint32_t slot = 0; slot < frames.size(); ++slot) {
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
                if (equal) { match = frame; break; }
            }
            if (match == frames.size()) {
                fail(std::format("host slot {} is corrupt, duplicated, or unknown",
                    slot));
                return false;
            }
            captured[match] = true;
        }
        return true;
    }

    void report_progress()
    {
        std::cerr << "800G demo progress: ticks=" << ticks
                  << " host=" << host_consumer << '/' << FRAME_COUNT;
        for (uint32_t cluster = 0; cluster < CPUS_USED; ++cluster) {
            std::cerr << " c" << cluster << "{desc="
                      << (uint32_t)dut.processing.descriptor_fetcher[cluster]
                          .descriptor_count_out()
                      << ",dma="
                      << (uint32_t)dut.processing.packet_dma[cluster]
                          .completed_count_out() << '}';
        }
        std::cerr << '\n';
    }

public:
    bool run(const std::filesystem::path& firmware,
        const std::filesystem::path& output, uint8_t background)
    {
        bind();
        if (!load_elf(firmware)) return false;
        const auto frames = make_frames();
        const auto beats = pack_traffic(frames);
        visualizer = std::make_unique<Visualizer>(output, frames, beats,
            firmware_image, VIDEO_FPS, background);

        // Include reset, ring programming, generator loading, wire burst and
        // host drain in the movie. A frame is emitted after every net-clock
        // evaluation while all other clocks retain their exact phase ratios.
        for (uint32_t index = 0; index < 512; ++index) cycle(true);
        for (uint32_t frame = 0; frame < frames.size(); ++frame) {
            write_ring_descriptor(frame,
                HOST_PACKET_BASE + frame * HOST_PACKET_STRIDE,
                HOST_PACKET_STRIDE, frame % CPUS_USED);
        }
        write32(Controller<>::REG_RX_PRODUCER, frames.size());
        write32(Controller<>::REG_CONTROL, Controller<>::CONTROL_ENABLE);
        if (!load_traffic(beats)) return false;

        traffic_start = true;
        wait_net_edge();
        traffic_start = false;

        uint64_t next_poll = ticks;
        uint64_t next_progress = ticks + PROGRESS_INTERVAL;
        report_progress();
        while (ticks < MAX_CPU_TICKS && host_consumer != frames.size()
            && !error) {
            cycle();
            if (ticks >= next_poll) {
                host_consumer = read32(Controller<>::REG_RX_CONSUMER);
                next_poll = ticks + 20000;
            }
            if (ticks >= next_progress) {
                report_progress();
                next_progress = ticks + PROGRESS_INTERVAL;
            }
            if (dut.protocol_error_out()) {
                fail("RTL protocol_error asserted");
            }
            if (dut.storage_full_out()) fail("RxRAM/RxFIFO storage_full asserted");
        }
        host_consumer = read32(Controller<>::REG_RX_CONSUMER);
        if (host_consumer != frames.size()) {
            fail(std::format("capture timed out: {} of {} packets reached host",
                host_consumer, frames.size()));
        }
        if (!dut.traffic_done_out()) fail("traffic source did not drain");
        if ((uint32_t)dut.traffic_backpressure_cycles_out() != 0) {
            fail(std::format("wire-speed violation: {} network cycles backpressured",
                (uint32_t)dut.traffic_backpressure_cycles_out()));
        }
        if (!error) verify_packets(frames);
        visualizer->finish();

        std::print("800G demo: packets={} beats={} CPU ticks={} video_frames={} "
                   "result={}\nvideo: {}\n",
            frames.size(), (uint32_t)dut.traffic_emitted_beats_out(), ticks,
            visualizer->frame_count(), error ? "FAILED" : "PASSED",
            output.string());
        return !error;
    }
};

} // namespace

int main(int argc, char** argv)
{
    try {
        const std::filesystem::path firmware = argc > 1
            ? argv[1] : "capture.elf";
        const std::filesystem::path output = argc > 2
            ? argv[2] : "smartnic_800g.avi";
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
        return CaptureDemo().run(firmware, output, background) ? 0 : 1;
    }
    catch (const std::exception& exception) {
        std::cerr << "800G demo exception: " << exception.what() << '\n';
        return 1;
    }
}
