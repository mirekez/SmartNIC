#pragma once

// Per-CPU receive-descriptor prefetch queue.  The processing dispatcher sends
// one complete five-word descriptor to exactly one instance.  Software reads
// the current descriptor through an uncached 256-bit AXI MMIO window and pops
// it explicitly, so speculative/cacheable loads cannot consume queue state.

#include "../network/RxFifo.h"
#include "../../cpphdl/tribe_cpu/common/Axi4.h"

using namespace cpphdl;

template<size_t DEPTH = 4, size_t AXI_ADDR_WIDTH = 32,
    size_t AXI_ID_WIDTH = 4, size_t AXI_DATA_WIDTH = 256,
    size_t HANDLE_BITS = 16>
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
        REG_PROTOCOL = 0x13c
    };

    static constexpr uint32_t CONTROL_ENABLE = 1u << 0;
    static constexpr uint32_t ACTION_NEXT = 1u << 0;
    static constexpr uint32_t ACTION_DMA_DISCARD = 1u << 1;
    static constexpr uint32_t ACTION_DMA_SYSTEM = 1u << 2;
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

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> mmio;

    _PORT(bool) descriptor_available_out;
    _PORT(u<COUNT_BITS>) descriptor_count_out;
    _PORT(bool) prefetch_enabled_out;
    _PORT(bool) protocol_error_out;

