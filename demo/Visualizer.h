#pragma once

// Visualization-only mirrors driven by real SmartNIC public handshakes. No
// synthesis state is exposed or modified: the mirrors observe generator load
// and emission, descriptor/RxRAM completion, PacketDMA coherent AXI writes,
// CPU instruction/data accesses, System queue traffic, and host DMA drains.

#include "Video.h"
#include "../Config.h"

#include <array>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <format>
#include <string>
#include <vector>

#if !DEMO_VIDEO
#error "The SmartNIC video visualizer requires DEMO_VIDEO=1"
#endif

namespace smartnic_demo
{

using Packet = std::vector<uint8_t>;
using PacketList = std::vector<Packet>;

template<class DUT, class BEAT>
class Visualizer
{
    static constexpr uint32_t QUEUES = 8;
    static constexpr uint32_t CLUSTERS = CPUS_USED;
    static constexpr uint32_t L2_VIEW_BYTES = 2048;
    static constexpr uint32_t L1_VIEW_BYTES = 512;
    static constexpr uint32_t PACKET_BUFFER = 0x00010000;
    static constexpr uint64_t HOST_PACKET_BASE = 0x00100000;
    static constexpr uint32_t HOST_PACKET_STRIDE = 2048;

    static_assert(CLUSTERS == 8,
        "the 800G demonstration layout shows eight Processing clusters");

    const PacketList& source_packets;
    const std::vector<BEAT>& source_beats;
    const uint32_t source_repeats;
    const std::vector<uint8_t>& firmware;
    std::filesystem::path video_path;
    RleAviWriter video;
#if DEMO_TRANSPARENT_VIDEO
    ApngWriter transparent_video;
#endif
    std::ofstream trace;
    Canvas canvas;
    uint8_t background_color;

    size_t loaded_beats = 0;
    size_t emitted_beats = 0;
    size_t completed_packets = 0;
    uint64_t net_cycles = 0;
    uint64_t cpu_cycles = 0;
    uint64_t l2_cycles = 0;
    uint64_t system_cycles = 0;

    std::array<std::vector<Packet>, QUEUES> rx_ram;
    std::array<std::deque<Packet>, CLUSTERS> rx_fifo;
    std::array<std::deque<Packet>, QUEUES> tx_fifo;
    std::array<Packet, QUEUES> tx_fifo_assembling;
    std::array<std::deque<Packet>, QUEUES> rx_queue;
    std::array<Packet, QUEUES> rx_queue_assembling;
    std::array<std::deque<Packet>, QUEUES> tx_queue;

    std::array<Packet, CLUSTERS> l2_data;
    std::array<std::vector<bool>, CLUSTERS> l2_valid;
    std::array<uint32_t, CLUSTERS> l2_packet_base{};
    std::array<uint32_t, CLUSTERS> l2_write_address{};
    std::array<uint32_t, CLUSTERS> l2_previous_write_address{};
    std::array<bool, CLUSTERS> l2_previous_write_valid{};
    std::array<bool, CLUSTERS> l2_write_address_valid{};
    std::array<Packet, CLUSTERS> l1_instruction;
    std::array<std::vector<bool>, CLUSTERS> l1_instruction_valid;
    std::array<Packet, CLUSTERS> l1_data;
    std::array<std::vector<bool>, CLUSTERS> l1_data_valid;
    std::array<uint32_t, CLUSTERS> l1_instruction_address{};
    std::array<uint32_t, CLUSTERS> l1_data_address{};
    std::array<bool, CLUSTERS> l1_touch_completed{};
    std::array<uint32_t, CLUSTERS> last_dma_completed{};
    bool loaded_snapshot_written = false;
    bool mid_snapshot_written = false;
    bool queue_snapshot_written = false;

