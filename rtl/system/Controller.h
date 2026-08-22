#pragma once

// Host-visible System controller.  It owns independent 1024-entry RX and TX
// descriptor rings, reports all eight packet queues, and issues one host DMA
// command at a time.  TX descriptors are scatter-gather fragments; bit zero
// of flags marks the fragment that ends the assembled TxQueue packet.

#include "../../Config.h"
#include "MasterDMA.h"
#include "../common/Memory.cpp"
#include "../../cpphdl/tribe_cpu/common/Axi4.h"

using namespace cpphdl;

struct SystemRingDescriptor
{
    u64 address;
    u16 length;
    u8 queue;
    u8 flags;
    u32 reserved;
} __PACKED;

union SystemRingDescriptorWord
{
    SystemRingDescriptor descriptor;
    logic<128> raw;
} __PACKED;

enum SystemControllerFlags : uint8_t
{
    SYSTEM_TX_DESCRIPTOR_EOP = 1u << 0
};

template<size_t QUEUES = SYSTEM_QUEUES, size_t RING_DEPTH = 1024,
    size_t DATA_WIDTH = HOST_DATA_WIDTH>
class Controller : public Module
{
public:
    static constexpr size_t DATA_BYTES = DATA_WIDTH / 8;
    static constexpr size_t RING_BITS = clog2(RING_DEPTH);
    static constexpr uint32_t REG_CONTROL = 0x0000;
    static constexpr uint32_t REG_STATUS = 0x0004;
    static constexpr uint32_t REG_RX_PRODUCER = 0x0010;
    static constexpr uint32_t REG_RX_CONSUMER = 0x0014;
    static constexpr uint32_t REG_TX_PRODUCER = 0x0018;
    static constexpr uint32_t REG_TX_CONSUMER = 0x001c;
    static constexpr uint32_t REG_COMPLETED = 0x0020;
    static constexpr uint32_t REG_QUEUE_BASE = 0x0100;
    static constexpr uint32_t REG_QUEUE_STRIDE = 0x20;
    static constexpr uint32_t REG_RX_RING_BASE = 0x10000;
    static constexpr uint32_t REG_TX_RING_BASE = 0x20000;
    static constexpr uint32_t RING_ENTRY_BYTES = 16;
    static constexpr uint32_t CONTROL_ENABLE = 1u << 0;

    static_assert(QUEUES == 1, "System controller exposes one queue pair");
    static_assert(RING_DEPTH == 1024,
        "Host ABI fixes RX and TX descriptor rings at 1024 entries");
    static_assert(sizeof(SystemRingDescriptor) == 16,
        "System ring descriptor is 128 bits");

    Axi4If<32, 4, DATA_WIDTH> host_control;

    _PORT(logic<QUEUES>) rx_empty_in;
    _PORT(logic<QUEUES * 16>) rx_packet_length_in;
    _PORT(logic<QUEUES>) tx_full_in;
    _PORT(logic<QUEUES * 16>) rx_packet_count_in;
    _PORT(logic<QUEUES * 16>) tx_packet_count_in;

    _PORT(bool) dma_command_valid_out;
    _PORT(bool) dma_command_ready_in;
    _PORT(bool) dma_command_direction_out;
    _PORT(u<3>) dma_command_queue_out;
    _PORT(u<HOST_ADDR_WIDTH>) dma_command_address_out;
    _PORT(u<16>) dma_command_length_out;
    _PORT(bool) dma_command_sop_out;
    _PORT(bool) dma_command_eop_out;
    _PORT(bool) dma_completion_valid_in;
    _PORT(u<3>) dma_completion_queue_in;
    _PORT(bool) dma_completion_direction_in;

