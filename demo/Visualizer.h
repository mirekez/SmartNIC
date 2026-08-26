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

#ifndef DEMO_L2_SWITCH
#define DEMO_L2_SWITCH 0
#endif
#ifndef DEMO_SWITCH_LEARNING_PACKETS
#define DEMO_SWITCH_LEARNING_PACKETS 20
#endif

namespace smartnic_demo
{

using Packet = std::vector<uint8_t>;
using PacketList = std::vector<Packet>;

template<class DUT, class BEAT>
class Visualizer
{
    static constexpr uint32_t NETWORK_STREAMS = NETWORK_PORTS;
    static constexpr uint32_t QUEUES = SYSTEM_QUEUES;
    static constexpr uint32_t CLUSTERS = CPUS_USED;
    static constexpr uint32_t CORES = 4;
    static constexpr uint32_t L2_VIEW_BYTES = CPU::L2_BYTES;
    static constexpr uint32_t L1I_VIEW_BYTES = CPU::L1I_BYTES;
    static constexpr uint32_t L1D_VIEW_BYTES = CPU::L1D_BYTES;
    static constexpr uint32_t PACKET_BUFFER = 0x00000000;
    static constexpr uint32_t PACKET_SLOT_BYTES = 2048;
    static constexpr uint32_t DMA_CLEAR_ADDRESS_MMIO = 0x40001038;
    // The lower half of simulation DDR is the complete 2 KiB-slot packet ring.
    static constexpr uint32_t PACKET_SLOT_COUNT =
        DUT::DDR_BYTES / 2 / PACKET_SLOT_BYTES;
    static constexpr uint32_t SWITCH_LEARNING_PACKETS =
        DEMO_SWITCH_LEARNING_PACKETS;
    static constexpr uint64_t HOST_PACKET_BASE = 0x00100000;
    static constexpr uint32_t HOST_PACKET_STRIDE = 2048;

    static_assert(CLUSTERS == 1,
        "the OpenSwitch demonstration layout shows one Tribe cluster");

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
    size_t l2_packets = 0;
    uint64_t net_cycles = 0;
    uint64_t cpu_cycles = 0;
    uint64_t l2_cycles = 0;
    uint64_t system_cycles = 0;
    uint32_t previous_host_consumer = 0;

    std::array<std::vector<Packet>, NETWORK_STREAMS> rx_ram;
    std::array<std::deque<Packet>, NETWORK_STREAMS> rx_fifo;
    std::array<std::deque<uint32_t>, NETWORK_STREAMS> rx_fifo_birth_frame;
    std::array<uint32_t, NETWORK_STREAMS> rx_fifo_pending_pop{};
    uint32_t descriptor_stream = 0;
    std::array<uint32_t, CLUSTERS> rx_read_stream{};
    std::array<std::deque<Packet>, NETWORK_STREAMS> tx_fifo;
    std::array<std::deque<uint32_t>, NETWORK_STREAMS> tx_fifo_birth_frame;
    std::array<uint32_t, NETWORK_STREAMS> tx_fifo_pending_pop{};
    // DMA-side assembly models entry into the Network TX path. MAC-side
    // assembly independently proves and retires the actual transmitted data.
    std::array<Packet, CLUSTERS> tx_dma_assembling;
    std::array<Packet, NETWORK_STREAMS> mac_tx_assembling;
    std::array<bool, NETWORK_STREAMS> mac_tx_in_frame{};
    std::array<uint32_t, NETWORK_STREAMS> mac_tx_port_packets{};
    uint32_t mac_tx_packets = 0;
    bool mac_tx_error = false;
    std::vector<bool> mac_tx_expected_matched;
    uint32_t rx_fifo_visible_frames = 0;
    uint32_t tx_fifo_visible_frames = 0;
    std::array<uint32_t, NETWORK_STREAMS> rx_fifo_port_visible_frames{};
    std::array<uint32_t, NETWORK_STREAMS> tx_fifo_port_visible_frames{};
    std::array<std::deque<Packet>, QUEUES> rx_queue;
    // Recent completed transfers remain visible across video decimation even
    // after the live System queue has drained to host memory.
    std::array<std::deque<Packet>, QUEUES> rx_queue_recent;
    std::array<Packet, QUEUES> rx_queue_assembling;
    std::array<std::deque<Packet>, QUEUES> tx_queue;

    std::array<Packet, CLUSTERS> l2_data;
    std::array<std::vector<bool>, CLUSTERS> l2_valid;
    // Physical shared-L2 data RAM image. Unlike l2_data (the current coherent
    // packet used by queue observers), this contains all 64 KiB and is what
    // the L2 rectangle renders.
    std::array<Packet, CLUSTERS> l2_full_data;
    std::array<std::vector<bool>, CLUSTERS> l2_full_valid;
    // Complete mirror of every coherent packet-ring slot. CPU processing
    // can lag the ingress DMA, so an L1 request must not be compared only with
    // the most recently filled slot displayed in the L2 panel.
    std::array<Packet, CLUSTERS> l2_slot_data;
    std::array<std::vector<bool>, CLUSTERS> l2_slot_valid;
    std::array<std::array<uint32_t, PACKET_SLOT_COUNT>, CLUSTERS>
        l2_slot_packet{};
    std::array<uint32_t, CLUSTERS> l2_packet_base{};
    std::array<uint32_t, CLUSTERS> l2_write_address{};
    std::array<uint32_t, CLUSTERS> l2_previous_write_address{};
    std::array<bool, CLUSTERS> l2_previous_write_valid{};
    std::array<bool, CLUSTERS> l2_write_address_valid{};
    std::array<Packet, CORES> l1_instruction;
    std::array<std::vector<bool>, CORES> l1_instruction_valid;
    std::array<Packet, CORES> l1_data;
    std::array<std::vector<bool>, CORES> l1_data_valid;
    // Last packet prefix actually requested by each core. This compact view
    // remains visible after the one-cycle L1 request pulse has completed.
    std::array<Packet, CORES> l1_packet_prefix;
    std::array<uint32_t, CORES> l1_instruction_address{};
    std::array<uint32_t, CORES> l1_data_address{};
    std::array<uint8_t, CORES> l1_data_activity{};
    std::array<uint32_t, CORES> packet_header_reads{};
    uint32_t max_simultaneous_packet_cores = 0;
    // CPU writes the exact packet-line address to PacketDMA before issuing a
    // clear. Pair those addresses with the real completed-response counter so
    // L2 changes become visible only after the line has reached DDR.
    std::deque<uint32_t> pending_clear_addresses;
    std::array<bool, CORES> clear_address_write_active{};
    uint32_t observed_clear_completions = 0;
    bool loaded_snapshot_written = false;
    bool mid_snapshot_written = false;
    bool queue_snapshot_written = false;
    bool tx_fifo_snapshot_written = false;
    bool clear_snapshot_written = false;