    static constexpr uint8_t BLACK = Canvas::rgb332(0, 0, 0);
    static constexpr uint8_t PANEL = Canvas::UI_PANEL;
    static constexpr uint8_t BORDER = Canvas::UI_BORDER;
    static constexpr uint8_t GRID = Canvas::UI_GRID;
    static constexpr uint8_t TEXT = Canvas::UI_TEXT;
    static constexpr uint8_t ACTIVE = Canvas::UI_ACTIVE;

    static Packet descriptor_for(const Packet& packet, uint32_t index)
    {
        Packet descriptor(160, 0);
        descriptor[0] = (uint8_t)index;
        descriptor[1] = (uint8_t)(index >> 8);
        descriptor[4] = (uint8_t)packet.size();
        descriptor[5] = (uint8_t)(packet.size() >> 8);
        descriptor[6] = (uint8_t)(index & 7u);
        const size_t copied = std::min<size_t>(128, packet.size());
        std::copy_n(packet.begin(), copied, descriptor.begin() + 32);
        return descriptor;
    }

    template<size_t DATA_WIDTH, size_t KEEP_WIDTH>
    static void append_beat(Packet& packet, const logic<DATA_WIDTH>& data,
        const logic<KEEP_WIDTH>& keep)
    {
        static_assert(DATA_WIDTH / 8 == KEEP_WIDTH);
        for (size_t byte = 0; byte < KEEP_WIDTH; ++byte) {
            if (keep[byte]) {
                packet.push_back((uint8_t)data.bits(byte * 8 + 7, byte * 8));
            }
        }
    }

    static void consume(std::deque<Packet>& queue, uint32_t bytes)
    {
        while (bytes != 0 && !queue.empty()) {
            Packet& packet = queue.front();
            const uint32_t consumed = std::min<uint32_t>(bytes, packet.size());
            packet.erase(packet.begin(), packet.begin() + consumed);
            bytes -= consumed;
            if (packet.empty()) queue.pop_front();
        }
    }

    PacketList channel_packets() const
    {
        PacketList packets;
        Packet current;
        const size_t end = std::min(loaded_beats, source_beats.size());
        const uint64_t total_beats = (uint64_t)source_beats.size()
            * source_repeats;
        if (source_beats.empty() || emitted_beats >= total_beats) return packets;
        // The hardware generator retains one compact image and replays it.
        // Show the unconsumed tail of the current pass; it refills at the next
        // replay boundary instead of pretending all repeated beats are stored.
        const size_t begin = std::min<size_t>(emitted_beats
            % source_beats.size(), end);
        for (size_t index = begin; index < end; ++index) {
            const BEAT& beat = source_beats[index];
            for (size_t byte = 0; byte < DUT::NET_BYTES; ++byte) {
                if (beat.sop[byte] && !current.empty()) {
                    packets.push_back(std::move(current));
                    current.clear();
                }
                if (beat.keep[byte]) {
                    current.push_back((uint8_t)beat.data.bits(
                        byte * 8 + 7, byte * 8));
                }
                if (beat.eop[byte]) {
                    packets.push_back(std::move(current));
                    current.clear();
                }
            }
        }
        if (!current.empty()) packets.push_back(std::move(current));
        return packets;
    }

    static PacketList flatten(const std::deque<Packet>& packets)
    {
        return PacketList(packets.begin(), packets.end());
    }

    static PacketList flatten(const std::vector<Packet>& packets)
    {
        return packets;
    }

    template<size_t COUNT>
    static PacketList flatten_all(
        const std::array<std::deque<Packet>, COUNT>& queues)
    {
        PacketList result;
        for (const auto& queue : queues) {
            result.insert(result.end(), queue.begin(), queue.end());
        }
        return result;
    }

    static void panel(Canvas& image, Rect rect, std::string_view label,
        bool active = false)
    {
        image.fill(rect, PANEL);
        image.outline(rect, active ? ACTIVE : BORDER);
        image.text(rect.x + 3, rect.y + 2, label, TEXT);
        image.hline(rect.x + 1, rect.y + 8, rect.width - 2, GRID);
    }