    _PORT(logic<QUEUES>) rx_queue_empty_out;
    _PORT(u<RING_BITS>) rx_consumer_out;
    _PORT(u<RING_BITS>) tx_consumer_out;
    _PORT(bool) protocol_error_out;

private:
    SmartNicMemory<16, RING_DEPTH, true> rx_ring;
    SmartNicMemory<16, RING_DEPTH, true> tx_ring;
    reg<u1> enabled_reg;
    reg<u<RING_BITS>> rx_producer_reg;
    reg<u<RING_BITS>> rx_consumer_reg;
    reg<u<RING_BITS>> tx_producer_reg;
    reg<u<RING_BITS>> tx_consumer_reg;
    reg<u1> tx_packet_start_reg;
    reg<u<3>> tx_packet_queue_reg;
    reg<u1> command_valid_reg;
    reg<u1> command_direction_reg;
    reg<u<3>> command_queue_reg;
    reg<u<HOST_ADDR_WIDTH>> command_address_reg;
    reg<u<16>> command_length_reg;
    reg<u1> command_sop_reg;
    reg<u1> command_eop_reg;
    reg<u1> dma_active_reg;
    reg<u1> active_direction_reg;
    reg<u<32>> completed_reg;
    reg<u1> protocol_error_reg;

    reg<u32> write_address_reg;
    reg<u<4>> write_id_reg;
    reg<u1> write_address_valid_reg;
    reg<u1> write_response_valid_reg;
    reg<u<4>> read_id_reg;
    reg<logic<DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    logic<128> rx_ring_write_data_comb;
    logic<16> rx_ring_write_mask_comb;
    logic<128> tx_ring_write_data_comb;
    logic<16> tx_ring_write_mask_comb;
    logic<DATA_WIDTH> register_read_comb;
    u<RING_BITS> rx_ring_write_addr_comb;
    u<RING_BITS> rx_ring_read_addr_comb;
    u<RING_BITS> tx_ring_write_addr_comb;
    u<RING_BITS> tx_ring_read_addr_comb;
    bool rx_ring_write_comb;
    bool tx_ring_write_comb;

    uint32_t bus_write_address()
    {
        return (uint32_t)write_address_reg;
    }

    bool bus_write_fire()
    {
        return host_control.wvalid_in() && host_control.wready_out();
    }

    logic<DATA_WIDTH> bus_write_data()
    {
        return host_control.wdata_in();
    }

    logic<DATA_BYTES> bus_write_mask()
    {
        return host_control.wstrb_in();
    }

    uint32_t write_word_value()
    {
        uint32_t address;
        uint32_t lane;
        address = bus_write_address();
        lane = address & (DATA_BYTES - 1);
        return (uint32_t)bus_write_data().bits(lane * 8 + 31, lane * 8);
    }

    uint32_t bus_read_address()
    {
        return (uint32_t)host_control.araddr_in();
    }

    bool bus_read_fire()
    {
        return host_control.arvalid_in() && host_control.arready_out();
    }

    bool address_in_ring(uint32_t address, uint32_t base)
    {
        return address >= base
            && address < base + RING_DEPTH * RING_ENTRY_BYTES;
    }

    uint32_t ring_index(uint32_t address, uint32_t base)
    {
        return (address - base) / RING_ENTRY_BYTES;
    }

    uint32_t ring_word(uint32_t address, uint32_t base)
    {
        return ((address - base) & (RING_ENTRY_BYTES - 1)) / 4;
    }

    logic<128>& rx_ring_write_data_comb_func()
    {
        uint32_t bit;
        uint32_t word;
        uint32_t value;
        rx_ring_write_data_comb = 0;
        word = ring_word(bus_write_address(), REG_RX_RING_BASE);
        value = write_word_value();
        for (bit = 0; bit < 32; ++bit) {
            rx_ring_write_data_comb[word * 32 + bit] = (value >> bit) & 1u;
        }
        return rx_ring_write_data_comb;
    }

    logic<16>& rx_ring_write_mask_comb_func()
    {
        uint32_t byte;
        uint32_t word;
        uint32_t lane;
        rx_ring_write_mask_comb = 0;
        word = ring_word(bus_write_address(), REG_RX_RING_BASE);
        lane = bus_write_address() & (DATA_BYTES - 1);
        for (byte = 0; byte < 4; ++byte) {
            rx_ring_write_mask_comb[word * 4 + byte] =
                bus_write_mask()[lane + byte];
        }
        return rx_ring_write_mask_comb;
    }