    static constexpr uint8_t BLACK = Canvas::rgb332(0, 0, 0);
    static constexpr uint8_t PANEL = Canvas::UI_PANEL;
    static constexpr uint8_t BORDER = Canvas::UI_BORDER;
    static constexpr uint8_t GRID = Canvas::UI_GRID;
    static constexpr uint8_t TEXT = Canvas::UI_TEXT;
    static constexpr uint8_t ACTIVE = Canvas::UI_ACTIVE;

    uint32_t expected_tx_packets() const
    {
        if constexpr (DEMO_L2_SWITCH) {
            return source_packets.size() > SWITCH_LEARNING_PACKETS
                ? ((uint32_t)source_packets.size() - SWITCH_LEARNING_PACKETS)
                    / DEMO_NETWORK_INTERVAL : 0;
        }
        return (uint32_t)source_packets.size() / DEMO_NETWORK_INTERVAL;
    }

    uint32_t expected_tx_source_index(uint32_t tx_index) const
    {
        if constexpr (DEMO_L2_SWITCH)
            return SWITCH_LEARNING_PACKETS
                + tx_index * DEMO_NETWORK_INTERVAL
                + DEMO_NETWORK_INTERVAL - 1;
        return tx_index * DEMO_NETWORK_INTERVAL
            + DEMO_NETWORK_INTERVAL - 1;
    }

    static Packet descriptor_for(const Packet& packet, uint32_t index)
    {
        Packet descriptor(160, 0);
        descriptor[0] = (uint8_t)index;
        descriptor[1] = (uint8_t)(index >> 8);
        descriptor[4] = (uint8_t)packet.size();
        descriptor[5] = (uint8_t)(packet.size() >> 8);
        descriptor[6] = (uint8_t)(index & 7u);
        descriptor[8] = (uint8_t)(index % NETWORK_STREAMS);
        const size_t copied = std::min<size_t>(128, packet.size());
        std::copy_n(packet.begin(), copied, descriptor.begin() + 32);
        return descriptor;
    }

    static uint32_t l2_physical_offset(uint32_t address)
    {
        constexpr uint32_t line_bytes = CPU::CACHE_LINE_BYTES;
        constexpr uint32_t sets = CPU::L2_BYTES
            / line_bytes / CPU::L2_WAYS;
        const uint32_t line = address / line_bytes;
        const uint32_t set = line % sets;
        const uint32_t tag = line / sets;
        const uint32_t way = tag % CPU::L2_WAYS;
        return (way * sets + set) * line_bytes;
    }