    static void cpu_chip(Canvas& image, Rect rect)
    {
        // A stepped metallic gradient and two-pixel bevel make the cache group
        // read as one physical CPU chip behind its L2/I$/D$ sub-blocks.
        const int inner_height = rect.height - 4;
        for (int row = 0; row < inner_height; ++row) {
            const uint8_t shade = row < inner_height / 3
                ? Canvas::UI_OUTSIDE
                : (row < inner_height * 2 / 3
                    ? Canvas::UI_CHIP_MIDDLE : Canvas::UI_CHIP_BOTTOM);
            image.hline(rect.x + 2, rect.y + 2 + row,
                rect.width - 4, shade);
        }
        image.outline(rect, Canvas::UI_CHIP_BOTTOM);
        image.hline(rect.x + 1, rect.y + 1, rect.width - 2,
            Canvas::UI_PANEL);
        image.vline(rect.x + 1, rect.y + 1, rect.height - 2,
            Canvas::UI_PANEL);
        image.hline(rect.x + 1, rect.y + rect.height - 2,
            rect.width - 2, Canvas::UI_CHIP_BOTTOM);
        image.vline(rect.x + rect.width - 2, rect.y + 1,
            rect.height - 2, Canvas::UI_CHIP_BOTTOM);
    }

    static void packets(Canvas& image, Rect rect, const PacketList& list)
    {
        const int left = rect.x + 2;
        const int right = rect.x + rect.width - 2;
        int x = left;
        int y = rect.y + 10;
        const int bottom = rect.y + rect.height - 2;
        bool first = true;
        for (const Packet& packet : list) {
            if (!first) {
                if (x != left) { x = left; ++y; }
                if (y >= bottom) return;
                image.hline(left, y++, right - left, GRID);
            }
            first = false;
            for (size_t byte = 0; byte < packet.size(); byte += 2) {
                if (y >= bottom) return;
                const uint16_t word = packet[byte]
                    | (uint16_t)(byte + 1 < packet.size() ? packet[byte + 1] : 0)
                        << 8;
                image.pixel(x, y, Canvas::word_color(word));
                if (++x >= right) { x = left; ++y; }
            }
        }
    }

    template<size_t COUNT, class CONTAINER>
    static void partitioned(Canvas& image, Rect rect,
        const std::array<CONTAINER, COUNT>& contents)
    {
        const int top = rect.y + 9;
        const int available = rect.height - 10;
        for (size_t index = 0; index < COUNT; ++index) {
            const int y0 = top + (int)index * available / COUNT;
            const int y1 = top + (int)(index + 1) * available / COUNT;
            if (index != 0) image.hline(rect.x + 1, y0,
                rect.width - 2, GRID);
            Rect part{rect.x, y0 - 9, rect.width, y1 - y0 + 9};
            packets(image, part, flatten(contents[index]));
        }
    }

    static void cache(Canvas& image, Rect rect, const Packet& bytes,
        const std::vector<bool>& valid, uint32_t address)
    {
        const int left = rect.x + 2;
        const int top = rect.y + 10;
        const int columns = 16; // one visible row is one 32-byte cache line
        const int rows = std::max(0, rect.height - 12);
        const size_t words = std::min<size_t>(bytes.size() / 2,
            (size_t)columns * rows);
        for (size_t word = 0; word < words; ++word) {
            const size_t byte = word * 2;
            if (byte >= valid.size() || !valid[byte]) continue;
            const uint16_t value = bytes[byte]
                | (uint16_t)bytes[byte + 1] << 8;
            image.pixel(left + (int)(word % columns),
                top + (int)(word / columns), Canvas::word_color(value));
        }
        for (int row = 1; row < rows; ++row) {
            image.pixel(left + columns, top + row, GRID);
        }
        const uint32_t line = (address / 32u) % (uint32_t)std::max(1, rows);
        if (line < (uint32_t)rows) {
            image.pixel(left + columns + 1, top + (int)line, ACTIVE);
        }
    }