    logic<128>& tx_ring_write_data_comb_func()
    {
        uint32_t bit;
        uint32_t word;
        uint32_t value;
        tx_ring_write_data_comb = 0;
        word = ring_word(bus_write_address(), REG_TX_RING_BASE);
        value = write_word_value();
        for (bit = 0; bit < 32; ++bit) {
            tx_ring_write_data_comb[word * 32 + bit] = (value >> bit) & 1u;
        }
        return tx_ring_write_data_comb;
    }

    logic<16>& tx_ring_write_mask_comb_func()
    {
        uint32_t byte;
        uint32_t word;
        uint32_t lane;
        tx_ring_write_mask_comb = 0;
        word = ring_word(bus_write_address(), REG_TX_RING_BASE);
        lane = bus_write_address() & (DATA_BYTES - 1);
        for (byte = 0; byte < 4; ++byte) {
            tx_ring_write_mask_comb[word * 4 + byte] =
                bus_write_mask()[lane + byte];
        }
        return tx_ring_write_mask_comb;
    }

    uint32_t descriptor_word_value(logic<128> descriptor, uint32_t word)
    {
        uint32_t bit;
        uint32_t value;
        value = 0;
        for (bit = 0; bit < 32; ++bit) {
            if (descriptor[word * 32 + bit]) value |= 1u << bit;
        }
        return value;
    }

    uint32_t queue_value(logic<QUEUES * 16> values, uint32_t queue)
    {
        uint32_t bit;
        uint32_t value;
        value = 0;
        for (bit = 0; bit < 16; ++bit) {
            if (values[queue * 16 + bit]) value |= 1u << bit;
        }
        return value;
    }

    bool descriptor_address_valid(u64 address)
    {
        return ((uint64_t)address >> HOST_ADDR_WIDTH) == 0;
    }

    uint32_t register_value(uint32_t address)
    {
        uint32_t queue;
        uint32_t offset;
        if (address == REG_CONTROL) return enabled_reg ? CONTROL_ENABLE : 0;
        if (address == REG_STATUS) {
            return ((bool)dma_active_reg ? 1u : 0u)
                | ((bool)command_valid_reg ? 2u : 0u)
                | ((bool)protocol_error_reg ? 4u : 0u);
        }
        if (address == REG_RX_PRODUCER) return (uint32_t)rx_producer_reg;
        if (address == REG_RX_CONSUMER) return (uint32_t)rx_consumer_reg;
        if (address == REG_TX_PRODUCER) return (uint32_t)tx_producer_reg;
        if (address == REG_TX_CONSUMER) return (uint32_t)tx_consumer_reg;
        if (address == REG_COMPLETED) return (uint32_t)completed_reg;
        if (address >= REG_QUEUE_BASE
            && address < REG_QUEUE_BASE + QUEUES * REG_QUEUE_STRIDE) {
            queue = (address - REG_QUEUE_BASE) / REG_QUEUE_STRIDE;
            offset = (address - REG_QUEUE_BASE) & (REG_QUEUE_STRIDE - 1);
            if (offset == 0) {
                return (rx_empty_in()[queue] ? 1u : 0u)
                    | (tx_full_in()[queue] ? 2u : 0u);
            }
            if (offset == 4) return queue_value(rx_packet_count_in(), queue);
            if (offset == 8) return queue_value(tx_packet_count_in(), queue);
            if (offset == 12) return queue_value(rx_packet_length_in(), queue);
        }
        if (address_in_ring(address, REG_RX_RING_BASE)) {
            return descriptor_word_value(rx_ring.read_data_out(),
                ring_word(address, REG_RX_RING_BASE));
        }
        if (address_in_ring(address, REG_TX_RING_BASE)) {
            return descriptor_word_value(tx_ring.read_data_out(),
                ring_word(address, REG_TX_RING_BASE));
        }
        return 0;
    }