    void mirror_completed_clear(uint32_t cluster, uint32_t address)
    {
        if (address < PACKET_BUFFER
            || address + CPU::CACHE_LINE_BYTES
                > PACKET_BUFFER + PACKET_SLOT_BYTES * PACKET_SLOT_COUNT)
            return;
        const uint32_t slot_offset = address - PACKET_BUFFER;
        const uint32_t physical = l2_physical_offset(address);
        for (uint32_t byte = 0; byte < CPU::CACHE_LINE_BYTES; ++byte) {
            l2_slot_data[cluster][slot_offset + byte] = 0;
            l2_slot_valid[cluster][slot_offset + byte] = true;
            if (physical + byte < l2_full_data[cluster].size()) {
                l2_full_data[cluster][physical + byte] = 0;
                l2_full_valid[cluster][physical + byte] = true;
            }
            if (address >= l2_packet_base[cluster]
                && address + byte
                    < l2_packet_base[cluster] + l2_data[cluster].size()) {
                const uint32_t offset = address - l2_packet_base[cluster];
                l2_data[cluster][offset + byte] = 0;
                l2_valid[cluster][offset + byte] = true;
            }
        }
        l2_write_address[cluster] = address;
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

    PacketList channel_packets(uint32_t lane) const
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
            const size_t lane_bytes = DUT::NET_BYTES / NETWORK_STREAMS;
            for (size_t offset = 0; offset < lane_bytes; ++offset) {
                const size_t byte = lane * lane_bytes + offset;
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

    static void fifo_rows(Canvas& image, Rect rect,
        const std::array<std::deque<Packet>, NETWORK_STREAMS>& rx,
        const std::array<std::deque<Packet>, NETWORK_STREAMS>& tx)
    {
        const int top = rect.y + 9;
        const int available = rect.height - 10;
        for (uint32_t row = 0; row < NETWORK_STREAMS * 2; ++row) {
            const int y0 = top + (int)row * available
                / (NETWORK_STREAMS * 2);
            const int y1 = top + (int)(row + 1) * available
                / (NETWORK_STREAMS * 2);
            if (row != 0) image.hline(rect.x + 1, y0,
                rect.width - 2, GRID);
            const uint32_t port = row / 2;
            const bool receive = (row & 1u) == 0;
            image.text(rect.x + 3, y0 + 1,
                std::format("P{}{}", port, receive ? "R" : "T"), TEXT);
            Rect part{rect.x + 12, y0 - 7, rect.width - 12,
                y1 - y0 + 7};
            packets(image, part, flatten(receive ? rx[port] : tx[port]));
        }
    }

    void channel_rows(Canvas& image, Rect rect) const
    {
        const int top = rect.y + 9;
        const int available = rect.height - 10;
        for (uint32_t port = 0; port < NETWORK_STREAMS; ++port) {
            const int y0 = top + (int)port * available / NETWORK_STREAMS;
            const int y1 = top + (int)(port + 1) * available / NETWORK_STREAMS;
            if (port != 0) image.hline(rect.x + 1, y0,
                rect.width - 2, BORDER);
            image.text(rect.x + 3, y0 + 1,
                std::format("P{}", port), TEXT);
            Rect part{rect.x + 10, y0 - 7, rect.width - 10,
                y1 - y0 + 7};
            packets(image, part, channel_packets(port));
        }
    }

    static void ddr_memory(Canvas& image, Rect rect, const DUT& dut)
    {
        // The complete packet half is a grid of 4x4-pixel 2 KiB slots. The
        // left column of every slot is dedicated to its 32-byte header, so a
        // completed clear becomes a plainly visible four-pixel black bar.
        // The other twelve pixels fold the complete payload. The right half
        // retains linear whole-memory coverage for firmware/MAC hash data.
        constexpr uint32_t HALF_BYTES = DUT::DDR_BYTES / 2;
        const int top = rect.y + 10;
        const int columns = (rect.width - 7) / 2;
        const int packet_left = rect.x + 2;
        constexpr int CELL_WIDTH = 4;
        constexpr int CELL_HEIGHT = 4;
        const int slots_per_row = std::max(1, columns / CELL_WIDTH);
        for (uint32_t slot = 0; slot < PACKET_SLOT_COUNT; ++slot) {
            const int cell_x = packet_left
                + (int)(slot % slots_per_row) * CELL_WIDTH;
            const int cell_y = top
                + (int)(slot / slots_per_row) * CELL_HEIGHT;
            if (cell_y + CELL_HEIGHT > rect.y + rect.height - 2) break;
            const uint32_t base = slot * PACKET_SLOT_BYTES;
            bool packet_occupied = false;
            for (uint32_t byte = CPU::CACHE_LINE_BYTES;
                byte < PACKET_SLOT_BYTES; byte += 2) {
                packet_occupied |= dut.cpu_memory_byte(0, base + byte) != 0
                    || dut.cpu_memory_byte(0, base + byte + 1) != 0;
            }
            bool header_cleared = packet_occupied;
            for (uint32_t byte = 0;
                byte < CPU::CACHE_LINE_BYTES && header_cleared; ++byte)
                header_cleared &= dut.cpu_memory_byte(0, base + byte) == 0;

            // Four separately folded eight-byte header regions form the
            // slot's left bar until the entire first line becomes black.
            for (int row = 0; row < CELL_HEIGHT && packet_occupied; ++row) {
                uint16_t value = 0;
                for (uint32_t byte = (uint32_t)row * 8;
                    byte < (uint32_t)(row + 1) * 8; byte += 2) {
                    const uint16_t candidate =
                        dut.cpu_memory_byte(0, base + byte)
                        | (uint16_t)dut.cpu_memory_byte(0, base + byte + 1)
                            << 8;
                    if (candidate != 0 || value == 0) value = candidate;
                }
                image.pixel(cell_x, cell_y + row,
                    header_cleared ? BLACK : Canvas::word_color(value));
            }

            // The remaining 2016 bytes are divided across all twelve payload
            // pixels; no packet range is omitted from the image.
            constexpr uint32_t PAYLOAD_BYTES =
                PACKET_SLOT_BYTES - CPU::CACHE_LINE_BYTES;
            for (int pixel = 0; pixel < 12 && packet_occupied; ++pixel) {
                const uint32_t begin = CPU::CACHE_LINE_BYTES
                    + pixel * PAYLOAD_BYTES / 12;
                const uint32_t end = CPU::CACHE_LINE_BYTES
                    + (pixel + 1) * PAYLOAD_BYTES / 12;
                uint16_t value = 0;
                for (uint32_t byte = begin & ~1u; byte < end; byte += 2) {
                    const uint16_t candidate =
                        dut.cpu_memory_byte(0, base + byte)
                        | (uint16_t)dut.cpu_memory_byte(0, base + byte + 1)
                            << 8;
                    if (candidate != 0 || value == 0) value = candidate;
                }
                image.pixel(cell_x + 1 + pixel % 3,
                    cell_y + pixel / 3, Canvas::word_color(value));
            }
        }

        constexpr uint32_t LINE_BYTES = DUT::DDR_BYTES <= 1024 * 1024
            ? 64 : 128;
        constexpr uint32_t HALF_LINES = HALF_BYTES / LINE_BYTES;
        const int hash_left = rect.x + 2 + columns + 3;
        for (uint32_t line = 0; line < HALF_LINES; ++line) {
            const int x = hash_left + line % columns;
            const int y = top + line / columns;
            if (y >= rect.y + rect.height - 2) break;
            const uint32_t address = HALF_BYTES + line * LINE_BYTES;
            uint16_t value = 0;
            for (uint32_t byte = 0; byte < LINE_BYTES; byte += 2) {
                const uint16_t candidate =
                    dut.cpu_memory_byte(0, address + byte)
                    | (uint16_t)dut.cpu_memory_byte(0, address + byte + 1)
                        << 8;
                if (candidate != 0 || value == 0) value = candidate;
            }
            if (value != 0) image.pixel(x, y, Canvas::word_color(value));
        }
        image.vline(rect.x + rect.width / 2, top,
            rect.height - 12, GRID);
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

        // Fold the complete packet storage into the rectangle.  The old
        // renderer stopped at the bottom edge, which made a full RxRAM look
        // like it contained only its oldest prefix.  Every source word now
        // contributes to one proportional destination pixel.
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
                // Underfilled storage uses a literal contiguous 2-byte/pixel
                // mapping. Proportional folding is needed only after the
                // visible capacity is exceeded; using it unconditionally
                // stretched a short FIFO into dotted pixels with large gaps.
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
            if (occupied[pixel]) image.pixel(left + pixel % columns,
                top + pixel / columns, Canvas::word_color(values[pixel]));
        }
        // Packet boundaries are overlaid after folding, so separate frames
        // remain visible even when many source words share one pixel.
        for (const size_t boundary : boundaries) {
            const size_t pixel = source_words <= pixels
                ? std::min(pixels - 1, boundary)
                : std::min(pixels - 1,
                    boundary * pixels / source_words);
            image.pixel(left + pixel % columns, top + pixel / columns, GRID);
        }
    }

    static void packet_prefix(Canvas& image, Rect rect, const Packet& packet)
    {
        // Magnify the 20 two-byte words touched by firmware. A one-pixel cache
        // grid is too small to see in a 500-pixel-wide video: the first 32-byte
        // line occupies row zero and the remaining eight bytes occupy row one.
        const size_t words = std::min<size_t>(20, (packet.size() + 1) / 2);
        for (size_t word = 0; word < words; ++word) {
            const size_t byte = word * 2;
            const uint16_t value = packet[byte]
                | (uint16_t)(byte + 1 < packet.size()
                    ? packet[byte + 1] : 0) << 8;
            const int column = (int)(word % 16);
            const int row = (int)(word / 16);
            image.fill(Rect{rect.x + 3 + column * 6,
                rect.y + 10 + row * 9, 5, 7},
                Canvas::word_color(value));
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
        // Every byte range maps to a pixel; nothing beyond the visible prefix
        // is discarded. If several words share a pixel, use the last valid
        // nonzero word so newly written packet colors remain apparent.
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
        for (int row = 1; row < rows; ++row) {
            image.pixel(left + columns, top + row, GRID);
        }
        if (source_words != 0 && pixels != 0) {
            const size_t active_word = (address % bytes.size()) / 2;
            const size_t active_pixel = std::min(pixels - 1,
                active_word * pixels / source_words);
            image.pixel(left + (int)(active_pixel % columns),
                top + (int)(active_pixel / columns), ACTIVE);
        }
    }

    void render(DUT& dut, uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        const uint32_t cleared_lines = (uint32_t)dut.processing
            .packet_dma[0].clear_completed_count_out();
        // Resolve a queue token observed before its flattened AXI payload by
        // attaching the coherent packet once the observer sees the L2 write.
        size_t coherent_bytes = 0;
        while (coherent_bytes < l2_valid[0].size()
            && l2_valid[0][coherent_bytes]) ++coherent_bytes;
        if (coherent_bytes != 0) {
            for (auto& queue : rx_queue) {
                for (auto& packet : queue) {
                    packet.assign(l2_data[0].begin(),
                        l2_data[0].begin() + coherent_bytes);
                }
            }
        }
        canvas.clear(background_color);
        const Rect channel{3, 2, 43, 296};
        const Rect fifo_rect{49, 2, 56, 296};
        const Rect rx_ram_rect{108, 2, 122, 296};
        const Rect cpu_rect{233, 2, 201, 296};
        const Rect l2_rect{239, 14, 62, 278};
        std::array<Rect, CORES> core_rects{};
        std::array<Rect, CORES> l1i_rects{};
        std::array<Rect, CORES> l1d_rects{};
        for (uint32_t core = 0; core < CORES; ++core) {
            const int y = 14 + (int)core * 70;
            core_rects[core] = Rect{305, y, 123, 65};
            l1i_rects[core] = Rect{310, y + 5, 113, 20};
            l1d_rects[core] = Rect{310, y + 28, 113, 32};
        }
        const Rect rx_queue_rect{437, 2, 60, 146};
        const Rect tx_queue_rect{437, 152, 60, 146};
        const Rect ddr_rect{3, 302, 494, 56};

        panel(canvas, channel, "2X10G");
        canvas.text(channel.x + 3, channel.y + 9, "CHANNEL", TEXT);
        channel_rows(canvas, channel);

        panel(canvas, fifo_rect, "PORT FIFOS");
        fifo_rows(canvas, fifo_rect, rx_fifo, tx_fifo);

        panel(canvas, rx_ram_rect, "RX RAM");
        partitioned(canvas, rx_ram_rect, rx_ram);

        cpu_chip(canvas, cpu_rect);
        canvas.text(cpu_rect.x + 7, cpu_rect.y + 4,
            "TRIBE CPU / 4 CORES", TEXT);
        panel(canvas, l2_rect, std::format("L2 64K C{}", cleared_lines),
            l2_edge && l2_write_address_valid[0]);
        cache(canvas, l2_rect, l2_full_data[0], l2_full_valid[0],
            l2_physical_offset(l2_write_address[0]));
        for (uint32_t core = 0; core < CORES; ++core) {
            cpu_chip(canvas, core_rects[core]);
            panel(canvas, l1i_rects[core],
                std::format("CORE {} I$", core));
            cache(canvas, l1i_rects[core], l1_instruction[core],
                l1_instruction_valid[core], l1_instruction_address[core]);
            panel(canvas, l1d_rects[core],
                std::format("CORE {} D$ MAC {}", core,
                    packet_header_reads[core]),
                l1_data_activity[core] != 0);
            cache(canvas, l1d_rects[core], l1_data[core],
                l1_data_valid[core], l1_data_address[core]);
        }

        // Do not key the border to the unrelated sys/net phase relationship;
        // that made this rectangle blink at the sampling cadence.
        panel(canvas, rx_queue_rect, "RX QUEUE");
        partitioned(canvas, rx_queue_rect, rx_queue_recent);
        panel(canvas, tx_queue_rect, "TX QUEUE");
        partitioned(canvas, tx_queue_rect, tx_queue);

        panel(canvas, ddr_rect, std::format(
            "DDR: PACKETS {}K BLACK=CLR-HDR | MAC/HASH {}K | C {}/{}",
            DUT::DDR_BYTES / 2048, DUT::DDR_BYTES / 2048,
            cleared_lines, source_packets.size()));
        ddr_memory(canvas, ddr_rect, dut);

        for (uint32_t core = 0; core < CORES; ++core) {
            if (l1_data_activity[core] != 0) --l1_data_activity[core];
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
            && l2_packets >= source_packets.size() / 2
            && l2_packets < source_packets.size()) {
            snapshot("_mid");
            mid_snapshot_written = true;
        }
        if (!queue_snapshot_written) {
            for (const auto& queue : rx_queue) {
                if (coherent_bytes != 0 && !queue.empty()
                    && !queue.front().empty()) {
                    snapshot("_queue");
                    queue_snapshot_written = true;
                    break;
                }
            }
        }
        if (!tx_fifo_snapshot_written) {
            if constexpr (DEMO_L2_SWITCH) {
                bool all_ports_visible = true;
                for (const auto& queue : tx_fifo)
                    all_ports_visible &= !queue.empty();
                if (all_ports_visible) {
                    snapshot("_tx_fifo");
                    tx_fifo_snapshot_written = true;
                }
            }
            else {
                for (const auto& queue : tx_fifo) {
                    if (!queue.empty()) {
                        snapshot("_tx_fifo");
                        tx_fifo_snapshot_written = true;
                        break;
                    }
                }
            }
        }
        if (!clear_snapshot_written && cleared_lines >= source_packets.size() / 2
            && cleared_lines < source_packets.size()) {
            snapshot("_clearing");
            clear_snapshot_written = true;
        }

        video.write(canvas);
#if DEMO_TRANSPARENT_VIDEO
        transparent_video.write(canvas);
#endif
        uint32_t rx_fifo_packets = 0;
        uint32_t tx_fifo_packets = 0;
        for (uint32_t stream = 0; stream < NETWORK_STREAMS; ++stream) {
            rx_fifo_packets += rx_fifo[stream].size();
            tx_fifo_packets += tx_fifo[stream].size();
            if (!rx_fifo[stream].empty())
                ++rx_fifo_port_visible_frames[stream];
            if (!tx_fifo[stream].empty())
                ++tx_fifo_port_visible_frames[stream];
        }
        if (rx_fifo_packets != 0) ++rx_fifo_visible_frames;
        if (tx_fifo_packets != 0) ++tx_fifo_visible_frames;
        trace << video.frame_count() - 1 << ',' << ticks << ',' << net_cycles
              << ',' << cpu_cycles << ',' << l2_cycles << ',' << system_cycles
              << ',' << loaded_beats << ',' << emitted_beats << ','
              << completed_packets << ',' << host_consumer << ','
              << rx_fifo_packets << ',' << tx_fifo_packets << ','
              << mac_tx_packets << ',' << cleared_lines << '\n';
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
        mac_tx_expected_matched.assign(expected_tx_packets(), false);
        // The capture test constructs the observer after loading the compact
        // generator image, immediately before firmware boot and wire release.
        loaded_beats = source_beats.size();
        const std::filesystem::path trace_path = path.parent_path()
            / (path.stem().string() + ".csv");
        trace.open(trace_path);
        if (!trace) throw std::runtime_error("cannot create trace "
            + trace_path.string());
        trace << "video_frame,cpu_tick,net_cycle,cpu_cycle,l2_cycle,system_cycle,"
                 "loaded_beats,emitted_beats,rx_packets,host_consumer,"
                 "rx_fifo_packets,tx_fifo_packets,mac_tx_packets,"
                 "cleared_lines\n";
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            l2_data[cluster].assign(L2_VIEW_BYTES, 0);
            l2_valid[cluster].assign(L2_VIEW_BYTES, false);
            l2_full_data[cluster].assign(L2_VIEW_BYTES, 0);
            l2_full_valid[cluster].assign(L2_VIEW_BYTES, false);
            l2_slot_data[cluster].assign(
                PACKET_SLOT_BYTES * PACKET_SLOT_COUNT, 0);
            l2_slot_valid[cluster].assign(
                PACKET_SLOT_BYTES * PACKET_SLOT_COUNT, false);
            l2_packet_base[cluster] = PACKET_BUFFER;
        }
        for (uint32_t core = 0; core < CORES; ++core) {
            l1_instruction[core].assign(L1I_VIEW_BYTES, 0);
            l1_instruction_valid[core].assign(L1I_VIEW_BYTES, false);
            l1_data[core].assign(L1D_VIEW_BYTES, 0);
            l1_data_valid[core].assign(L1D_VIEW_BYTES, false);
        }
    }

    void observe_cpu_before(DUT& dut)
    {
        uint32_t simultaneous_packet_cores = 0;
        ++cpu_cycles;
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            auto& packet_dma = dut.processing.packet_dma[cluster];
            const uint32_t completed =
                (uint32_t)packet_dma.clear_completed_count_out();
            while (observed_clear_completions < completed
                && !pending_clear_addresses.empty()) {
                mirror_completed_clear(cluster,
                    pending_clear_addresses.front());
                pending_clear_addresses.pop_front();
                ++observed_clear_completions;
            }
            if (packet_dma.l2_line_valid_out()
                && packet_dma.l2_line_ready_in()) {
                const uint32_t address =
                    (uint32_t)packet_dma.l2_line_addr_out();
                if (address >= PACKET_BUFFER
                    && address < PACKET_BUFFER
                        + PACKET_SLOT_BYTES * PACKET_SLOT_COUNT
                    && (address - PACKET_BUFFER) % PACKET_SLOT_BYTES == 0) {
                    l2_packet_base[cluster] = address;
                    const uint32_t slot_offset = address - PACKET_BUFFER;
                    std::fill_n(l2_slot_data[cluster].begin() + slot_offset,
                        PACKET_SLOT_BYTES, 0);
                    std::fill_n(l2_slot_valid[cluster].begin() + slot_offset,
                        PACKET_SLOT_BYTES, false);
                    std::fill(l2_data[cluster].begin(), l2_data[cluster].end(), 0);
                    std::fill(l2_valid[cluster].begin(), l2_valid[cluster].end(),
                        false);
                    // Seed the packet view from the byte-exact generator
                    // image. The accepted coherent lines below overwrite the
                    // same bytes; seeding avoids observer scheduling hiding a
                    // one-cycle line transfer between rendered frames.
                    const Packet& packet =
                        source_packets[l2_packets % source_packets.size()];
                    l2_slot_packet[cluster][slot_offset / PACKET_SLOT_BYTES] =
                        (uint32_t)(l2_packets % source_packets.size());
                    const size_t visible = std::min(packet.size(),
                        l2_data[cluster].size());
                    std::copy_n(packet.begin(), visible,
                        l2_data[cluster].begin());
                    std::fill_n(l2_valid[cluster].begin(), visible, true);
                    std::copy_n(packet.begin(), visible,
                        l2_slot_data[cluster].begin() + slot_offset);
                    std::fill_n(l2_slot_valid[cluster].begin() + slot_offset,
                        visible, true);
                    ++l2_packets;
                }
                l2_write_address[cluster] = address;
                const uint32_t physical = l2_physical_offset(address);
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (packet_dma.l2_line_keep_out()[byte]
                        && physical + byte < l2_full_data[cluster].size()) {
                        l2_full_data[cluster][physical + byte] =
                            (uint8_t)packet_dma.l2_line_data_out().bits(
                                byte * 8 + 7, byte * 8);
                        l2_full_valid[cluster][physical + byte] = true;
                    }
                }
                if (address >= PACKET_BUFFER
                    && address < PACKET_BUFFER
                        + PACKET_SLOT_BYTES * PACKET_SLOT_COUNT) {
                    const uint32_t slot_offset = address - PACKET_BUFFER;
                    for (uint32_t byte = 0; byte < 32; ++byte) {
                        if (packet_dma.l2_line_keep_out()[byte]
                            && slot_offset + byte
                                < l2_slot_data[cluster].size()) {
                            l2_slot_data[cluster][slot_offset + byte] =
                                (uint8_t)packet_dma.l2_line_data_out().bits(
                                    byte * 8 + 7, byte * 8);
                            l2_slot_valid[cluster][slot_offset + byte] = true;
                        }
                    }
                }
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    const uint32_t offset = address - l2_packet_base[cluster];
                    if (packet_dma.l2_line_keep_out()[byte]
                        && offset + byte < L2_VIEW_BYTES) {
                        l2_data[cluster][offset + byte] =
                            (uint8_t)packet_dma.l2_line_data_out().bits(
                                byte * 8 + 7, byte * 8);
                        l2_valid[cluster][offset + byte] = true;
                    }
                }
            }
            auto& dma = packet_dma.l2_dma;
            if (dma.awvalid_out() && dma.awready_in()) {
                const uint32_t address = (uint32_t)dma.awaddr_out();
                if (address >= PACKET_BUFFER
                    && address < PACKET_BUFFER
                        + PACKET_SLOT_BYTES * PACKET_SLOT_COUNT
                    && (address - PACKET_BUFFER) % PACKET_SLOT_BYTES == 0
                    && l2_packets < source_packets.size()) {
                    l2_packet_base[cluster] = address;
                    std::fill(l2_data[cluster].begin(), l2_data[cluster].end(), 0);
                    std::fill(l2_valid[cluster].begin(), l2_valid[cluster].end(),
                        false);
                    const uint32_t slot = (address - PACKET_BUFFER)
                        / PACKET_SLOT_BYTES;
                    l2_slot_packet[cluster][slot] = (uint32_t)l2_packets;
                    // The coherent AXI write can present AW/W in the same
                    // evaluation step. Seed the visual mirror from the
                    // byte-exact generated frame, then let observed W beats
                    // overwrite it when their wrapper timing is visible.
                    const Packet& packet = source_packets[l2_packets];
                    const size_t visible = std::min(packet.size(),
                        l2_data[cluster].size());
                    std::copy_n(packet.begin(), visible,
                        l2_data[cluster].begin());
                    std::fill_n(l2_valid[cluster].begin(), visible, true);
                    const uint32_t slot_offset = slot * PACKET_SLOT_BYTES;
                    std::copy_n(packet.begin(), visible,
                        l2_slot_data[cluster].begin() + slot_offset);
                    std::fill_n(l2_slot_valid[cluster].begin() + slot_offset,
                        visible, true);
                    ++l2_packets;
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
                const bool clear_address_write = cache_debug.dcache_cpu_write
                    && cache_debug.dcache_cpu_addr == DMA_CLEAR_ADDRESS_MMIO;
                if (clear_address_write
                    && !clear_address_write_active[core]) {
                    pending_clear_addresses.push_back(
                        cache_debug.dcache_cpu_wdata
                            & ~(CPU::CACHE_LINE_BYTES - 1));
                }
                clear_address_write_active[core] = clear_address_write;
                const uint32_t instruction = cache_debug.icache_read_addr;
                l1_instruction_address[core] = instruction;
                const uint32_t line = instruction & ~31u;
                const uint32_t physical_line = line % L1I_VIEW_BYTES;
                if (line < firmware.size()) {
                    for (uint32_t byte = 0; byte < 32
                        && physical_line + byte < L1I_VIEW_BYTES
                        && line + byte < firmware.size(); ++byte) {
                        l1_instruction[core][physical_line + byte] =
                            firmware[line + byte];
                        l1_instruction_valid[core][physical_line + byte] = true;
                    }
                }
                if (cache_debug.dcache_cpu_read
                    || cache_debug.dcache_cpu_write) {
                    const uint32_t address = cache_debug.dcache_cpu_addr;
                    if (address >= PACKET_BUFFER
                        && address < PACKET_BUFFER
                            + PACKET_SLOT_BYTES * PACKET_SLOT_COUNT) {
                        ++simultaneous_packet_cores;
                        const uint32_t slot_base = PACKET_BUFFER
                            + ((address - PACKET_BUFFER) / PACKET_SLOT_BYTES)
                                * PACKET_SLOT_BYTES;
                        const uint32_t packet_offset = address - slot_base;
                        if (cache_debug.dcache_cpu_read
                            && packet_offset < 40)
                            ++packet_header_reads[core];
                        l1_data_address[core] = packet_offset;
                        const uint32_t line_address = packet_offset & ~31u;
                        const uint32_t physical_line =
                            (address & ~31u) % L1D_VIEW_BYTES;
                        const uint32_t slot_line = slot_base - PACKET_BUFFER
                            + line_address;
                        const Packet& slot_packet = source_packets[
                            l2_slot_packet[cluster][
                                (slot_base - PACKET_BUFFER)
                                    / PACKET_SLOT_BYTES]];
                        const size_t prefix_bytes =
                            std::min<size_t>(40, slot_packet.size());
                        l1_packet_prefix[core].assign(slot_packet.begin(),
                            slot_packet.begin() + prefix_bytes);
                        for (uint32_t byte = 0; byte < 32
                            && physical_line + byte < L1D_VIEW_BYTES; ++byte) {
                            if (line_address + byte < slot_packet.size()) {
                                l1_data[core][physical_line + byte] =
                                    slot_packet[line_address + byte];
                                l1_data_valid[core][physical_line + byte] = true;
                            }
                            else {
                                l1_data[core][physical_line + byte] =
                                    l2_slot_data[cluster][slot_line + byte];
                                l1_data_valid[core][physical_line + byte] =
                                    l2_slot_valid[cluster][slot_line + byte];
                            }
                        }
                        if (cache_debug.dcache_cpu_write) {
                            const uint32_t word_offset = address & 31u;
                            for (uint32_t byte = 0; byte < 4; ++byte) {
                                if (((cache_debug.dcache_cpu_wmask >> byte)
                                        & 1u) != 0
                                    && physical_line + word_offset + byte
                                        < L1D_VIEW_BYTES) {
                                    l1_data[core][physical_line + word_offset
                                        + byte] = (uint8_t)
                                        (cache_debug.dcache_cpu_wdata
                                            >> (byte * 8));
                                    l1_data_valid[core][physical_line
                                        + word_offset + byte] = true;
                                }
                            }
                        }
                        // Keep recent parallel activity visible across video
                        // decimation; the counter is visual dwell, while the
                        // simultaneous-core assertion uses same-cycle RTL
                        // requests above and is not affected by this value.
                        l1_data_activity[core] = 60;
                    }
                    else if (address < firmware.size()) {
                        l1_data_address[core] = address % L1D_VIEW_BYTES;
                        const uint32_t line_address = address & ~31u;
                        const uint32_t physical_line =
                            line_address % L1D_VIEW_BYTES;
                        for (uint32_t byte = 0; byte < 32
                            && physical_line + byte < L1D_VIEW_BYTES; ++byte) {
                            if (line_address + byte < firmware.size()) {
                                l1_data[core][physical_line + byte] =
                                    firmware[line_address + byte];
                                l1_data_valid[core][physical_line + byte] = true;
                            }
                        }
                    }
                }
            }
        }
        max_simultaneous_packet_cores = std::max(
            max_simultaneous_packet_cores, simultaneous_packet_cores);
    }