    void render(uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        canvas.clear(background_color);
        const Rect channel{3, 2, 43, 296};
        const Rect rx_fifo_rect{49, 2, 56, 146};
        const Rect tx_fifo_rect{49, 152, 56, 146};
        const Rect rx_ram_rect{108, 2, 106, 296};
        std::array<Rect, CLUSTERS> chip_rects{};
        std::array<Rect, CLUSTERS> l2_rects{};
        std::array<Rect, CLUSTERS> l1i_rects{};
        std::array<Rect, CLUSTERS> l1d_rects{};
        // Eight CPU chips are arranged as two columns of four. Each retains a
        // compact I$ above its larger D$ and a separate L2 view.
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            const int column = (int)(cluster / 4);
            const int row = (int)(cluster % 4);
            const int x = 216 + column * 110;
            const int y = 1 + row * 75;
            chip_rects[cluster] = Rect{x, y, 108, 73};
            l2_rects[cluster] = Rect{x + 4, y + 4, 32, 65};
            l1i_rects[cluster] = Rect{x + 39, y + 4, 65, 22};
            l1d_rects[cluster] = Rect{x + 39, y + 29, 65, 40};
        }
        const Rect rx_queue_rect{437, 2, 60, 146};
        const Rect tx_queue_rect{437, 152, 60, 146};

        panel(canvas, channel, ENABLE_800G ? "800G" : "400G");
        canvas.text(channel.x + 3, channel.y + 9, "CHANNEL", TEXT);
        packets(canvas, Rect{channel.x, channel.y + 7,
            channel.width, channel.height - 7}, channel_packets());

        panel(canvas, rx_fifo_rect, "RX FIFO");
        partitioned(canvas, rx_fifo_rect, rx_fifo);
        panel(canvas, tx_fifo_rect, "TX FIFO");
        partitioned(canvas, tx_fifo_rect, tx_fifo);

        panel(canvas, rx_ram_rect, "RX RAM");
        partitioned(canvas, rx_ram_rect, rx_ram);

        for (const Rect& chip : chip_rects) cpu_chip(canvas, chip);
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            panel(canvas, l2_rects[cluster], std::format("L2 {}", cluster),
                l2_edge && l2_write_address_valid[cluster]);
            cache(canvas, l2_rects[cluster], l2_data[cluster],
                l2_valid[cluster], l2_write_address[cluster]
                    - l2_packet_base[cluster]);
            panel(canvas, l1i_rects[cluster],
                std::format("I$ {}", cluster));
            cache(canvas, l1i_rects[cluster], l1_instruction[cluster],
                l1_instruction_valid[cluster], l1_instruction_address[cluster]);
            // Cache contents change as lines are filled, but the panel frame is
            // intentionally static so CPU activity does not make it blink.
            panel(canvas, l1d_rects[cluster],
                std::format("D$ {}", cluster));
            cache(canvas, l1d_rects[cluster], l1_data[cluster],
                l1_data_valid[cluster], l1_data_address[cluster]);
        }

        // Do not key the border to the unrelated sys/net phase relationship;
        // that made this rectangle blink at the sampling cadence.
        panel(canvas, rx_queue_rect, "RX QUEUE");
        partitioned(canvas, rx_queue_rect, rx_queue);
        panel(canvas, tx_queue_rect, "TX QUEUE");
        partitioned(canvas, tx_queue_rect, tx_queue);

        const auto snapshot = [this](std::string_view suffix) {
            canvas.write_png(video_path.parent_path()
                / (video_path.stem().string() + std::string(suffix) + ".png"));
        };
        if (!loaded_snapshot_written && loaded_beats == source_beats.size()
            && emitted_beats == 0) {
            snapshot("_loaded");
            loaded_snapshot_written = true;
        }
        if (!mid_snapshot_written
            && completed_packets >= source_packets.size() / 2
            && completed_packets < source_packets.size()) {
            snapshot("_mid");
            mid_snapshot_written = true;
        }
        if (!queue_snapshot_written) {
            for (const auto& queue : rx_queue) {
                if (!queue.empty()) {
                    snapshot("_queue");
                    queue_snapshot_written = true;
                    break;
                }
            }
        }

