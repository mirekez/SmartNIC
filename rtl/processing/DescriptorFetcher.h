#pragma once

// Per-CPU receive-descriptor prefetch queue.  The processing dispatcher sends
// one complete five-word descriptor to exactly one instance.  Software reads
// the current descriptor through an uncached 256-bit AXI MMIO window and pops
// it explicitly, so speculative/cacheable loads cannot consume queue state.

#include "../network/RxFifo.h"
#include "../common/AsyncReadRam.h"
#include "../../cpphdl/tribe_cpu/common/Axi4.h"
#include "../../Config.h"

using namespace cpphdl;

template<size_t DEPTH = 4, size_t AXI_ADDR_WIDTH = 32,
    size_t AXI_ID_WIDTH = 4, size_t AXI_DATA_WIDTH = 256,
    size_t HANDLE_BITS = PACKET_HANDLE_BITS>
class DescriptorFetcher : public Module
{
public:
    static constexpr size_t DESCRIPTOR_BITS = 1280;
    static constexpr size_t DESCRIPTOR_WORD_BITS = 256;
    static constexpr size_t DESCRIPTOR_WORDS = 5;
    static constexpr size_t PTR_BITS = DEPTH <= 1 ? 1 : clog2(DEPTH);
    static constexpr size_t COUNT_BITS = clog2(DEPTH + 1);

    static_assert(DEPTH >= 2 && (DEPTH & (DEPTH - 1)) == 0,
        "DescriptorFetcher depth must be a power of two");
    static_assert(AXI_DATA_WIDTH == 256,
        "DescriptorFetcher MMIO currently matches Tribe's 256-bit L2 port");

    enum Register : uint32_t
    {
        REG_CONTROL = 0x000,
        REG_STATUS = 0x004,
        REG_ACTION = 0x008,
        REG_AUTO_SLOT_MASK = 0x00c,
        REG_AUTO_BASE = 0x010,
        REG_DESCRIPTOR_BASE = 0x020,
        REG_PACKET_ADDRESS = 0x100,
        REG_PACKET_META = 0x104,
        REG_DESTINATION_MAC_LO = 0x108,
        REG_DESTINATION_MAC_HI = 0x10c,
        REG_SOURCE_MAC_LO = 0x110,
        REG_SOURCE_MAC_HI = 0x114,
        REG_SOURCE_IP0 = 0x118,
        REG_SOURCE_IP1 = 0x11c,
        REG_SOURCE_IP2 = 0x120,
        REG_SOURCE_IP3 = 0x124,
        REG_DESTINATION_IP0 = 0x128,
        REG_DESTINATION_IP1 = 0x12c,
        REG_DESTINATION_IP2 = 0x130,
        REG_DESTINATION_IP3 = 0x134,
        REG_PORTS = 0x138,
        REG_PROTOCOL = 0x13c,
        // Logical MAC-side ingress port, independent of parsed L4 ports.
        REG_SOURCE_PORT = 0x140,
        // Per-action coherent destination.  Unlike AUTO_BASE this is selected
        // by the hart that atomically claims the current descriptor.
        REG_ACTION_DESTINATION = 0x144,
        // The autonomous DDR packet ring has one authoritative destination
        // MAC record per slot.  Low words occupy 2 KiB.  Two adjacent high
        // half-words share each word in the remaining 1 KiB, fitting all 512
        // records in this device's existing 4 KiB MMIO aperture.
        REG_AUTO_DESTINATION_LO_BASE = 0x400,
        REG_AUTO_DESTINATION_HI_BASE = 0xc00
    };