    void observe_l2_before(DUT& dut)
    {
        ++l2_cycles;
        if (dut.smartnic.l2_descriptor_valid_out()
            && dut.smartnic.l2_descriptor_ready_in()) {
            if ((uint32_t)dut.smartnic.l2_descriptor_word_out() == 0) {
                descriptor_stream = (uint32_t)dut.smartnic
                    .l2_descriptor_data_out().bits(71, 64)
                    % NETWORK_STREAMS;
            }
            if (dut.smartnic.l2_descriptor_eop_out())
                ++rx_fifo_pending_pop[descriptor_stream];
        }
        for (uint32_t cluster = 0; cluster < CLUSTERS; ++cluster) {
            if (dut.processing.rx_read_valid_out()[cluster]
                && dut.processing.rx_read_ready_in()[cluster]) {
                const uint32_t handle = (uint32_t)dut.processing
                    .rx_read_handle_out().bits(cluster * DUT::HANDLE_BITS
                        + DUT::HANDLE_BITS - 1,
                        cluster * DUT::HANDLE_BITS);
                rx_read_stream[cluster] = (handle & 7u) % NETWORK_STREAMS;
            }
            auto& packet_dma = dut.processing.packet_dma[cluster];
            if (packet_dma.rx_valid_in() && packet_dma.rx_ready_out()
                && packet_dma.rx_eop_in()) {
                const uint32_t stream = rx_read_stream[cluster];
                if (!rx_ram[stream].empty())
                    rx_ram[stream].erase(rx_ram[stream].begin());
            }
            if (packet_dma.system_tx_valid_out()
                && packet_dma.system_tx_ready_in()) {
                if (packet_dma.system_tx_sop_out()) {
                    rx_queue_assembling[cluster].clear();
                }
                append_beat(rx_queue_assembling[cluster],
                    (logic<256>)packet_dma.system_tx_data_out(),
                    (logic<32>)packet_dma.system_tx_keep_out());
                if (packet_dma.system_tx_eop_out()) {
                    // Some CppHDL input-port wrappers expose accepted AXI data
                    // one evaluation later than the valid/EOP token. The L2
                    // mirror is sourced from the same CPU-to-System transfer,
                    // so snapshot the exact contiguous coherent packet here.
                    size_t bytes = 0;
                    while (bytes < l2_valid[cluster].size()
                        && l2_valid[cluster][bytes]) ++bytes;
                    if (bytes != 0) {
                        rx_queue_assembling[cluster].assign(
                            l2_data[cluster].begin(),
                            l2_data[cluster].begin() + bytes);
                    }
                    rx_queue[cluster].push_back(
                        std::move(rx_queue_assembling[cluster]));
                    rx_queue_recent[cluster].push_back(rx_queue[cluster].back());
                    if (rx_queue_recent[cluster].size() > 4)
                        rx_queue_recent[cluster].pop_front();
                    rx_queue_assembling[cluster].clear();
                }
            }
            if (packet_dma.network_tx_valid_out()
                && packet_dma.network_tx_ready_in()) {
                if (packet_dma.network_tx_sop_out())
                    tx_dma_assembling[cluster].clear();
                append_beat(tx_dma_assembling[cluster],
                    (logic<256>)packet_dma.network_tx_data_out(),
                    (logic<32>)packet_dma.network_tx_keep_out());
                if (packet_dma.network_tx_eop_out()) {
                    const uint32_t port = (uint32_t)packet_dma
                        .network_tx_port_out() % NETWORK_STREAMS;
                    tx_fifo[port].push_back(
                        std::move(tx_dma_assembling[cluster]));
                    tx_fifo_birth_frame[port].push_back(video.frame_count());
                    tx_dma_assembling[cluster].clear();
                }
            }
        }
    }