private:
    reg<logic<DESCRIPTOR_BITS>> queue_reg[DEPTH];
    reg<u<PTR_BITS>> head_reg;
    reg<u<PTR_BITS>> tail_reg;
    reg<u<COUNT_BITS>> count_reg;
    reg<logic<DESCRIPTOR_BITS>> assembly_reg;
    reg<u<3>> assembly_word_reg;
    reg<u1> assembly_active_reg;
    reg<u1> enabled_reg;
    reg<u1> protocol_error_reg;
    reg<u1> packet_command_valid_reg;
    reg<u<HANDLE_BITS>> packet_command_handle_reg;
    reg<u<14>> packet_command_length_reg;
    reg<u1> packet_command_system_reg;

    reg<u<AXI_ADDR_WIDTH>> write_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_id_reg;
    reg<u1> write_addr_valid_reg;
    reg<u1> write_response_valid_reg;
    reg<u<AXI_ID_WIDTH>> read_id_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    logic<DESCRIPTOR_BITS> current_descriptor_comb;
    logic<AXI_DATA_WIDTH> register_read_comb;

    logic<DESCRIPTOR_BITS>& current_descriptor_comb_func()
    {
        current_descriptor_comb = 0;
        if ((uint32_t)count_reg != 0) {
            current_descriptor_comb = queue_reg[(uint32_t)head_reg];
        }
        return current_descriptor_comb;
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
            return (bool)enabled_reg ? CONTROL_ENABLE : 0;
        }
        if (address == REG_STATUS) {
            return ((uint32_t)count_reg != 0 ? STATUS_AVAILABLE : 0)
                | ((bool)enabled_reg ? STATUS_PREFETCH_ENABLED : 0)
                | ((bool)protocol_error_reg ? STATUS_PROTOCOL_ERROR : 0)
                | (packet_command_ready_in() ? STATUS_DMA_READY : 0)
                | ((uint32_t)count_reg << 8);
        }
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
    void _assign()
    {
        descriptor_ready_out = _ASSIGN((bool)enabled_reg
            && (uint32_t)count_reg < DEPTH);
        descriptor_available_out = _ASSIGN((uint32_t)count_reg != 0);
        descriptor_count_out = _ASSIGN_REG(count_reg);
        prefetch_enabled_out = _ASSIGN_REG(enabled_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
        packet_command_valid_out = _ASSIGN_REG(packet_command_valid_reg);
        packet_command_handle_out = _ASSIGN_REG(packet_command_handle_reg);
        packet_command_length_out = _ASSIGN_REG(packet_command_length_reg);
        packet_command_system_out = _ASSIGN_REG(packet_command_system_reg);

        mmio.awready_out = _ASSIGN(!write_addr_valid_reg
            && !write_response_valid_reg);
        mmio.wready_out = _ASSIGN(write_addr_valid_reg
            && !write_response_valid_reg);
        mmio.bvalid_out = _ASSIGN_REG(write_response_valid_reg);
        mmio.bid_out = _ASSIGN_REG(write_id_reg);
        mmio.arready_out = _ASSIGN(!read_valid_reg);
        mmio.rvalid_out = _ASSIGN_REG(read_valid_reg);
        mmio.rdata_out = _ASSIGN_REG(read_data_reg);
        mmio.rlast_out = _ASSIGN_REG(read_valid_reg);
        mmio.rid_out = _ASSIGN_REG(read_id_reg);
    }

    void _work(bool reset)
    {
        uint32_t slot;
        uint32_t count;
        uint32_t address;
        uint32_t value;
        uint32_t bit;
        uint32_t word_index;
        bool input_fire;
        bool pop;
        logic<DESCRIPTOR_BITS> assembly;

        count = (uint32_t)count_reg;
        pop = false;
        input_fire = descriptor_valid_in() && descriptor_ready_out();
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
            }
            else if (address == REG_ACTION && (value & ACTION_NEXT) != 0) {
                if ((value & (ACTION_DMA_DISCARD | ACTION_DMA_SYSTEM)) == 0) {
                    pop = count != 0;
                }
                else if (count != 0 && packet_command_ready_in()
                    && !((value & ACTION_DMA_DISCARD) != 0
                        && (value & ACTION_DMA_SYSTEM) != 0)) {
                    packet_command_handle_reg._next = descriptor_bits32(0);
                    packet_command_length_reg._next = descriptor_bits32(32);
                    packet_command_system_reg._next =
                        (value & ACTION_DMA_SYSTEM) != 0;
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
            read_data_reg._next = register_read_comb_func();
            read_valid_reg._next = true;
        }
        if (read_valid_reg && mmio.rready_in()) {
            read_valid_reg._next = false;
        }

        if (pop) {
            head_reg._next = ((uint32_t)head_reg + 1) & (DEPTH - 1);
            --count;
        }

        if (input_fire) {
            assembly = assembly_reg;
            word_index = (uint32_t)descriptor_word_in();
            if (word_index >= DESCRIPTOR_WORDS) {
                word_index = 0;
                protocol_error_reg._next = true;
            }
            if (descriptor_sop_in()) {
                if (assembly_active_reg || (uint32_t)descriptor_word_in() != 0) {
                    protocol_error_reg._next = true;
                }
                assembly = 0;
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
            for (bit = 0; bit < 256; ++bit) {
                assembly[word_index * 256 + bit] = descriptor_data_in()[bit];
            }
            assembly_reg._next = assembly;
            if (descriptor_eop_in()) {
                if ((uint32_t)descriptor_word_in() != DESCRIPTOR_WORDS - 1) {
                    protocol_error_reg._next = true;
                }
                queue_reg[(uint32_t)tail_reg]._next = assembly;
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
            protocol_error_reg.clr();
            packet_command_valid_reg.clr();
            packet_command_handle_reg.clr();
            packet_command_length_reg.clr();
            packet_command_system_reg.clr();
            write_addr_reg.clr();
            write_id_reg.clr();
            write_addr_valid_reg.clr();
            write_response_valid_reg.clr();
            read_id_reg.clr();
            read_data_reg.clr();
            read_valid_reg.clr();
            for (slot = 0; slot < DEPTH; ++slot) queue_reg[slot].clr();
        }
    }

    void _strobe()
    {
        uint32_t slot;
        for (slot = 0; slot < DEPTH; ++slot) queue_reg[slot].strobe();
        head_reg.strobe();
        tail_reg.strobe();
        count_reg.strobe();
        assembly_reg.strobe();
        assembly_word_reg.strobe();
        assembly_active_reg.strobe();
        enabled_reg.strobe();
        protocol_error_reg.strobe();
        packet_command_valid_reg.strobe();
        packet_command_handle_reg.strobe();
        packet_command_length_reg.strobe();
        packet_command_system_reg.strobe();
        write_addr_reg.strobe();
        write_id_reg.strobe();
        write_addr_valid_reg.strobe();
        write_response_valid_reg.strobe();
        read_id_reg.strobe();
        read_data_reg.strobe();
        read_valid_reg.strobe();
    }
};

template class DescriptorFetcher<4, 32, 4, 256, 16>;