    static constexpr uint32_t CONTROL_ENABLE = 1u << 0;
    static constexpr uint32_t CONTROL_AUTO_L2 = 1u << 1;
    static constexpr uint32_t ACTION_NEXT = 1u << 0;
    static constexpr uint32_t ACTION_DMA_DISCARD = 1u << 1;
    static constexpr uint32_t ACTION_DMA_SYSTEM = 1u << 2;
    static constexpr uint32_t ACTION_DMA_CACHE = 1u << 3;
    static constexpr uint32_t ACTION_DMA_NETWORK = 1u << 4;
    static constexpr uint32_t STATUS_AVAILABLE = 1u << 0;
    static constexpr uint32_t STATUS_PREFETCH_ENABLED = 1u << 1;
    static constexpr uint32_t STATUS_PROTOCOL_ERROR = 1u << 2;
    static constexpr uint32_t STATUS_DMA_READY = 1u << 3;

    _PORT(bool) descriptor_valid_in;
    _PORT(logic<DESCRIPTOR_WORD_BITS>) descriptor_data_in;
    _PORT(u<3>) descriptor_word_in;
    _PORT(bool) descriptor_sop_in;
    _PORT(bool) descriptor_eop_in;
    _PORT(bool) descriptor_ready_out;

    // A single software action transfers the descriptor-owned RxRAM handle
    // and exact frame length into PacketDMA.  Software supplies only whether
    // the packet is discarded or forwarded directly to the System queue.
    _PORT(bool) packet_command_ready_in;
    _PORT(bool) packet_command_valid_out;
    _PORT(u<HANDLE_BITS>) packet_command_handle_out;
    _PORT(u<14>) packet_command_length_out;
    _PORT(bool) packet_command_system_out;
    _PORT(bool) packet_command_cache_out;
    _PORT(bool) packet_command_network_out;
    _PORT(u<8>) packet_command_network_port_out;
    _PORT(u32) packet_command_destination_out;

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> mmio;

    _PORT(bool) descriptor_available_out;
    _PORT(u<COUNT_BITS>) descriptor_count_out;
    _PORT(bool) prefetch_enabled_out;
    _PORT(bool) auto_l2_enabled_out;
    _PORT(bool) protocol_error_out;

private:
    // Keep payload storage as an actual memory. A reg<> array makes CppHDL
    // preserve a whole-array next value, which synthesized as thousands of
    // flops plus a 1,280-bit circular-head mux. The queue count makes stale
    // memory contents unobservable after reset, so the payload RAM itself
    // deliberately has no reset.
    AsyncReadRam<DESCRIPTOR_BITS, DEPTH> queue_mem;
    AsyncReadRam<32, 512> auto_destination_low_mem;
    AsyncReadRam<32, 256> auto_destination_high_mem;
    reg<u<PTR_BITS>> head_reg;
    reg<u<PTR_BITS>> tail_reg;
    reg<u<COUNT_BITS>> count_reg;
    reg<logic<DESCRIPTOR_BITS>> assembly_reg;
    reg<u<3>> assembly_word_reg;
    reg<u1> assembly_active_reg;
    reg<u1> enabled_reg;
    reg<u1> auto_l2_reg;
    // One half of the 1 MiB CPU DDR is a 256-entry, 2 KiB packet ring.
    // Keeping base/mask programmable lets a larger board-level DDR map use
    // the same RTL without changing the descriptor protocol.
    reg<u<9>> auto_slot_mask_reg;
    reg<u32> auto_base_reg;
    reg<u32> auto_sequence_reg;
    reg<u1> protocol_error_reg;
    reg<u1> packet_command_valid_reg;
    reg<u<HANDLE_BITS>> packet_command_handle_reg;
    reg<u<14>> packet_command_length_reg;
    reg<u1> packet_command_system_reg;
    reg<u1> packet_command_cache_reg;
    reg<u1> packet_command_network_reg;
    reg<u<8>> packet_command_network_port_reg;
    reg<u32> packet_command_destination_reg;
    reg<u32> action_destination_reg;
    reg<u1> auto_metadata_write_reg;
    reg<u<9>> auto_metadata_slot_reg;
    reg<u32> auto_metadata_low_reg;
    reg<u16> auto_metadata_high_even_reg;
    reg<u1> auto_metadata_high_write_reg;
    reg<u<8>> auto_metadata_high_addr_reg;
    reg<u32> auto_metadata_high_data_reg;