        video.write(canvas);
#if DEMO_TRANSPARENT_VIDEO
        transparent_video.write(canvas);
#endif
        trace << video.frame_count() - 1 << ',' << ticks << ',' << net_cycles
              << ',' << cpu_cycles << ',' << l2_cycles << ',' << system_cycles
              << ',' << loaded_beats << ',' << emitted_beats << ','
              << completed_packets << ',' << host_consumer << '\n';
    }

public:
    Visualizer(const std::filesystem::path& path, const PacketList& packets,
        const std::vector<BEAT>& beats, const std::vector<uint8_t>& image,
        uint32_t repeats = 1, uint32_t fps = 120,
        uint8_t background = Canvas::UI_OUTSIDE)
        : source_packets(packets), source_beats(beats),
          source_repeats(repeats), firmware(image),
          video_path(path), video(path, fps),
#if DEMO_TRANSPARENT_VIDEO
          transparent_video(path.parent_path()
              / (path.stem().string() + "_transparent.png"), fps, background),
#endif
          background_color(background)
    {
        const std::filesystem::path trace_path = path.parent_path()
            / (path.stem().string() + ".csv");
        trace.open(trace_path);
        if (!trace) throw std::runtime_error("cannot create trace "
            + trace_path.string());
        trace << "video_frame,cpu_tick,net_cycle,cpu_cycle,l2_cycle,system_cycle,"
                 "loaded_beats,emitted_beats,rx_packets,host_consumer\n";
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            l2_data[cluster].assign(L2_VIEW_BYTES, 0);
            l2_valid[cluster].assign(L2_VIEW_BYTES, false);
            l2_packet_base[cluster] = PACKET_BUFFER;
            l1_instruction[cluster].assign(L1_VIEW_BYTES, 0);
            l1_instruction_valid[cluster].assign(L1_VIEW_BYTES, false);
            l1_data[cluster].assign(L1_VIEW_BYTES, 0);
            l1_data_valid[cluster].assign(L1_VIEW_BYTES, false);
        }
    }

    void observe_cpu_before(DUT& dut)
    {
        ++cpu_cycles;
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            auto& dma = dut.processing.packet_dma[cluster].l2_dma;
            const uint32_t completed = (uint32_t)dut.processing
                .packet_dma[cluster].completed_count_out();
            if (completed != last_dma_completed[cluster]) {
                last_dma_completed[cluster] = completed;
                // Operations alternate NETWORK_CPU then CPU_SYSTEM. An even
                // completion is reachable only after the ten CPU prefix loads.
                if (completed != 0 && (completed & 1u) == 0) {
                    for (uint32_t byte = 0; byte < 64; ++byte) {
                        l1_data[cluster][byte] = l2_data[cluster][byte];
                        l1_data_valid[cluster][byte] = l2_valid[cluster][byte];
                    }
                    l1_data_address[cluster] = 36;
                    l1_touch_completed[cluster] = true;
                }
            }
            if (l1_touch_completed[cluster] && completed != 0
                && (completed & 1u) == 0) {
                for (uint32_t byte = 0; byte < 64; ++byte) {
                    l1_data[cluster][byte] = l2_data[cluster][byte];
                    l1_data_valid[cluster][byte] = l2_valid[cluster][byte];
                }
            }
            if (dma.awvalid_out() && dma.awready_in()) {
                const uint32_t address = (uint32_t)dma.awaddr_out();
                if (!l2_previous_write_valid[cluster]
                    || address != l2_previous_write_address[cluster] + 32u) {
                    l2_packet_base[cluster] = address;
                    std::fill(l2_data[cluster].begin(), l2_data[cluster].end(), 0);
                    std::fill(l2_valid[cluster].begin(), l2_valid[cluster].end(),
                        false);
                    l1_touch_completed[cluster] = false;
                }
                l2_write_address[cluster] = address;
                l2_previous_write_address[cluster] = address;
                l2_previous_write_valid[cluster] = true;
                l2_write_address_valid[cluster] = true;
            }
            if (dma.wvalid_out() && dma.wready_in()
                && l2_write_address_valid[cluster]) {
                const uint32_t address = l2_write_address[cluster];
                if (address >= l2_packet_base[cluster]
                    && address < l2_packet_base[cluster] + L2_VIEW_BYTES) {
                    const uint32_t offset = address - l2_packet_base[cluster];
                    for (uint32_t byte = 0; byte < 32; ++byte) {
                        if (dma.wstrb_out()[byte]
                            && offset + byte < L2_VIEW_BYTES) {
                            l2_data[cluster][offset + byte] =
                                (uint8_t)dma.wdata_out().bits(
                                    byte * 8 + 7, byte * 8);
                            l2_valid[cluster][offset + byte] = true;
                        }
                    }
                }
                l2_write_address_valid[cluster] = false;
            }
            for (uint32_t core = 0; core < 4; ++core) {
                const TribeCacheDebug cache_debug = dut.processing
                    .cpu[cluster].demo_cache_debug(core);
                const uint32_t instruction = cache_debug.icache_read_addr;
                l1_instruction_address[cluster] = instruction;
                const uint32_t line = instruction & ~31u;
                if (line < L1_VIEW_BYTES && line < firmware.size()) {
                    for (uint32_t byte = 0; byte < 32
                        && line + byte < L1_VIEW_BYTES
                        && line + byte < firmware.size(); ++byte) {
                        l1_instruction[cluster][line + byte] = firmware[line + byte];
                        l1_instruction_valid[cluster][line + byte] = true;
                    }
                }
                if (cache_debug.dcache_cpu_read
                    || cache_debug.dcache_cpu_write) {
                    const uint32_t address = cache_debug.dcache_cpu_addr;
                    if (address >= l2_packet_base[cluster]
                        && address < l2_packet_base[cluster] + L1_VIEW_BYTES) {
                        const uint32_t packet_offset =
                            address - l2_packet_base[cluster];
                        l1_data_address[cluster] = packet_offset;
                        const uint32_t line_address = packet_offset & ~31u;
                        for (uint32_t byte = 0; byte < 32
                            && line_address + byte < L1_VIEW_BYTES; ++byte) {
                            l1_data[cluster][line_address + byte] =
                                l2_data[cluster][line_address + byte];
                            l1_data_valid[cluster][line_address + byte] =
                                l2_valid[cluster][line_address + byte];
                        }
                    }
                    else if (address < L1_VIEW_BYTES) {
                        l1_data_address[cluster] = address;
                        const uint32_t line_address = address & ~31u;
                        for (uint32_t byte = 0; byte < 32
                            && line_address + byte < L1_VIEW_BYTES; ++byte) {
                            if (line_address + byte < firmware.size()) {
                                l1_data[cluster][line_address + byte] =
                                    firmware[line_address + byte];
                                l1_data_valid[cluster][line_address + byte] = true;
                            }
                        }
                    }
                }
            }
        }
    }

    void observe_l2_before(DUT& dut)
    {
        ++l2_cycles;
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            if (dut.processing.rx_read_valid_out()[cluster]
                && dut.processing.rx_read_ready_in()[cluster]
                && !rx_fifo[cluster].empty()) {
                rx_fifo[cluster].pop_front();
            }
            if (dut.system.l2_rx_valid_in()[cluster]
                && dut.system.l2_rx_ready_out()[cluster]) {
                if (dut.system.l2_rx_sop_in()[cluster]) {
                    rx_queue_assembling[cluster].clear();
                }
                const logic<256> data = dut.system.l2_rx_data_in().bits(
                    cluster * 256 + 255, cluster * 256);
                const logic<32> keep = dut.system.l2_rx_keep_in().bits(
                    cluster * 32 + 31, cluster * 32);
                append_beat(rx_queue_assembling[cluster], data, keep);
                if (dut.system.l2_rx_eop_in()[cluster]) {
                    rx_queue[cluster].push_back(
                        std::move(rx_queue_assembling[cluster]));
                    rx_queue_assembling[cluster].clear();
                }
            }
            if (dut.smartnic.l2_tx_valid_in()[cluster]
                && dut.smartnic.l2_tx_ready_out()[cluster]) {
                if (dut.smartnic.l2_tx_sop_in()[cluster]) {
                    tx_fifo_assembling[cluster].clear();
                }
                append_beat(tx_fifo_assembling[cluster],
                    (logic<256>)dut.smartnic.l2_tx_data_in().bits(
                        cluster * 256 + 255, cluster * 256),
                    (logic<32>)dut.smartnic.l2_tx_keep_in().bits(
                        cluster * 32 + 31, cluster * 32));
                if (dut.smartnic.l2_tx_eop_in()[cluster]) {
                    tx_fifo[cluster].push_back(
                        std::move(tx_fifo_assembling[cluster]));
                    tx_fifo_assembling[cluster].clear();
                }
            }
        }
    }

    void observe_system_before(DUT& dut)
    {
        ++system_cycles;
#if !HOST_AXI4
        if (dut.system.host_dma_out.write_in()
            && !dut.system.host_dma_out.waitrequest_out()) {
            const uint64_t address = dut.system.host_dma_out.address_in();
            if (address >= HOST_PACKET_BASE) {
                const uint32_t slot = (uint32_t)((address - HOST_PACKET_BASE)
                    / HOST_PACKET_STRIDE);
                const uint32_t queue = slot % CLUSTERS;
                uint32_t bytes = 0;
                for (uint32_t byte = 0; byte < HOST_DATA_WIDTH / 8; ++byte) {
                    if (dut.system.host_dma_out.byteenable_in()[byte]) ++bytes;
                }
                consume(rx_queue[queue], bytes);
            }
        }
#endif
    }

    void observe_net_before(DUT& dut)
    {
        ++net_cycles;
        if (dut.traffic.load_valid_in() && dut.traffic.load_ready_out()
            && loaded_beats < source_beats.size()) {
            ++loaded_beats;
        }
        if (!dut.traffic.valid_out()) return;
        const uint64_t total_beats = (uint64_t)source_beats.size()
            * source_repeats;
        if (emitted_beats < total_beats) ++emitted_beats;
        uint32_t completions = 0;
        for (uint32_t byte = 0; byte < DUT::NET_BYTES; ++byte) {
            if (dut.traffic.eop_out()[byte]) ++completions;
        }
        for (uint32_t completion = 0; completion < completions
            && completed_packets < source_packets.size(); ++completion) {
            const Packet& packet = source_packets[completed_packets];
            const uint32_t stream = completed_packets % QUEUES;
            const uint32_t cluster = completed_packets % CLUSTERS;
            rx_ram[stream].push_back(packet);
            rx_fifo[cluster].push_back(
                descriptor_for(packet, (uint32_t)completed_packets));
            ++completed_packets;
        }
    }

    void frame(uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        render(ticks, host_consumer, l2_edge, system_edge);
    }

    void finish()
    {
        video.finish();
        trace.flush();
        const std::filesystem::path preview = video_path.parent_path()
            / (video_path.stem().string() + "_final.ppm");
        canvas.write_ppm(preview);
        canvas.write_bmp(video_path.parent_path()
            / (video_path.stem().string() + "_final.bmp"));
        canvas.write_png(video_path.parent_path()
            / (video_path.stem().string() + "_final.png"));
    }

    uint32_t frame_count() const { return video.frame_count(); }
};

} // namespace smartnic_demo