    logic<DATA_WIDTH>& register_read_comb_func()
    {
        uint32_t address;
        uint32_t lane;
        uint32_t bit;
        uint32_t value;
        register_read_comb = 0;
        address = bus_read_address();
        lane = address & (DATA_BYTES - 1);
        value = register_value(address & ~3u);
        for (bit = 0; bit < 32; ++bit) {
            register_read_comb[lane * 8 + bit] = (value >> bit) & 1u;
        }
        return register_read_comb;
    }

    uint32_t selected_ring_read_address(uint32_t base, uint32_t consumer)
    {
        uint32_t address;
        address = bus_read_address();
        if (bus_read_fire() && address_in_ring(address, base)) {
            return ring_index(address, base);
        }
        return consumer;
    }

    u<RING_BITS>& rx_ring_write_addr_comb_func()
    {
        rx_ring_write_addr_comb = ring_index(bus_write_address(),
            REG_RX_RING_BASE);
        return rx_ring_write_addr_comb;
    }

    u<RING_BITS>& rx_ring_read_addr_comb_func()
    {
        rx_ring_read_addr_comb = selected_ring_read_address(REG_RX_RING_BASE,
            (uint32_t)rx_consumer_reg);
        return rx_ring_read_addr_comb;
    }

    u<RING_BITS>& tx_ring_write_addr_comb_func()
    {
        tx_ring_write_addr_comb = ring_index(bus_write_address(),
            REG_TX_RING_BASE);
        return tx_ring_write_addr_comb;
    }

    u<RING_BITS>& tx_ring_read_addr_comb_func()
    {
        tx_ring_read_addr_comb = selected_ring_read_address(REG_TX_RING_BASE,
            (uint32_t)tx_consumer_reg);
        return tx_ring_read_addr_comb;
    }

    bool& rx_ring_write_comb_func()
    {
        rx_ring_write_comb = bus_write_fire()
            && address_in_ring(bus_write_address(), REG_RX_RING_BASE);
        return rx_ring_write_comb;
    }