    reg<u<AXI_ADDR_WIDTH>> write_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_id_reg;
    reg<u1> write_addr_valid_reg;
    reg<u1> write_response_valid_reg;
    reg<u<AXI_ID_WIDTH>> read_id_reg;
    reg<u<AXI_ADDR_WIDTH>> read_addr_reg;
    reg<u<32>> read_value_reg;
    reg<u<clog2(AXI_DATA_WIDTH / 8)>> read_lane_reg;
    reg<u1> read_pending_reg;
    reg<u1> read_format_pending_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    logic<DESCRIPTOR_BITS> current_descriptor_comb;
    logic<DESCRIPTOR_BITS> queue_write_data_comb;
    logic<AXI_DATA_WIDTH> register_read_comb;

    logic<DESCRIPTOR_BITS>& current_descriptor_comb_func()
    {
        current_descriptor_comb = 0;
        if ((uint32_t)count_reg != 0) {
            current_descriptor_comb = queue_mem.read_data_out();
        }
        return current_descriptor_comb;
    }

    logic<DESCRIPTOR_BITS>& queue_write_data_comb_func()
    {
        uint32_t bit;
        uint32_t word_index;
        queue_write_data_comb = assembly_reg;
        word_index = (uint32_t)descriptor_word_in();
        if (word_index >= DESCRIPTOR_WORDS) word_index = 0;
        if (descriptor_sop_in()) queue_write_data_comb = 0;
        for (bit = 0; bit < DESCRIPTOR_WORD_BITS; ++bit) {
            queue_write_data_comb[word_index * DESCRIPTOR_WORD_BITS + bit] =
                descriptor_data_in()[bit];
        }
        return queue_write_data_comb;
    }

    uint32_t descriptor_bits32(uint32_t bit_offset)
    {
        uint32_t bit;
        uint32_t value;
        logic<DESCRIPTOR_BITS> descriptor;
        descriptor = current_descriptor_comb_func();
        value = 0;
        for (bit = 0; bit < 32; ++bit) {
            if (bit_offset + bit < DESCRIPTOR_BITS && descriptor[bit_offset + bit]) {
                value |= 1u << bit;
            }
        }
        return value;
    }