    void observe_system_before(DUT& dut)
    {
        (void)dut;
        ++system_cycles;
    }

    void observe_net_before(DUT& dut)
    {
        ++net_cycles;
        // Observe only accepted data at the external MAC boundary. This is
        // deliberately downstream of PacketDMA, the CDC gearbox, Network
        // TxFIFO, and OutputMerger, so the video cannot imply transmission
        // merely because a DMA command was issued.
        if (dut.smartnic.net_tx_valid_out()
            && dut.smartnic.net_tx_ready_in()) {
            const auto data = dut.smartnic.net_tx_data_out();
            const auto keep = dut.smartnic.net_tx_keep_out();
            const auto sop = dut.smartnic.net_tx_sop_out();
            const auto eop = dut.smartnic.net_tx_eop_out();
            constexpr uint32_t PORT_BYTES =
                DUT::NET_BYTES / NETWORK_STREAMS;
            for (uint32_t port = 0; port < NETWORK_STREAMS; ++port) {
                for (uint32_t lane_byte = 0; lane_byte < PORT_BYTES;
                    ++lane_byte) {
                    const uint32_t byte = port * PORT_BYTES + lane_byte;
                    if (!keep[byte]) continue;
                    if (sop[byte]) {
                        if (mac_tx_in_frame[port]) mac_tx_error = true;
                        mac_tx_assembling[port].clear();
                        mac_tx_in_frame[port] = true;
                    }
                    if (!mac_tx_in_frame[port]) {
                        mac_tx_error = true;
                        continue;
                    }
                    mac_tx_assembling[port].push_back((uint8_t)data.bits(
                        byte * 8 + 7, byte * 8));
                    if (eop[byte]) {
                        size_t matched = mac_tx_expected_matched.size();
                        for (size_t candidate = 0;
                            candidate < mac_tx_expected_matched.size();
                            ++candidate) {
                            const uint32_t expected_index =
                                expected_tx_source_index(candidate);
                            if (!mac_tx_expected_matched[candidate]
                                && expected_index < source_packets.size()
                                && source_packets[expected_index][3] == port
                                && mac_tx_assembling[port]
                                    == source_packets[expected_index]) {
                                matched = candidate;
                                break;
                            }
                        }
                        if (matched == mac_tx_expected_matched.size())
                            mac_tx_error = true;
                        else {
                            mac_tx_expected_matched[matched] = true;
                            // A CPU-issued post-TX-clear command enters the
                            // DDR backing path after PacketDMA's EOP. Record
                            // the byte-exact matched ring slot so its completed
                            // response updates the L2 visualization as well.
                            const uint32_t source_index =
                                expected_tx_source_index((uint32_t)matched);
                            pending_clear_addresses.push_back(
                                (source_index & (PACKET_SLOT_COUNT - 1))
                                    * PACKET_SLOT_BYTES);
                        }
                        // A MAC EOP is the real dequeue event. Require it to
                        // match the packet previously admitted from PacketDMA.
                        if (tx_fifo_pending_pop[port]
                                >= tx_fifo[port].size()
                            || tx_fifo[port][tx_fifo_pending_pop[port]]
                                != mac_tx_assembling[port]) {
                            mac_tx_error = true;
                        }
                        else {
                            // Keep the verified, already-dequeued packet in
                            // the drawing briefly; frame() performs its visual
                            // retirement. Hardware timing is unaffected.
                            ++tx_fifo_pending_pop[port];
                        }
                        mac_tx_assembling[port].clear();
                        mac_tx_in_frame[port] = false;
                        ++mac_tx_port_packets[port];
                        ++mac_tx_packets;
                    }
                }
            }
        }
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
            const uint32_t stream = completed_packets % NETWORK_STREAMS;
            const uint32_t cluster = completed_packets % CLUSTERS;
            rx_ram[stream].push_back(packet);
            rx_fifo[stream].push_back(
                descriptor_for(packet, (uint32_t)completed_packets));
            rx_fifo_birth_frame[stream].push_back(video.frame_count());
            ++completed_packets;
        }
    }

    void frame(DUT& dut, uint64_t ticks, uint32_t host_consumer,
        bool l2_edge, bool system_edge)
    {
        // Hold a very short-lived RX descriptor for eight video frames so its
        // enqueue and dequeue are both visible at the decimated frame rate.
        // Once all traffic has drained, retire immediately so the final still
        // represents the empty hardware FIFO.
        constexpr uint32_t RX_FIFO_VISIBLE_FRAMES = 8;
        constexpr uint32_t TX_FIFO_VISIBLE_FRAMES = 60;
        const bool rx_settled = l2_packets == source_packets.size();
        const bool tx_settled = mac_tx_packets == expected_tx_packets();
        for (uint32_t stream = 0; stream < NETWORK_STREAMS; ++stream) {
            while (rx_fifo_pending_pop[stream] != 0
                && !rx_fifo[stream].empty()
                && (rx_settled || video.frame_count()
                    >= rx_fifo_birth_frame[stream].front()
                        + RX_FIFO_VISIBLE_FRAMES)) {
                rx_fifo[stream].pop_front();
                rx_fifo_birth_frame[stream].pop_front();
                --rx_fifo_pending_pop[stream];
            }
            while (tx_fifo_pending_pop[stream] != 0
                && !tx_fifo[stream].empty()
                && (tx_settled || video.frame_count()
                    >= tx_fifo_birth_frame[stream].front()
                        + TX_FIFO_VISIBLE_FRAMES)) {
                tx_fifo[stream].pop_front();
                tx_fifo_birth_frame[stream].pop_front();
                --tx_fifo_pending_pop[stream];
            }
        }
        // The AXI host consumer register advances once a complete queue packet
        // has reached host memory. Retire the same packets from the mirror.
        while (previous_host_consumer < host_consumer) {
            const uint32_t queue = previous_host_consumer % QUEUES;
            if (!rx_queue[queue].empty()) rx_queue[queue].pop_front();
            ++previous_host_consumer;
        }
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
    uint32_t mac_tx_packet_count() const { return mac_tx_packets; }
    uint32_t mac_tx_packet_count(uint32_t port) const
    {
        return port < NETWORK_STREAMS ? mac_tx_port_packets[port] : 0;
    }
    bool mac_tx_ok() const { return !mac_tx_error; }
    uint32_t rx_fifo_frame_count() const { return rx_fifo_visible_frames; }
    uint32_t tx_fifo_frame_count() const { return tx_fifo_visible_frames; }
    uint32_t rx_fifo_frame_count(uint32_t port) const
    {
        return port < NETWORK_STREAMS
            ? rx_fifo_port_visible_frames[port] : 0;
    }
    uint32_t tx_fifo_frame_count(uint32_t port) const
    {
        return port < NETWORK_STREAMS
            ? tx_fifo_port_visible_frames[port] : 0;
    }
    uint32_t packet_header_read_count(uint32_t core) const
    {
        return core < CORES ? packet_header_reads[core] : 0;
    }
    uint32_t simultaneous_packet_core_count() const
    {
        return max_simultaneous_packet_cores;
    }
};

} // namespace smartnic_demo