    bool& tx_ring_write_comb_func()
    {
        tx_ring_write_comb = bus_write_fire()
            && address_in_ring(bus_write_address(), REG_TX_RING_BASE);
        return tx_ring_write_comb;
    }

public:
    void _assign()
    {
        rx_ring.write_addr_in = _ASSIGN_COMB(rx_ring_write_addr_comb_func());
        rx_ring.write_in = _ASSIGN_COMB(rx_ring_write_comb_func());
        rx_ring.write_data_in = _ASSIGN_COMB(rx_ring_write_data_comb_func());
        rx_ring.write_mask_in = _ASSIGN_COMB(rx_ring_write_mask_comb_func());
        rx_ring.read_addr_in = _ASSIGN_COMB(rx_ring_read_addr_comb_func());
        rx_ring.read_in = _ASSIGN(true);

        tx_ring.write_addr_in = _ASSIGN_COMB(tx_ring_write_addr_comb_func());
        tx_ring.write_in = _ASSIGN_COMB(tx_ring_write_comb_func());
        tx_ring.write_data_in = _ASSIGN_COMB(tx_ring_write_data_comb_func());
        tx_ring.write_mask_in = _ASSIGN_COMB(tx_ring_write_mask_comb_func());
        tx_ring.read_addr_in = _ASSIGN_COMB(tx_ring_read_addr_comb_func());
        tx_ring.read_in = _ASSIGN(true);
#ifndef SYNTHESIS
        rx_ring.__inst_name = __inst_name + "/rx_ring";
        tx_ring.__inst_name = __inst_name + "/tx_ring";
#endif
        rx_ring._assign();
        tx_ring._assign();

        host_control.awready_out = _ASSIGN(!write_address_valid_reg
            && !write_response_valid_reg);
        host_control.wready_out = _ASSIGN(write_address_valid_reg
            && !write_response_valid_reg);
        host_control.bvalid_out = _ASSIGN_REG(write_response_valid_reg);
        host_control.bid_out = _ASSIGN_REG(write_id_reg);
        host_control.arready_out = _ASSIGN(!read_valid_reg);
        host_control.rvalid_out = _ASSIGN_REG(read_valid_reg);
        host_control.rdata_out = _ASSIGN_REG(read_data_reg);
        host_control.rlast_out = _ASSIGN_REG(read_valid_reg);
        host_control.rid_out = _ASSIGN_REG(read_id_reg);

        dma_command_valid_out = _ASSIGN_REG(command_valid_reg);
        dma_command_direction_out = _ASSIGN((bool)command_direction_reg);
        dma_command_queue_out = _ASSIGN_REG(command_queue_reg);
        dma_command_address_out = _ASSIGN_REG(command_address_reg);
        dma_command_length_out = _ASSIGN_REG(command_length_reg);
        dma_command_sop_out = _ASSIGN_REG(command_sop_reg);
        dma_command_eop_out = _ASSIGN_REG(command_eop_reg);
        rx_queue_empty_out = rx_empty_in;
        rx_consumer_out = _ASSIGN_REG(rx_consumer_reg);
        tx_consumer_out = _ASSIGN_REG(tx_consumer_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work(bool reset)
    {
        uint32_t address;
        uint32_t value;
        uint32_t queue;
        uint32_t packet_length;
        SystemRingDescriptorWord descriptor;

        if (host_control.awvalid_in() && host_control.awready_out()) {
            write_address_reg._next = host_control.awaddr_in();
            write_id_reg._next = host_control.awid_in();
            write_address_valid_reg._next = true;
        }
        if (host_control.wvalid_in() && host_control.wready_out()) {
            write_address_valid_reg._next = false;
            write_response_valid_reg._next = true;
        }
        if (write_response_valid_reg && host_control.bready_in()) {
            write_response_valid_reg._next = false;
        }
        if (host_control.arvalid_in() && host_control.arready_out()) {
            read_id_reg._next = host_control.arid_in();
            read_data_reg._next = register_read_comb_func();
            read_valid_reg._next = true;
        }
        if (read_valid_reg && host_control.rready_in()) read_valid_reg._next = false;

        if (bus_write_fire()) {
            address = bus_write_address() & ~3u;
            value = write_word_value();
            if (address == REG_CONTROL) enabled_reg._next = value & CONTROL_ENABLE;
            else if (address == REG_RX_PRODUCER) rx_producer_reg._next = value;
            else if (address == REG_TX_PRODUCER) tx_producer_reg._next = value;
        }

        if (command_valid_reg && dma_command_ready_in()) {
            command_valid_reg._next = false;
            dma_active_reg._next = true;
            active_direction_reg._next = command_direction_reg;
        }
        if (dma_completion_valid_in()) {
            if (!dma_active_reg
                || dma_completion_direction_in() != active_direction_reg
                || dma_completion_queue_in() != command_queue_reg) {
                protocol_error_reg._next = true;
            }
            else if (active_direction_reg == MASTER_DMA_QUEUE_TO_HOST) {
                rx_consumer_reg._next = rx_consumer_reg + 1;
            }
            else {
                tx_consumer_reg._next = tx_consumer_reg + 1;
                tx_packet_start_reg._next = command_eop_reg;
            }
            dma_active_reg._next = false;
            completed_reg._next = completed_reg + 1;
        }

        // Do not inspect show-ahead ring data during a host readback cycle,
        // because that cycle temporarily owns the ring's read address.
        if (enabled_reg && !command_valid_reg && !dma_active_reg
            && !bus_read_fire()) {
            if ((uint32_t)rx_consumer_reg != (uint32_t)rx_producer_reg) {
                descriptor.raw = rx_ring.read_data_out();
                queue = (uint32_t)descriptor.descriptor.queue;
                packet_length = 0;
                if (queue < QUEUES) {
                    packet_length = queue_value(rx_packet_length_in(), queue);
                }
                if (queue < QUEUES && !rx_empty_in()[queue]
                    && packet_length != 0
                    && descriptor_address_valid(descriptor.descriptor.address)
                    && (uint32_t)descriptor.descriptor.length >= packet_length) {
                    command_direction_reg._next = MASTER_DMA_QUEUE_TO_HOST;
                    command_queue_reg._next = queue;
                    command_address_reg._next =
                        (u<HOST_ADDR_WIDTH>)descriptor.descriptor.address;
                    command_length_reg._next = packet_length;
                    command_sop_reg._next = true;
                    command_eop_reg._next = true;
                    command_valid_reg._next = true;
                }
                else if (queue >= QUEUES
                    || !descriptor_address_valid(descriptor.descriptor.address)
                    || ((uint32_t)descriptor.descriptor.length < packet_length
                        && packet_length != 0)) {
                    protocol_error_reg._next = true;
                }
            }
            else if ((uint32_t)tx_consumer_reg != (uint32_t)tx_producer_reg) {
                descriptor.raw = tx_ring.read_data_out();
                queue = (uint32_t)descriptor.descriptor.queue;
                if (queue < QUEUES && !tx_full_in()[queue]
                    && (uint32_t)descriptor.descriptor.length != 0
                    && descriptor_address_valid(descriptor.descriptor.address)
                    && ((bool)tx_packet_start_reg
                        || queue == (uint32_t)tx_packet_queue_reg)) {
                    command_direction_reg._next = MASTER_DMA_HOST_TO_QUEUE;
                    command_queue_reg._next = queue;
                    command_address_reg._next =
                        (u<HOST_ADDR_WIDTH>)descriptor.descriptor.address;
                    command_length_reg._next = descriptor.descriptor.length;
                    command_sop_reg._next = tx_packet_start_reg;
                    command_eop_reg._next =
                        ((uint32_t)descriptor.descriptor.flags
                            & SYSTEM_TX_DESCRIPTOR_EOP) != 0;
                    command_valid_reg._next = true;
                    if (tx_packet_start_reg) tx_packet_queue_reg._next = queue;
                }
                else if (queue >= QUEUES
                    || !descriptor_address_valid(descriptor.descriptor.address)
                    || (!(bool)tx_packet_start_reg
                        && queue != (uint32_t)tx_packet_queue_reg)) {
                    protocol_error_reg._next = true;
                }
            }
        }

        rx_ring._work(reset);
        tx_ring._work(reset);
        if (reset) {
            enabled_reg.clr();
            rx_producer_reg.clr();
            rx_consumer_reg.clr();
            tx_producer_reg.clr();
            tx_consumer_reg.clr();
            tx_packet_start_reg._next = true;
            tx_packet_queue_reg.clr();
            command_valid_reg.clr();
            command_direction_reg.clr();
            command_queue_reg.clr();
            command_address_reg.clr();
            command_length_reg.clr();
            command_sop_reg.clr();
            command_eop_reg.clr();
            dma_active_reg.clr();
            active_direction_reg.clr();
            completed_reg.clr();
            protocol_error_reg.clr();
            write_address_reg.clr();
            write_id_reg.clr();
            write_address_valid_reg.clr();
            write_response_valid_reg.clr();
            read_id_reg.clr();
            read_data_reg.clr();
            read_valid_reg.clr();
        }
    }

    void _strobe()
    {
        rx_ring._strobe();
        tx_ring._strobe();
        enabled_reg.strobe();
        rx_producer_reg.strobe();
        rx_consumer_reg.strobe();
        tx_producer_reg.strobe();
        tx_consumer_reg.strobe();
        tx_packet_start_reg.strobe();
        tx_packet_queue_reg.strobe();
        command_valid_reg.strobe();
        command_direction_reg.strobe();
        command_queue_reg.strobe();
        command_address_reg.strobe();
        command_length_reg.strobe();
        command_sop_reg.strobe();
        command_eop_reg.strobe();
        dma_active_reg.strobe();
        active_direction_reg.strobe();
        completed_reg.strobe();
        protocol_error_reg.strobe();
        write_address_reg.strobe();
        write_id_reg.strobe();
        write_address_valid_reg.strobe();
        write_response_valid_reg.strobe();
        read_id_reg.strobe();
        read_data_reg.strobe();
        read_valid_reg.strobe();
    }
};

template class Controller<SYSTEM_QUEUES, 1024, HOST_DATA_WIDTH>;