    uint32_t register_value(uint32_t address)
    {
        uint32_t body_word;
        if (address == REG_CONTROL) {
            return ((bool)enabled_reg ? CONTROL_ENABLE : 0)
                | ((bool)auto_l2_reg ? CONTROL_AUTO_L2 : 0);
        }
        if (address == REG_STATUS) {
            return ((uint32_t)count_reg != 0 ? STATUS_AVAILABLE : 0)
                | ((bool)enabled_reg ? STATUS_PREFETCH_ENABLED : 0)
                | ((bool)protocol_error_reg ? STATUS_PROTOCOL_ERROR : 0)
                | (packet_command_ready_in()
                    && !packet_command_valid_reg ? STATUS_DMA_READY : 0)
                | ((uint32_t)count_reg << 8);
        }
        if (address == REG_AUTO_SLOT_MASK)
            return (uint32_t)auto_slot_mask_reg;
        if (address == REG_AUTO_BASE) return (uint32_t)auto_base_reg;
        if (address >= REG_DESCRIPTOR_BASE
            && address < REG_DESCRIPTOR_BASE + DESCRIPTOR_BITS / 8
            && (address & 3u) == 0) {
            body_word = (address - REG_DESCRIPTOR_BASE) / 4;
            return descriptor_bits32(body_word * 32);
        }
        if (address == REG_PACKET_ADDRESS) return descriptor_bits32(0);
        if (address == REG_PACKET_META) return descriptor_bits32(32);
        if (address == REG_DESTINATION_MAC_LO) return descriptor_bits32(256);
        if (address == REG_DESTINATION_MAC_HI) return descriptor_bits32(288) & 0xffffu;
        if (address == REG_SOURCE_MAC_LO) return descriptor_bits32(304);
        if (address == REG_SOURCE_MAC_HI) return descriptor_bits32(336) & 0xffffu;
        if (address >= REG_SOURCE_IP0 && address <= REG_SOURCE_IP3) {
            return descriptor_bits32(352 + ((address - REG_SOURCE_IP0) / 4) * 32);
        }
        if (address >= REG_DESTINATION_IP0 && address <= REG_DESTINATION_IP3) {
            return descriptor_bits32(480 + ((address - REG_DESTINATION_IP0) / 4) * 32);
        }
        if (address == REG_PORTS) return descriptor_bits32(608);
        if (address == REG_PROTOCOL) return descriptor_bits32(640);
        if (address == REG_SOURCE_PORT) return descriptor_bits32(64) & 0xffu;
        if (address == REG_ACTION_DESTINATION)
            return (uint32_t)action_destination_reg;
        if (address >= REG_AUTO_DESTINATION_LO_BASE
            && address < REG_AUTO_DESTINATION_HI_BASE
            && (address & 3u) == 0) {
            return (uint32_t)auto_destination_low_mem.read_data_out();
        }
        if (address >= REG_AUTO_DESTINATION_HI_BASE
            && address < 0x1000 && (address & 3u) == 0) {
            return (uint32_t)auto_destination_high_mem.read_data_out();
        }
        return 0;
    }

    logic<AXI_DATA_WIDTH>& register_read_comb_func()
    {
        uint32_t address;
        uint32_t byte_lane;
        uint32_t bit;
        uint32_t value;
        register_read_comb = 0;
        address = (uint32_t)mmio.araddr_in();
        byte_lane = address & (AXI_DATA_WIDTH / 8 - 1);
        value = register_value(address & ~3u);
        for (bit = 0; bit < 32; ++bit) {
            if (byte_lane * 8 + bit < AXI_DATA_WIDTH) {
                register_read_comb[byte_lane * 8 + bit] = (value >> bit) & 1u;
            }
        }
        return register_read_comb;
    }

    uint32_t write_value()
    {
        uint32_t bit;
        uint32_t value;
        uint32_t byte_lane;
        value = 0;
        byte_lane = (uint32_t)write_addr_reg & (AXI_DATA_WIDTH / 8 - 1);
        for (bit = 0; bit < 32; ++bit) {
            if (byte_lane * 8 + bit < AXI_DATA_WIDTH
                && mmio.wdata_in()[byte_lane * 8 + bit]) {
                value |= 1u << bit;
            }
        }
        return value;
    }

public:
#ifndef SYNTHESIS
    uint64_t debug_auto_destination(uint32_t slot)
    {
        const uint32_t low = (uint32_t)
            auto_destination_low_mem.debug_read(slot);
        const uint32_t high_pair = (uint32_t)
            auto_destination_high_mem.debug_read(slot >> 1);
        const uint32_t high = (high_pair >> ((slot & 1u) * 16u)) & 0xffffu;
        return low | ((uint64_t)high << 32);
    }
#endif

