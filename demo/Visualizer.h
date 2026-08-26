#pragma once

// Visualization-only mirrors driven by real SmartNIC public handshakes. No
// synthesis state is exposed or modified: the mirrors observe generator load
// and emission, descriptor/RxRAM completion, PacketDMA coherent AXI writes,
// CPU instruction/data accesses, System queue traffic, and host DMA drains.

#include "Video.h"
#include "../Config.h"

#include <algorithm>
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
    static constexpr uint32_t CORES = CPU::CORES;
    static constexpr uint32_t TOTAL_CORES = CLUSTERS * CORES;
    static constexpr uint32_t L2_VIEW_BYTES = CPU::L2_BYTES;
    static constexpr uint32_t L1I_VIEW_BYTES = CPU::L1I_BYTES;
    static constexpr uint32_t L1D_VIEW_BYTES = CPU::L1D_BYTES;
    static constexpr uint32_t PACKET_BUFFER = 0x00010000;
    static constexpr uint32_t PACKET_SLOT_BYTES = 2048;
    static constexpr uint32_t PACKET_SLOT_COUNT = 512;
    static constexpr uint32_t DDR_VIEW_COLUMNS = 92;
    static constexpr uint32_t DDR_VIEW_ROWS = 106;
    static constexpr uint32_t DDR_VIEW_PIXELS =
        DDR_VIEW_COLUMNS * DDR_VIEW_ROWS;
    static constexpr uint32_t CHANNEL_VIEW_COLUMNS = 71;
    static constexpr uint32_t CHANNEL_VIEW_ROWS = 342;
    static constexpr uint32_t CHANNEL_VIEW_PIXELS =
        CHANNEL_VIEW_COLUMNS * CHANNEL_VIEW_ROWS;
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
    std::vector<uint16_t> channel_data;
    std::vector<bool> channel_valid;
    size_t channel_write_word = 0;

    struct RxRamPacket
    {
        uint32_t handle = 0;
        Packet data;
    };

    std::array<std::vector<RxRamPacket>, QUEUES> rx_ram;
    std::array<std::deque<Packet>, QUEUES> rx_ram_pending;
    std::array<std::deque<Packet>, CLUSTERS> rx_fifo;
    std::array<Packet, CLUSTERS> rx_fifo_assembling;
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
    std::array<Packet, TOTAL_CORES> l1_instruction;
    std::array<std::vector<bool>, TOTAL_CORES> l1_instruction_valid;
    std::array<Packet, TOTAL_CORES> l1_data;
    std::array<std::vector<bool>, TOTAL_CORES> l1_data_valid;
    std::array<uint32_t, TOTAL_CORES> l1_instruction_address{};
    std::array<uint32_t, TOTAL_CORES> l1_data_address{};
    std::array<uint8_t, TOTAL_CORES> l1_activity{};
    std::array<std::vector<uint16_t>, CLUSTERS> ddr_data;
    std::array<std::vector<bool>, CLUSTERS> ddr_valid;
    bool loaded_snapshot_written = false;
    bool mid_snapshot_written = false;
    bool queue_snapshot_written = false;

    static constexpr uint8_t BLACK = Canvas::rgb332(0, 0, 0);
    static constexpr uint8_t PANEL = Canvas::UI_PANEL;
    static constexpr uint8_t BORDER = Canvas::UI_BORDER;
    static constexpr uint8_t GRID = Canvas::UI_GRID;
    static constexpr uint8_t TEXT = Canvas::UI_TEXT;
    static constexpr uint8_t ACTIVE = Canvas::UI_ACTIVE;

    static uint32_t l2_physical_offset(uint32_t address)
    {
        constexpr uint32_t line_bytes = CPU::CACHE_LINE_BYTES;
        constexpr uint32_t sets = CPU::L2_BYTES
            / line_bytes / CPU::L2_WAYS;
        const uint32_t line = address / line_bytes;
        const uint32_t set = line % sets;
        const uint32_t way = (line / sets) % CPU::L2_WAYS;
        return (way * sets + set) * line_bytes;
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

    static void channel_memory(Canvas& image, Rect rect,
        const std::vector<uint16_t>& data, const std::vector<bool>& valid,
        size_t write_word)
    {
        const int left = rect.x + 2;
        const int top = rect.y + 10;
        const int columns = std::max(1, rect.width - 4);
        const int rows = std::max(1, rect.height - 12);
        const size_t pixels = std::min(data.size(),
            (size_t)columns * rows);
        for (size_t pixel = 0; pixel < pixels; ++pixel) {
            if (pixel < valid.size() && valid[pixel]) {
                image.pixel(left + (int)(pixel % columns),
                    top + (int)(pixel / columns),
                    Canvas::word_color(data[pixel]));
            }
        }
        if (pixels != 0) {
            const size_t cursor = write_word % pixels;
            image.pixel(left + (int)(cursor % columns),
                top + (int)(cursor / columns), ACTIVE);
        }
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
        const int top = rect.y + 10;
        const int bottom = rect.y + rect.height - 2;
        const int columns = std::max(0, right - left);
        const int rows = std::max(0, bottom - top);
        const size_t pixels = (size_t)columns * rows;
        size_t source_words = 0;
        for (const Packet& packet : list) {
            source_words += (packet.size() + 1) / 2;
        }
        if (pixels == 0 || source_words == 0) return;

        // Map two bytes to each pixel while the panel has room. If it fills,
        // fold the complete contents proportionally instead of truncating the
        // newest packets or inserting the old five-pixel visual spacing.
        std::vector<uint16_t> values(pixels, 0);
        std::vector<bool> occupied(pixels, false);
        std::vector<size_t> boundaries;
        size_t source_word = 0;
        for (const Packet& packet : list) {
            if (source_word != 0) boundaries.push_back(source_word);
            for (size_t byte = 0; byte < packet.size(); byte += 2) {
                const uint16_t word = packet[byte]
                    | (uint16_t)(byte + 1 < packet.size() ? packet[byte + 1] : 0)
                        << 8;
                const size_t pixel = source_words <= pixels
                    ? source_word
                    : std::min(pixels - 1,
                        source_word * pixels / source_words);
                occupied[pixel] = true;
                if (word != 0 || values[pixel] == 0) values[pixel] = word;
                ++source_word;
            }
        }
        for (size_t pixel = 0; pixel < pixels; ++pixel) {
            if (occupied[pixel]) image.pixel(left + (int)(pixel % columns),
                top + (int)(pixel / columns), Canvas::word_color(values[pixel]));
        }
        for (const size_t boundary : boundaries) {
            const size_t pixel = source_words <= pixels
                ? std::min(pixels - 1, boundary)
                : std::min(pixels - 1, boundary * pixels / source_words);
            image.pixel(left + (int)(pixel % columns),
                top + (int)(pixel / columns), GRID);
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
        const int columns = std::min(32, std::max(1, rect.width - 6));
        const int rows = std::max(0, rect.height - 12);
        const size_t source_words = bytes.size() / 2;
        const size_t pixels = (size_t)columns * rows;
        // Compress the complete cache capacity into the panel. Every source
        // range contributes; valid nonzero data wins when several words fold
        // into one destination pixel.
        for (size_t pixel = 0; pixel < pixels && source_words != 0; ++pixel) {
            const size_t begin = pixel * source_words / pixels;
            const size_t end = std::max(begin + 1,
                (pixel + 1) * source_words / pixels);
            bool occupied = false;
            uint16_t value = 0;
            for (size_t word = begin; word < end && word < source_words;
                ++word) {
                const size_t byte = word * 2;
                if (byte + 1 >= valid.size() || !valid[byte]) continue;
                const uint16_t candidate = bytes[byte]
                    | (uint16_t)bytes[byte + 1] << 8;
                occupied = true;
                if (candidate != 0 || value == 0) value = candidate;
            }
            if (occupied) image.pixel(left + (int)(pixel % columns),
                top + (int)(pixel / columns), Canvas::word_color(value));
        }
        if (source_words != 0 && pixels != 0) {
            const size_t active_word = (address % bytes.size()) / 2;
            const size_t active_pixel = std::min(pixels - 1,
                active_word * pixels / source_words);
            image.pixel(left + (int)(active_pixel % columns),
                top + (int)(active_pixel / columns), ACTIVE);
        }
    }

    static void ddr_memory(Canvas& image, Rect rect,
        const std::vector<uint16_t>& data, const std::vector<bool>& valid)
    {
        const int left = rect.x + 2;
        const int top = rect.y + 10;
        const int columns = std::max(1, rect.width - 4);
        const int rows = std::max(1, rect.height - 12);
        const size_t pixels = (size_t)columns * rows;
        // The mirror is updated only on accepted writes at the native DDR
        // port. Rendering is therefore proportional to image pixels rather
        // than rescanning eight complete 1 MiB rings for every video frame.
        for (size_t pixel = 0;
            pixel < pixels && pixel < data.size(); ++pixel) {
            if (pixel < valid.size() && valid[pixel]) {
                image.pixel(left + (int)(pixel % columns),
                    top + (int)(pixel / columns),
                    Canvas::word_color(data[pixel]));
            }
        }
    }

    static void rx_ram_memory(Canvas& image, Rect rect,
        const std::array<std::vector<RxRamPacket>, QUEUES>& contents)
    {
        constexpr size_t capacity_bytes = RX_RAM_BANK_DEPTH * 2
            * (NET_LANE_WIDTH / 8);
        constexpr size_t capacity_words = capacity_bytes / 2;
        const int top = rect.y + 9;
        const int available = rect.height - 10;
        for (size_t stream = 0; stream < QUEUES; ++stream) {
            const int y0 = top + (int)stream * available / QUEUES;
            const int y1 = top + (int)(stream + 1) * available / QUEUES;
            if (stream != 0) image.hline(rect.x + 1, y0,
                rect.width - 2, GRID);
            const int left = rect.x + 2;
            const int columns = std::max(1, rect.width - 4);
            const int rows = std::max(1, y1 - y0 - 1);
            const size_t pixels = (size_t)columns * rows;
            std::vector<uint16_t> values(pixels, 0);
            std::vector<bool> valid(pixels, false);

            // A handle contains the fixed logical start row above its low
            // three stream bits. Map every byte from that physical circular
            // address into a fixed pixel bucket. Occupancy changes therefore
            // affect only the released/allocated address ranges.
            for (const RxRamPacket& packet : contents[stream]) {
                const size_t start_byte = (packet.handle >> 3)
                    * (NET_LANE_WIDTH / 8);
                for (size_t byte = 0; byte < packet.data.size(); byte += 2) {
                    const size_t physical = (start_byte + byte)
                        % capacity_bytes;
                    const size_t word = physical / 2;
                    const size_t pixel = std::min(pixels - 1,
                        word * pixels / capacity_words);
                    const uint16_t value = packet.data[byte]
                        | (uint16_t)(byte + 1 < packet.data.size()
                            ? packet.data[byte + 1] : 0) << 8;
                    valid[pixel] = true;
                    if (value != 0 || values[pixel] == 0)
                        values[pixel] = value;
                }
            }
            for (size_t pixel = 0; pixel < pixels; ++pixel) {
                if (valid[pixel]) image.pixel(
                    left + (int)(pixel % columns),
                    y0 + 1 + (int)(pixel / columns),
                    Canvas::word_color(values[pixel]));
            }
        }
    }

    void render(DUT& dut, uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        canvas.clear(background_color);
        const Rect channel{3, 2, 75, 354};
        const Rect rx_fifo_rect{81, 2, 83, 172};
        const Rect tx_fifo_rect{81, 178, 83, 178};
        const Rect rx_ram_rect{167, 2, 112, 354};
        std::array<Rect, CLUSTERS> chip_rects{};
        std::array<Rect, CLUSTERS> l2_rects{};
        std::array<Rect, TOTAL_CORES> core_rects{};
        std::array<Rect, TOTAL_CORES> l1i_rects{};
        std::array<Rect, TOTAL_CORES> l1d_rects{};
        // Eight beveled CPU packages use a 2x4 layout. Inside every package,
        // its four cores form one horizontal row beside the shared L2.
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            const int column = (int)(cluster & 1u);
            const int row = (int)(cluster / 2u);
            const int x = 282 + column * 207;
            const int y = 2 + row * 89;
            chip_rects[cluster] = Rect{x, y, 204, 86};
            l2_rects[cluster] = Rect{x + 4, y + 13, 44, 69};
            for (uint32_t core = 0; core < CORES; ++core) {
                const uint32_t index = cluster * CORES + core;
                const int core_x = x + 51 + (int)core * 37;
                core_rects[index] = Rect{core_x, y + 13, 35, 69};
                l1i_rects[index] = Rect{core_x + 2, y + 16, 31, 20};
                l1d_rects[index] = Rect{core_x + 2, y + 39, 31, 40};
            }
        }
        const Rect rx_queue_rect{699, 2, 98, 172};
        const Rect tx_queue_rect{699, 178, 98, 178};
        std::array<Rect, CLUSTERS> ddr_rects{};
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            ddr_rects[cluster] = Rect{3 + (int)cluster * 99, 360, 96, 118};
        }

        panel(canvas, channel, ENABLE_800G ? "800G" : "400G");
        canvas.text(channel.x + 3, channel.y + 9, "CHANNEL", TEXT);
        channel_memory(canvas, channel, channel_data, channel_valid,
            channel_write_word);

        panel(canvas, rx_fifo_rect, "RX FIFO");
        partitioned(canvas, rx_fifo_rect, rx_fifo);
        panel(canvas, tx_fifo_rect, "TX FIFO");
        partitioned(canvas, tx_fifo_rect, tx_fifo);

        panel(canvas, rx_ram_rect, "RX RAM");
        rx_ram_memory(canvas, rx_ram_rect, rx_ram);

        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            cpu_chip(canvas, chip_rects[cluster]);
            canvas.text(chip_rects[cluster].x + 6,
                chip_rects[cluster].y + 4,
                std::format("CPU {} / 4 CORES", cluster), TEXT);
            panel(canvas, l2_rects[cluster], std::format("L2 {}", cluster),
                l2_edge && l2_write_address_valid[cluster]);
            cache(canvas, l2_rects[cluster], l2_data[cluster],
                l2_valid[cluster], l2_physical_offset(
                    l2_write_address[cluster]));
            for (uint32_t core = 0; core < CORES; ++core) {
                const uint32_t index = cluster * CORES + core;
                cpu_chip(canvas, core_rects[index]);
                panel(canvas, l1i_rects[index],
                    std::format("{}I", core));
                cache(canvas, l1i_rects[index], l1_instruction[index],
                    l1_instruction_valid[index],
                    l1_instruction_address[index]);
                panel(canvas, l1d_rects[index],
                    std::format("{}D", core), l1_activity[index] != 0);
                cache(canvas, l1d_rects[index], l1_data[index],
                    l1_data_valid[index], l1_data_address[index]);
                if (l1_activity[index] != 0) --l1_activity[index];
            }
        }

        // Do not key the border to the unrelated sys/net phase relationship;
        // that made this rectangle blink at the sampling cadence.
        panel(canvas, rx_queue_rect, "RX QUEUE");
        // This must be the live queue model. Keeping the two most recently
        // observed packets here made completed host DMA traffic look stalled.
        partitioned(canvas, rx_queue_rect, rx_queue);
        panel(canvas, tx_queue_rect, "TX QUEUE");
        partitioned(canvas, tx_queue_rect, tx_queue);
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            panel(canvas, ddr_rects[cluster],
                std::format("DDR{} 1M RING", cluster));
            ddr_memory(canvas, ddr_rects[cluster], ddr_data[cluster],
                ddr_valid[cluster]);
        }

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
        size_t rx_queue_packets = 0;
        size_t rx_queue_bytes = 0;
        for (const auto& queue : rx_queue) {
            rx_queue_packets += queue.size();
            for (const auto& packet : queue) rx_queue_bytes += packet.size();
        }
        trace << video.frame_count() - 1 << ',' << ticks << ',' << net_cycles
              << ',' << cpu_cycles << ',' << l2_cycles << ',' << system_cycles
              << ',' << loaded_beats << ',' << emitted_beats << ','
              << completed_packets << ',' << host_consumer << ','
              << rx_queue_packets << ',' << rx_queue_bytes << '\n';
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
        // Capture constructs the observer after loading the compact generator
        // image, immediately before releasing traffic.
        loaded_beats = source_beats.size();
        const std::filesystem::path trace_path = path.parent_path()
            / (path.stem().string() + ".csv");
        trace.open(trace_path);
        if (!trace) throw std::runtime_error("cannot create trace "
            + trace_path.string());
        trace << "video_frame,cpu_tick,net_cycle,cpu_cycle,l2_cycle,system_cycle,"
                 "loaded_beats,emitted_beats,rx_packets,host_consumer,"
                 "rx_queue_packets,rx_queue_bytes\n";
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            l2_data[cluster].assign(L2_VIEW_BYTES, 0);
            l2_valid[cluster].assign(L2_VIEW_BYTES, false);
            l2_packet_base[cluster] = PACKET_BUFFER;
            ddr_data[cluster].assign(DDR_VIEW_PIXELS, 0);
            ddr_valid[cluster].assign(DDR_VIEW_PIXELS, false);
        }
        channel_data.assign(CHANNEL_VIEW_PIXELS, 0);
        channel_valid.assign(CHANNEL_VIEW_PIXELS, false);
        for (uint32_t index = 0; index < TOTAL_CORES; ++index) {
            l1_instruction[index].assign(L1I_VIEW_BYTES, 0);
            l1_instruction_valid[index].assign(L1I_VIEW_BYTES, false);
            l1_data[index].assign(L1D_VIEW_BYTES, 0);
            l1_data_valid[index].assign(L1D_VIEW_BYTES, false);
        }
    }

    void observe_cpu_before(DUT& dut)
    {
        ++cpu_cycles;
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            if (dut.processing.demo_descriptor_command_fire(cluster)
                && !rx_fifo[cluster].empty()) {
                rx_fifo[cluster].pop_front();
            }
            auto& memory = dut.cpu_memory_adapter[cluster];
            if (memory.ddr_valid_out() && memory.ddr_write_out()
                && memory.ddr_ready_in()) {
                constexpr uint32_t ring_bytes =
                    PACKET_SLOT_BYTES * PACKET_SLOT_COUNT;
                constexpr size_t source_words = ring_bytes / 2;
                const uint32_t address = (uint32_t)memory.ddr_address_out();
                for (uint32_t byte = 0; byte < DUT::DDR_WIDTH / 8;
                    byte += 2) {
                    const uint32_t current = address + byte;
                    if (current < PACKET_BUFFER
                        || current + 1 >= PACKET_BUFFER + ring_bytes)
                        continue;
                    if (!memory.ddr_byteenable_out()[byte]
                        && !memory.ddr_byteenable_out()[byte + 1])
                        continue;
                    const uint16_t value =
                        (memory.ddr_byteenable_out()[byte]
                            ? (uint16_t)memory.ddr_writedata_out().bits(
                                byte * 8 + 7, byte * 8) : 0)
                        | (memory.ddr_byteenable_out()[byte + 1]
                            ? (uint16_t)memory.ddr_writedata_out().bits(
                                byte * 8 + 15, byte * 8 + 8) << 8 : 0);
                    const size_t word = (current - PACKET_BUFFER) / 2;
                    const size_t pixel = std::min<size_t>(
                        DDR_VIEW_PIXELS - 1,
                        word * DDR_VIEW_PIXELS / source_words);
                    if (value != 0 || !ddr_valid[cluster][pixel])
                        ddr_data[cluster][pixel] = value;
                    ddr_valid[cluster][pixel] = true;
                }
            }
            auto& packet_dma = dut.processing.packet_dma[cluster];
            if (packet_dma.l2_line_valid_out()
                && packet_dma.l2_line_ready_in()) {
                const uint32_t address =
                    (uint32_t)packet_dma.l2_line_addr_out();
                l2_write_address[cluster] = address;
                l2_previous_write_address[cluster] = address;
                l2_previous_write_valid[cluster] = true;
                const uint32_t physical = l2_physical_offset(address);
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (packet_dma.l2_line_keep_out()[byte]
                        && physical + byte < L2_VIEW_BYTES) {
                        l2_data[cluster][physical + byte] =
                            (uint8_t)packet_dma.l2_line_data_out().bits(
                                byte * 8 + 7, byte * 8);
                        l2_valid[cluster][physical + byte] = true;
                    }
                }
            }
            auto& dma = dut.processing.packet_dma[cluster].l2_dma;
            if (dma.awvalid_out() && dma.awready_in()) {
                const uint32_t address = (uint32_t)dma.awaddr_out();
                l2_write_address[cluster] = address;
                l2_previous_write_address[cluster] = address;
                l2_previous_write_valid[cluster] = true;
                l2_write_address_valid[cluster] = true;
            }
            if (dma.wvalid_out() && dma.wready_in()
                && l2_write_address_valid[cluster]) {
                const uint32_t address = l2_write_address[cluster];
                const uint32_t physical = l2_physical_offset(address);
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (dma.wstrb_out()[byte]
                        && physical + byte < L2_VIEW_BYTES) {
                        l2_data[cluster][physical + byte] =
                            (uint8_t)dma.wdata_out().bits(
                                byte * 8 + 7, byte * 8);
                        l2_valid[cluster][physical + byte] = true;
                    }
                }
                l2_write_address_valid[cluster] = false;
            }
            for (uint32_t core = 0; core < CORES; ++core) {
                const uint32_t index = cluster * CORES + core;
                const TribeCacheDebug cache_debug = dut.processing
                    .cpu[cluster].demo_cache_debug(core);
                const uint32_t instruction = cache_debug.icache_read_addr;
                l1_instruction_address[index] = instruction;
                const uint32_t line = instruction & ~31u;
                const uint32_t physical_i = line % L1I_VIEW_BYTES;
                if (line < firmware.size()) {
                    for (uint32_t byte = 0; byte < 32
                        && physical_i + byte < L1I_VIEW_BYTES
                        && line + byte < firmware.size(); ++byte) {
                        l1_instruction[index][physical_i + byte] =
                            firmware[line + byte];
                        l1_instruction_valid[index][physical_i + byte] = true;
                    }
                }
                if (cache_debug.dcache_cpu_read
                    || cache_debug.dcache_cpu_write) {
                    const uint32_t address = cache_debug.dcache_cpu_addr;
                    l1_activity[index] = 8;
                    if (address < DUT::DDR_BYTES) {
                        l1_data_address[index] = address;
                        const uint32_t line_address = address & ~31u;
                        const uint32_t physical_d =
                            line_address % L1D_VIEW_BYTES;
                        for (uint32_t byte = 0; byte < 32
                            && physical_d + byte < L1D_VIEW_BYTES; ++byte) {
                            l1_data[index][physical_d + byte] =
                                dut.cpu_memory_byte(cluster, line_address + byte);
                            l1_data_valid[index][physical_d + byte] = true;
                        }
                    }
                }
            }
        }
    }

    void observe_l2_before(DUT& dut)
    {
        ++l2_cycles;
        if (dut.processing.descriptor_valid_in()
            && dut.processing.descriptor_ready_out()) {
            const uint32_t cluster =
                dut.processing.demo_descriptor_target();
            if (cluster < CLUSTERS) {
                if (dut.processing.descriptor_sop_in())
                    rx_fifo_assembling[cluster].clear();
                const logic<256> word = dut.processing.descriptor_data_in();
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    rx_fifo_assembling[cluster].push_back(
                        (uint8_t)word.bits(byte * 8 + 7, byte * 8));
                }
                if (dut.processing.descriptor_eop_in()) {
                    rx_fifo[cluster].push_back(
                        std::move(rx_fifo_assembling[cluster]));
                    rx_fifo_assembling[cluster].clear();
                }
            }
        }
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
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
        if (dut.smartnic.demo_rx_descriptor_fire()) {
            const uint32_t handle =
                dut.smartnic.demo_rx_descriptor_handle();
            const uint32_t stream =
                dut.smartnic.demo_rx_descriptor_stream();
            if (stream < QUEUES && !rx_ram_pending[stream].empty()) {
                rx_ram[stream].push_back(RxRamPacket{
                    handle, std::move(rx_ram_pending[stream].front())});
                rx_ram_pending[stream].pop_front();
            }
        }
        for (uint32_t port = 0; port < CLUSTERS; ++port) {
            if (!dut.smartnic.demo_rx_release_fire(port)) continue;
            const uint32_t handle = dut.smartnic.demo_rx_release_handle(port);
            const uint32_t stream = handle & 7u;
            if (stream < QUEUES) {
                std::erase_if(rx_ram[stream], [handle](const RxRamPacket& item) {
                    return item.handle == handle;
                });
            }
        }
        if (dut.traffic.load_valid_in() && dut.traffic.load_ready_out()
            && loaded_beats < source_beats.size()) {
            ++loaded_beats;
        }
        if (!dut.traffic.valid_out()) return;
        // Record the live aggregate input at its native representation: one
        // pixel per two wire byte positions. A fixed circular address avoids
        // rescaling or shifting old data as the generator advances.
        for (uint32_t byte = 0; byte < DUT::NET_BYTES; byte += 2) {
            const size_t pixel = channel_write_word % CHANNEL_VIEW_PIXELS;
            const bool low_valid = dut.traffic.keep_out()[byte];
            const bool high_valid = byte + 1 < DUT::NET_BYTES
                && dut.traffic.keep_out()[byte + 1];
            channel_data[pixel] =
                (low_valid ? (uint16_t)dut.traffic.data_out().bits(
                    byte * 8 + 7, byte * 8) : 0)
                | (high_valid ? (uint16_t)dut.traffic.data_out().bits(
                    byte * 8 + 15, byte * 8 + 8) << 8 : 0);
            channel_valid[pixel] = low_valid || high_valid;
            ++channel_write_word;
        }
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
            rx_ram_pending[stream].push_back(packet);
            ++completed_packets;
        }
    }

    void frame(DUT& dut, uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        render(dut, ticks, host_consumer, l2_edge, system_edge);
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