    void _assign()
    {
        queue_mem.write_addr_in = _ASSIGN_REG(tail_reg);
        queue_mem.write_in = _ASSIGN(descriptor_valid_in()
            && descriptor_ready_out() && descriptor_eop_in());
        queue_mem.write_data_in =
            _ASSIGN_COMB(queue_write_data_comb_func());
        queue_mem.read_addr_in = _ASSIGN_REG(head_reg);
        queue_mem._assign();

        auto_destination_low_mem.write_addr_in =
            _ASSIGN_REG(auto_metadata_slot_reg);
        auto_destination_low_mem.write_in =
            _ASSIGN_REG(auto_metadata_write_reg);
        auto_destination_low_mem.write_data_in =
            _ASSIGN((logic<32>)auto_metadata_low_reg);
        auto_destination_low_mem.read_addr_in = _ASSIGN(
            (u<9>)(((uint32_t)read_addr_reg
                - REG_AUTO_DESTINATION_LO_BASE) >> 2));
        auto_destination_low_mem._assign();

        auto_destination_high_mem.write_addr_in =
            _ASSIGN_REG(auto_metadata_high_addr_reg);
        auto_destination_high_mem.write_in =
            _ASSIGN_REG(auto_metadata_high_write_reg);
        auto_destination_high_mem.write_data_in =
            _ASSIGN((logic<32>)auto_metadata_high_data_reg);
        auto_destination_high_mem.read_addr_in = _ASSIGN(
            (u<8>)(((uint32_t)read_addr_reg
                - REG_AUTO_DESTINATION_HI_BASE) >> 2));
        auto_destination_high_mem._assign();

        descriptor_ready_out = _ASSIGN((bool)enabled_reg
            && (uint32_t)count_reg < DEPTH);
        descriptor_available_out = _ASSIGN((uint32_t)count_reg != 0);
        descriptor_count_out = _ASSIGN_REG(count_reg);
        prefetch_enabled_out = _ASSIGN_REG(enabled_reg);
        auto_l2_enabled_out = _ASSIGN_REG(auto_l2_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
        packet_command_valid_out = _ASSIGN_REG(packet_command_valid_reg);
        packet_command_handle_out = _ASSIGN_REG(packet_command_handle_reg);
        packet_command_length_out = _ASSIGN_REG(packet_command_length_reg);
        packet_command_system_out = _ASSIGN_REG(packet_command_system_reg);
        packet_command_cache_out = _ASSIGN_REG(packet_command_cache_reg);
        packet_command_network_out =
            _ASSIGN_REG(packet_command_network_reg);
        packet_command_network_port_out =
            _ASSIGN_REG(packet_command_network_port_reg);
        packet_command_destination_out =
            _ASSIGN((u32)packet_command_destination_reg);

        mmio.awready_out = _ASSIGN(!write_addr_valid_reg
            && !write_response_valid_reg);
        mmio.wready_out = _ASSIGN(write_addr_valid_reg
            && !write_response_valid_reg);
        mmio.bvalid_out = _ASSIGN_REG(write_response_valid_reg);
        mmio.bid_out = _ASSIGN_REG(write_id_reg);
        mmio.arready_out = _ASSIGN(!read_pending_reg
            && !read_format_pending_reg && !read_valid_reg);
        mmio.rvalid_out = _ASSIGN_REG(read_valid_reg);
        mmio.rdata_out = _ASSIGN_REG(read_data_reg);
        mmio.rlast_out = _ASSIGN_REG(read_valid_reg);
        mmio.rid_out = _ASSIGN_REG(read_id_reg);
    }

    void _work(bool reset)
    {
        uint32_t count;
        uint32_t address;
        uint32_t value;
        uint32_t bit;
        uint32_t word_index;
        uint32_t next_head;
        uint32_t mac_low_raw;
        uint32_t mac_high_raw;
        bool input_fire;
        bool pop;
        logic<DESCRIPTOR_BITS> assembly;

        count = (uint32_t)count_reg;
        queue_mem._work(reset);
        auto_destination_low_mem._work(reset);
        auto_destination_high_mem._work(reset);
        auto_metadata_write_reg._next = false;
        auto_metadata_high_write_reg._next = false;
        pop = false;
        input_fire = descriptor_valid_in() && descriptor_ready_out();
        // Hold the command until PacketDMA accepts it.  A one-cycle pulse can
        // lose a descriptor when ready changes after the MMIO action was
        // accepted but before registered valid reaches the consumer.
        if (packet_command_valid_reg && packet_command_ready_in())
            packet_command_valid_reg._next = false;

        if (mmio.awvalid_in() && mmio.awready_out()) {
            write_addr_reg._next = mmio.awaddr_in();
            write_id_reg._next = mmio.awid_in();
            write_addr_valid_reg._next = true;
        }
        if (mmio.wvalid_in() && mmio.wready_out()) {
            address = (uint32_t)write_addr_reg & ~3u;
            value = write_value();
            if (address == REG_CONTROL) {
                enabled_reg._next = (value & CONTROL_ENABLE) != 0;
                auto_l2_reg._next = (value & CONTROL_AUTO_L2) != 0;
            }
            else if (address == REG_AUTO_SLOT_MASK) {
                // A mask of 2^N-1 selects a naturally aligned DDR packet ring.
                auto_slot_mask_reg._next = value & 511u;
            }
            else if (address == REG_AUTO_BASE) {
                auto_base_reg._next = value & ~0x7ffu;
            }
            else if (address == REG_ACTION_DESTINATION) {
                action_destination_reg._next = value;
            }
            else if (address == REG_ACTION && (value & ACTION_NEXT) != 0) {
                if ((value & (ACTION_DMA_DISCARD | ACTION_DMA_SYSTEM
                        | ACTION_DMA_CACHE | ACTION_DMA_NETWORK)) == 0) {
                    pop = count != 0;
                }
                else if (count != 0 && packet_command_ready_in()
                    && !packet_command_valid_reg
                    && (((value & ACTION_DMA_DISCARD) != 0)
                        + ((value & ACTION_DMA_SYSTEM) != 0)
                        + ((value & ACTION_DMA_CACHE) != 0)
                        + ((value & ACTION_DMA_NETWORK) != 0)) == 1) {
                    packet_command_handle_reg._next = descriptor_bits32(0);
                    packet_command_length_reg._next = descriptor_bits32(32);
                    packet_command_system_reg._next =
                        (value & ACTION_DMA_SYSTEM) != 0;
                    packet_command_cache_reg._next =
                        (value & ACTION_DMA_CACHE) != 0;
                    packet_command_network_reg._next =
                        (value & ACTION_DMA_NETWORK) != 0;
                    packet_command_network_port_reg._next =
                        (descriptor_bits32(64) & 1u) ^ 1u;
                    packet_command_destination_reg._next =
                        (value & ACTION_DMA_CACHE) != 0
                            ? action_destination_reg : (u32)0;
                    packet_command_valid_reg._next = true;
                    pop = true;
                }
                else protocol_error_reg._next = true;
            }
            write_addr_valid_reg._next = false;
            write_response_valid_reg._next = true;
        }
        if (write_response_valid_reg && mmio.bready_in()) {
            write_response_valid_reg._next = false;
        }

        if (mmio.arvalid_in() && mmio.arready_out()) {
            read_id_reg._next = mmio.arid_in();
            read_addr_reg._next = mmio.araddr_in();
            read_pending_reg._next = true;
        }
        if (read_pending_reg && !read_format_pending_reg
            && !read_valid_reg) {
            address = (uint32_t)read_addr_reg;
            read_value_reg._next = register_value(address & ~3u);
            read_lane_reg._next = address & (AXI_DATA_WIDTH / 8 - 1);
            read_format_pending_reg._next = true;
            read_pending_reg._next = false;
        }
        if (read_format_pending_reg && !read_valid_reg) {
            read_data_reg._next = 0;
            for (bit = 0; bit < 32; ++bit) {
                if ((uint32_t)read_lane_reg * 8 + bit < AXI_DATA_WIDTH) {
                    read_data_reg._next[(uint32_t)read_lane_reg * 8 + bit] =
                        read_value_reg[bit];
                }
            }
            read_valid_reg._next = true;
            read_format_pending_reg._next = false;
        }
        if (read_valid_reg && mmio.rready_in()) {
            read_valid_reg._next = false;
        }

        // Optional hardware prefetch keeps RxRAM retirement independent of
        // uncached firmware MMIO latency. Each destination is both a physical
        // DDR ring address and its coherent L2 address; PacketDMA writes the
        // backing store while retaining the recent hot subset in shared L2.
        if (auto_l2_reg && count != 0 && packet_command_ready_in()
            && !packet_command_valid_reg && !pop) {
            packet_command_handle_reg._next = descriptor_bits32(0);
            packet_command_length_reg._next = descriptor_bits32(32);
            packet_command_system_reg._next = false;
            packet_command_cache_reg._next = true;
            packet_command_network_reg._next = false;
            packet_command_network_port_reg._next = 0;
            packet_command_destination_reg._next = auto_base_reg
                + (((uint32_t)auto_sequence_reg
                    & (uint32_t)auto_slot_mask_reg) << 11);
            // Bind the parsed MAC to the same sequence number as the packet
            // destination.  The CPU reads this uncached table instead of a
            // private-L1 copy that may predate an autonomous DMA refill.
            auto_metadata_slot_reg._next = (uint32_t)auto_sequence_reg
                & (uint32_t)auto_slot_mask_reg;
            // Parser MAC fields are 48-bit network-order integers. Expose
            // them in the same little-endian word layout produced by RV32
            // loads from packet bytes 0..5.
            mac_low_raw = descriptor_bits32(256);
            mac_high_raw = descriptor_bits32(288) & 0xffffu;
            auto_metadata_low_reg._next =
                ((mac_high_raw >> 8) & 0xffu)
                | ((mac_high_raw & 0xffu) << 8)
                | (((mac_low_raw >> 24) & 0xffu) << 16)
                | (((mac_low_raw >> 16) & 0xffu) << 24);
            auto_metadata_write_reg._next = true;
            if (((uint32_t)auto_sequence_reg & 1u) == 0) {
                auto_metadata_high_even_reg._next =
                    ((mac_low_raw >> 8) & 0xffu)
                    | ((mac_low_raw & 0xffu) << 8);
            }
            else {
                auto_metadata_high_addr_reg._next =
                    (((uint32_t)auto_sequence_reg
                        & (uint32_t)auto_slot_mask_reg) >> 1);
                auto_metadata_high_data_reg._next =
                    (uint32_t)auto_metadata_high_even_reg
                    | ((((mac_low_raw >> 8) & 0xffu)
                        | ((mac_low_raw & 0xffu) << 8)) << 16);
                auto_metadata_high_write_reg._next = true;
            }
            packet_command_valid_reg._next = true;
            auto_sequence_reg._next = auto_sequence_reg + 1;
            pop = true;
        }

        if (pop) {
            next_head = ((uint32_t)head_reg + 1) & (DEPTH - 1);
            head_reg._next = next_head;
            --count;
        }

        if (input_fire) {
            assembly = queue_write_data_comb_func();
            word_index = (uint32_t)descriptor_word_in();
            if (word_index >= DESCRIPTOR_WORDS) {
                word_index = 0;
                protocol_error_reg._next = true;
            }
            if (descriptor_sop_in()) {
                if (assembly_active_reg || (uint32_t)descriptor_word_in() != 0) {
                    protocol_error_reg._next = true;
                }
                assembly_active_reg._next = true;
                assembly_word_reg._next = 0;
            }
            if (!assembly_active_reg && !descriptor_sop_in()) {
                protocol_error_reg._next = true;
            }
            if ((uint32_t)descriptor_word_in() != (uint32_t)assembly_word_reg) {
                protocol_error_reg._next = true;
            }
            // A loop keeps the generated part-select width constant; cpphdl's
            // dynamic `.bits(high, low)` lowering otherwise makes Verilator
            // treat the width expression as non-constant.
            assembly_reg._next = assembly;
            if (descriptor_eop_in()) {
                if ((uint32_t)descriptor_word_in() != DESCRIPTOR_WORDS - 1) {
                    protocol_error_reg._next = true;
                }
                tail_reg._next = ((uint32_t)tail_reg + 1) & (DEPTH - 1);
                ++count;
                assembly_active_reg._next = false;
                assembly_word_reg._next = 0;
            }
            else {
                assembly_word_reg._next = descriptor_word_in() + 1;
            }
        }
        count_reg._next = count;

        if (reset) {
            head_reg.clr();
            tail_reg.clr();
            count_reg.clr();
            assembly_reg.clr();
            assembly_word_reg.clr();
            assembly_active_reg.clr();
            enabled_reg.clr();
            auto_l2_reg.clr();
            auto_slot_mask_reg._next = 511;
            auto_base_reg.clr();
            auto_sequence_reg.clr();
            protocol_error_reg.clr();
            packet_command_valid_reg.clr();
            packet_command_handle_reg.clr();
            packet_command_length_reg.clr();
            packet_command_system_reg.clr();
            packet_command_cache_reg.clr();
            packet_command_network_reg.clr();
            packet_command_network_port_reg.clr();
            packet_command_destination_reg.clr();
            action_destination_reg.clr();
            auto_metadata_write_reg.clr();
            auto_metadata_slot_reg.clr();
            auto_metadata_low_reg.clr();
            auto_metadata_high_even_reg.clr();
            auto_metadata_high_write_reg.clr();
            auto_metadata_high_addr_reg.clr();
            auto_metadata_high_data_reg.clr();
            write_addr_reg.clr();
            write_id_reg.clr();
            write_addr_valid_reg.clr();
            write_response_valid_reg.clr();
            read_id_reg.clr();
            read_addr_reg.clr();
            read_value_reg.clr();
            read_lane_reg.clr();
            read_pending_reg.clr();
            read_format_pending_reg.clr();
            read_data_reg.clr();
            read_valid_reg.clr();
        }
    }

    void _strobe()
    {
        queue_mem._strobe();
        auto_destination_low_mem._strobe();
        auto_destination_high_mem._strobe();
        head_reg.strobe();
        tail_reg.strobe();
        count_reg.strobe();
        assembly_reg.strobe();
        assembly_word_reg.strobe();
        assembly_active_reg.strobe();
        enabled_reg.strobe();
        auto_l2_reg.strobe();
        auto_slot_mask_reg.strobe();
        auto_base_reg.strobe();
        auto_sequence_reg.strobe();
        protocol_error_reg.strobe();
        packet_command_valid_reg.strobe();
        packet_command_handle_reg.strobe();
        packet_command_length_reg.strobe();
        packet_command_system_reg.strobe();
        packet_command_cache_reg.strobe();
        packet_command_network_reg.strobe();
        packet_command_network_port_reg.strobe();
        packet_command_destination_reg.strobe();
        action_destination_reg.strobe();
        auto_metadata_write_reg.strobe();
        auto_metadata_slot_reg.strobe();
        auto_metadata_low_reg.strobe();
        auto_metadata_high_even_reg.strobe();
        auto_metadata_high_write_reg.strobe();
        auto_metadata_high_addr_reg.strobe();
        auto_metadata_high_data_reg.strobe();
        write_addr_reg.strobe();
        write_id_reg.strobe();
        write_addr_valid_reg.strobe();
        write_response_valid_reg.strobe();
        read_id_reg.strobe();
        read_addr_reg.strobe();
        read_value_reg.strobe();
        read_lane_reg.strobe();
        read_pending_reg.strobe();
        read_format_pending_reg.strobe();
        read_data_reg.strobe();
        read_valid_reg.strobe();
    }
};

template class DescriptorFetcher<4, 32, 4, 256, PACKET_HANDLE_BITS>;
