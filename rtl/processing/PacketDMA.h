#pragma once

// Per-cluster packet DMA.  Commands select one of four paths between the
// coherent Tribe L2 port, network RxRAM/TxFIFO, and the corresponding System
// RxQueue/TxQueue.  The command FIFO and MMIO registers are uncached CPU IOMEM.

#include "../common/Axi4Master.h"

#ifndef SYNTHESIS
#include <print>
#endif

using namespace cpphdl;

enum PacketDmaOperation : uint8_t
{
    DMA_SYSTEM_CPU = 0,
    DMA_CPU_SYSTEM = 1,
    DMA_CPU_NETWORK = 2,
    DMA_NETWORK_CPU = 3
};

enum PacketDmaState : uint8_t
{
    PACKET_DMA_IDLE,
    PACKET_DMA_ISSUE_NETWORK_READ,
    PACKET_DMA_WAIT_INPUT,
    PACKET_DMA_WRITE_ADDRESS,
    PACKET_DMA_WRITE_DATA,
    PACKET_DMA_WRITE_RESPONSE,
    PACKET_DMA_READ_ADDRESS,
    PACKET_DMA_READ_DATA,
    PACKET_DMA_SEND_OUTPUT
};

enum PacketDmaError : uint8_t
{
    PACKET_DMA_ERROR_NONE,
    PACKET_DMA_ERROR_COMMAND_QUEUE_FULL,
    PACKET_DMA_ERROR_ZERO_LENGTH,
    PACKET_DMA_ERROR_FLAGS,
    PACKET_DMA_ERROR_DESTINATION_ALIGNMENT,
    PACKET_DMA_ERROR_SOURCE_ALIGNMENT,
    PACKET_DMA_ERROR_KEEP_GAP,
    PACKET_DMA_ERROR_SOP,
    PACKET_DMA_ERROR_BEAT_LENGTH,
    PACKET_DMA_ERROR_EOP_LENGTH,
    PACKET_DMA_ERROR_NON_EOP_LENGTH
};

template<size_t HANDLE_BITS = 16, size_t FRAME_LENGTH_BITS = 14,
    size_t CMD_DEPTH = 8, size_t AXI_ADDR_WIDTH = 32,
    size_t AXI_ID_WIDTH = 4, size_t AXI_DATA_WIDTH = 256>
class PacketDMA : public Module
{
public:
    static constexpr size_t AXI_BYTES = AXI_DATA_WIDTH / 8;
    static constexpr size_t CMD_PTR_BITS = CMD_DEPTH <= 1 ? 1 : clog2(CMD_DEPTH);
    static constexpr size_t CMD_COUNT_BITS = clog2(CMD_DEPTH + 1);

    static_assert(AXI_DATA_WIDTH == 256,
        "PacketDMA is matched to the Tribe 256-bit coherent L2 port");
    static_assert(CMD_DEPTH >= 2 && (CMD_DEPTH & (CMD_DEPTH - 1)) == 0,
        "PacketDMA command depth must be a power of two");

    enum Register : uint32_t
    {
        REG_RX_HANDLE = 0x00,
        REG_LENGTH = 0x04,
        REG_DESTINATION = 0x08,
        REG_FLAGS = 0x0c,
        REG_COMMAND = 0x10,
        REG_STATUS = 0x14,
        REG_COMPLETED = 0x18,
        REG_SOURCE = 0x1c,
        REG_LAST_OPERATION = 0x20
    };

    static constexpr uint32_t COMMAND_PUSH = 1u << 0;
    static constexpr uint32_t FLAG_OPERATION_MASK = 3u;
    static constexpr uint32_t FLAG_CACHE_ALLOCATE = 1u << 2;
    // Network ingress fast paths avoid forcing every packet through the L2
    // AXI transaction path. DISCARD drains an unselected RxRAM packet;
    // NETWORK_SYSTEM streams a selected packet directly to its System queue.
    static constexpr uint32_t FLAG_NETWORK_DISCARD = 1u << 3;
    static constexpr uint32_t FLAG_NETWORK_SYSTEM = 1u << 4;
    static constexpr uint32_t STATUS_BUSY = 1u << 0;
    static constexpr uint32_t STATUS_CMD_READY = 1u << 1;
    static constexpr uint32_t STATUS_ERROR = 1u << 2;

    struct Command
    {
        u<HANDLE_BITS> handle;
        u<FRAME_LENGTH_BITS> length;
        u32 source;
        u32 destination;
        u8 flags;
    } __PACKED;

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> mmio;
    Axi4MasterIf<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> l2_dma;

    // Network/RxRAM command and response path (DMA_NETWORK_CPU).
    _PORT(bool) rx_read_valid_out;
    _PORT(u<HANDLE_BITS>) rx_read_handle_out;
    _PORT(u<FRAME_LENGTH_BITS>) rx_read_length_out;
    _PORT(bool) rx_read_ready_in;
    _PORT(bool) rx_valid_in;
    _PORT(logic<AXI_DATA_WIDTH>) rx_data_in;
    _PORT(logic<AXI_BYTES>) rx_keep_in;
    _PORT(bool) rx_sop_in;
    _PORT(bool) rx_eop_in;
    _PORT(bool) rx_ready_out;

    // System TxQueue to CPU L2 path (DMA_SYSTEM_CPU).
    _PORT(bool) system_rx_valid_in;
    _PORT(logic<AXI_DATA_WIDTH>) system_rx_data_in;
    _PORT(logic<AXI_BYTES>) system_rx_keep_in;
    _PORT(bool) system_rx_sop_in;
    _PORT(bool) system_rx_eop_in;
    _PORT(bool) system_rx_ready_out;

    // CPU L2 to System RxQueue path (DMA_CPU_SYSTEM).
    _PORT(bool) system_tx_valid_out;
    _PORT(logic<AXI_DATA_WIDTH>) system_tx_data_out;
    _PORT(logic<AXI_BYTES>) system_tx_keep_out;
    _PORT(bool) system_tx_sop_out;
    _PORT(bool) system_tx_eop_out;
    _PORT(bool) system_tx_ready_in;

    // CPU L2 to Network TxFIFO path (DMA_CPU_NETWORK).
    _PORT(bool) network_tx_valid_out;
    _PORT(logic<AXI_DATA_WIDTH>) network_tx_data_out;
    _PORT(logic<AXI_BYTES>) network_tx_keep_out;
    _PORT(bool) network_tx_sop_out;
    _PORT(bool) network_tx_eop_out;
    _PORT(bool) network_tx_ready_in;

    _PORT(bool) busy_out;
    _PORT(bool) command_ready_out;
    _PORT(bool) descriptor_command_valid_in;
    _PORT(u<HANDLE_BITS>) descriptor_command_handle_in;
    _PORT(u<FRAME_LENGTH_BITS>) descriptor_command_length_in;
    _PORT(bool) descriptor_command_system_in;
    _PORT(u<32>) completed_count_out;
    _PORT(u<2>) last_operation_out;
    _PORT(bool) protocol_error_out;
    _PORT(u<4>) protocol_error_reason_out;

private:
    reg<Command> command_reg[CMD_DEPTH];
    reg<u<CMD_PTR_BITS>> command_head_reg;
    reg<u<CMD_PTR_BITS>> command_tail_reg;
    reg<u<CMD_COUNT_BITS>> command_count_reg;

    reg<u<HANDLE_BITS>> stage_handle_reg;
    reg<u<FRAME_LENGTH_BITS>> stage_length_reg;
    reg<u32> stage_source_reg;
    reg<u32> stage_destination_reg;
    reg<u8> stage_flags_reg;

    reg<u8> state_reg;
    reg<u<2>> operation_reg;
    reg<u8> active_flags_reg;
    reg<u<AXI_ADDR_WIDTH>> source_reg;
    reg<u<AXI_ADDR_WIDTH>> destination_reg;
    reg<u<FRAME_LENGTH_BITS>> remaining_reg;
    reg<logic<AXI_DATA_WIDTH>> beat_data_reg;
    reg<logic<AXI_BYTES>> beat_keep_reg;
    reg<u1> beat_sop_reg;
    reg<u1> beat_eop_reg;
    reg<u1> first_beat_reg;
    reg<u<32>> completed_reg;
    reg<u<2>> last_operation_reg;
    reg<u1> protocol_error_reg;
    reg<u<4>> protocol_error_reason_reg;

    reg<u<AXI_ADDR_WIDTH>> write_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_id_reg;
    reg<u1> write_addr_valid_reg;
    reg<u1> write_response_valid_reg;
    reg<u<AXI_ID_WIDTH>> read_id_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    u<HANDLE_BITS> current_handle_comb;
    u<FRAME_LENGTH_BITS> current_length_comb;
    logic<AXI_BYTES> output_keep_comb;

    Command current_command()
    {
        Command command = {};
        if ((uint32_t)command_count_reg != 0) {
            command = command_reg[(uint32_t)command_head_reg];
        }
        return command;
    }

    u<HANDLE_BITS>& current_handle_comb_func()
    {
        current_handle_comb = 0;
        if ((uint32_t)command_count_reg != 0) {
            current_handle_comb = command_reg[(uint32_t)command_head_reg].handle;
        }
        return current_handle_comb;
    }

    u<FRAME_LENGTH_BITS>& current_length_comb_func()
    {
        current_length_comb = 0;
        if ((uint32_t)command_count_reg != 0) {
            current_length_comb = command_reg[(uint32_t)command_head_reg].length;
        }
        return current_length_comb;
    }

    logic<AXI_BYTES>& output_keep_comb_func()
    {
        uint32_t byte;
        output_keep_comb = 0;
        for (byte = 0; byte < AXI_BYTES; ++byte) {
            output_keep_comb[byte] = byte < (uint32_t)remaining_reg;
        }
        return output_keep_comb;
    }

    uint32_t register_value(uint32_t address)
    {
        if (address == REG_RX_HANDLE) return (uint32_t)stage_handle_reg;
        if (address == REG_LENGTH) return (uint32_t)stage_length_reg;
        if (address == REG_DESTINATION) return (uint32_t)stage_destination_reg;
        if (address == REG_SOURCE) return (uint32_t)stage_source_reg;
        if (address == REG_FLAGS) return (uint32_t)stage_flags_reg;
        if (address == REG_STATUS) {
            return ((uint32_t)state_reg != PACKET_DMA_IDLE ? STATUS_BUSY : 0)
                | ((uint32_t)command_count_reg < CMD_DEPTH ? STATUS_CMD_READY : 0)
                | ((bool)protocol_error_reg ? STATUS_ERROR : 0)
                | ((uint32_t)command_count_reg << 8);
        }
        if (address == REG_COMPLETED) return (uint32_t)completed_reg;
        if (address == REG_LAST_OPERATION) return (uint32_t)last_operation_reg;
        return 0;
    }

    logic<AXI_DATA_WIDTH> register_read_value()
    {
        logic<AXI_DATA_WIDTH> data = 0;
        uint32_t index;
        uint32_t address = (uint32_t)mmio.araddr_in();
        uint32_t lane = address & (AXI_BYTES - 1);
        uint32_t value = register_value(address & ~3u);
        for (index = 0; index < 32; ++index) {
            data[lane * 8 + index] = (value >> index) & 1u;
        }
        return data;
    }

    uint32_t write_value()
    {
        uint32_t value = 0;
        uint32_t index;
        uint32_t lane = (uint32_t)write_addr_reg & (AXI_BYTES - 1);
        for (index = 0; index < 32; ++index) {
            if (mmio.wdata_in()[lane * 8 + index]) value |= 1u << index;
        }
        return value;
    }

    uint32_t beat_bytes()
    {
        uint32_t count = 0;
        uint32_t index;
        bool gap = false;
        for (index = 0; index < AXI_BYTES; ++index) {
            if (beat_keep_reg[index]) {
                if (gap) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_KEEP_GAP;
                }
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    uint32_t input_bytes(logic<AXI_BYTES> keep)
    {
        uint32_t count = 0;
        uint32_t index;
        bool gap = false;
        for (index = 0; index < AXI_BYTES; ++index) {
            if (keep[index]) {
                if (gap) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_KEEP_GAP;
                }
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    bool output_ready()
    {
        if ((uint32_t)operation_reg == DMA_CPU_SYSTEM) {
            return system_tx_ready_in();
        }
        return network_tx_ready_in();
    }

public:
    void _assign()
    {
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

        l2_dma.awvalid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_ADDRESS);
        l2_dma.awaddr_out = _ASSIGN_REG(destination_reg);
        l2_dma.awid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        l2_dma.wvalid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_DATA);
        l2_dma.wdata_out = _ASSIGN_REG(beat_data_reg);
        l2_dma.wstrb_out = _ASSIGN_REG(beat_keep_reg);
        l2_dma.wlast_out = _ASSIGN(true);
        l2_dma.bready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WRITE_RESPONSE);
        l2_dma.arvalid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_READ_ADDRESS);
        l2_dma.araddr_out = _ASSIGN_REG(source_reg);
        l2_dma.arid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        l2_dma.rready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_READ_DATA);

        rx_read_valid_out = _ASSIGN((uint32_t)state_reg
            == PACKET_DMA_ISSUE_NETWORK_READ);
        rx_read_handle_out = _ASSIGN_COMB(current_handle_comb_func());
        rx_read_length_out = _ASSIGN_COMB(current_length_comb_func());
        rx_ready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
            && (uint32_t)operation_reg == DMA_NETWORK_CPU
            && (((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) == 0
                || system_tx_ready_in()));
        system_rx_ready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
            && (uint32_t)operation_reg == DMA_SYSTEM_CPU);

        system_tx_valid_out = _ASSIGN(((uint32_t)state_reg
                == PACKET_DMA_SEND_OUTPUT
                && (uint32_t)operation_reg == DMA_CPU_SYSTEM)
            || ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0
                && rx_valid_in()));
        network_tx_valid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_SEND_OUTPUT
            && (uint32_t)operation_reg == DMA_CPU_NETWORK);
        system_tx_data_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_data_in() : (logic<AXI_DATA_WIDTH>)beat_data_reg);
        network_tx_data_out = _ASSIGN_REG(beat_data_reg);
        system_tx_keep_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_keep_in() : (logic<AXI_BYTES>)beat_keep_reg);
        network_tx_keep_out = _ASSIGN_REG(beat_keep_reg);
        system_tx_sop_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_sop_in() : (bool)beat_sop_reg);
        network_tx_sop_out = _ASSIGN_REG(beat_sop_reg);
        system_tx_eop_out = _ASSIGN(
            ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT
                && (uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) != 0)
            ? rx_eop_in() : (bool)beat_eop_reg);
        network_tx_eop_out = _ASSIGN_REG(beat_eop_reg);

        busy_out = _ASSIGN((uint32_t)state_reg != PACKET_DMA_IDLE
            || (uint32_t)command_count_reg != 0);
        command_ready_out = _ASSIGN((uint32_t)command_count_reg < CMD_DEPTH);
        completed_count_out = _ASSIGN_REG(completed_reg);
        last_operation_out = _ASSIGN_REG(last_operation_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
        protocol_error_reason_out = _ASSIGN_REG(protocol_error_reason_reg);
    }

    void _work(bool reset)
    {
        uint32_t slot;
        uint32_t address;
        uint32_t value;
        uint32_t count;
        uint32_t bytes;
        bool push;
        bool pop;
        bool descriptor_push;
        bool input_valid;
        bool input_sop;
        bool input_eop;
        logic<AXI_DATA_WIDTH> input_data;
        logic<AXI_BYTES> input_keep;
        Command command;
        Command staged;

        count = (uint32_t)command_count_reg;
        push = false;
        pop = false;
        descriptor_push = false;
        command = current_command();

        if (mmio.awvalid_in() && mmio.awready_out()) {
            write_addr_reg._next = mmio.awaddr_in();
            write_id_reg._next = mmio.awid_in();
            write_addr_valid_reg._next = true;
        }
        if (mmio.wvalid_in() && mmio.wready_out()) {
            address = (uint32_t)write_addr_reg & ~3u;
            value = write_value();
            if (address == REG_RX_HANDLE) stage_handle_reg._next = value;
            else if (address == REG_LENGTH) stage_length_reg._next = value;
            else if (address == REG_SOURCE) stage_source_reg._next = value;
            else if (address == REG_DESTINATION) stage_destination_reg._next = value;
            else if (address == REG_FLAGS) stage_flags_reg._next = value;
            else if (address == REG_COMMAND && (value & COMMAND_PUSH) != 0) {
                push = count < CMD_DEPTH;
                if (!push) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_COMMAND_QUEUE_FULL;
#ifndef SYNTHESIS
                    std::print(stderr,
                        "{}: PacketDMA command queue full count={} completed={} length={} flags={}\n",
                        __inst_name, count, (uint32_t)completed_reg,
                        (uint32_t)stage_length_reg,
                        (uint32_t)stage_flags_reg);
#endif
                }
                else if ((uint32_t)stage_length_reg == 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_ZERO_LENGTH;
                    push = false;
                }
                else if (((uint32_t)stage_flags_reg
                        & ~(FLAG_OPERATION_MASK | FLAG_CACHE_ALLOCATE
                            | FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)) != 0
                    || (((uint32_t)stage_flags_reg
                            & (FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)) != 0
                        && ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            != DMA_NETWORK_CPU)
                    || (((uint32_t)stage_flags_reg & FLAG_NETWORK_DISCARD) != 0
                        && ((uint32_t)stage_flags_reg & FLAG_NETWORK_SYSTEM) != 0)) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_FLAGS;
                    push = false;
                }
                if (push && ((((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_NETWORK_CPU
                        || ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_SYSTEM_CPU))
                    && ((uint32_t)stage_destination_reg & (AXI_BYTES - 1)) != 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_DESTINATION_ALIGNMENT;
                    push = false;
                }
                if (push && ((((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_CPU_SYSTEM
                        || ((uint32_t)stage_flags_reg & FLAG_OPERATION_MASK)
                            == DMA_CPU_NETWORK))
                    && ((uint32_t)stage_source_reg & (AXI_BYTES - 1)) != 0) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_SOURCE_ALIGNMENT;
                    push = false;
                }
            }
            write_addr_valid_reg._next = false;
            write_response_valid_reg._next = true;
        }
        if (write_response_valid_reg && mmio.bready_in()) {
            write_response_valid_reg._next = false;
        }
        if (mmio.arvalid_in() && mmio.arready_out()) {
            read_id_reg._next = mmio.arid_in();
            read_data_reg._next = register_read_value();
            read_valid_reg._next = true;
        }
        if (read_valid_reg && mmio.rready_in()) read_valid_reg._next = false;

        if (descriptor_command_valid_in() && count < CMD_DEPTH && !push) {
            staged = {};
            staged.handle = descriptor_command_handle_in();
            staged.length = descriptor_command_length_in();
            staged.destination = 0;
            staged.flags = DMA_NETWORK_CPU
                | (descriptor_command_system_in()
                    ? FLAG_NETWORK_SYSTEM : FLAG_NETWORK_DISCARD);
            push = true;
            descriptor_push = true;
        }

        if (push) {
            if (!descriptor_push) {
                staged = {};
                staged.handle = stage_handle_reg;
                staged.length = stage_length_reg;
                staged.source = stage_source_reg;
                staged.destination = stage_destination_reg;
                staged.flags = stage_flags_reg;
            }
            command_reg[(uint32_t)command_tail_reg]._next = staged;
            command_tail_reg._next = ((uint32_t)command_tail_reg + 1)
                & (CMD_DEPTH - 1);
            ++count;
        }

        if ((uint32_t)state_reg == PACKET_DMA_IDLE && count != 0) {
            if ((uint32_t)command_count_reg == 0 && push) command = staged;
            operation_reg._next = (uint32_t)command.flags & FLAG_OPERATION_MASK;
            active_flags_reg._next = command.flags;
            source_reg._next = command.source;
            destination_reg._next = command.destination;
            remaining_reg._next = command.length;
            first_beat_reg._next = true;
            if (((uint32_t)command.flags & FLAG_OPERATION_MASK) == DMA_NETWORK_CPU) {
                state_reg._next = PACKET_DMA_ISSUE_NETWORK_READ;
            }
            else if (((uint32_t)command.flags & FLAG_OPERATION_MASK)
                == DMA_SYSTEM_CPU) {
                state_reg._next = PACKET_DMA_WAIT_INPUT;
            }
            else {
                state_reg._next = PACKET_DMA_READ_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_ISSUE_NETWORK_READ
            && rx_read_ready_in()) {
            state_reg._next = PACKET_DMA_WAIT_INPUT;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WAIT_INPUT) {
            input_valid = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_valid_in() : system_rx_valid_in();
            input_data = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_data_in() : system_rx_data_in();
            input_keep = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_keep_in() : system_rx_keep_in();
            input_sop = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_sop_in() : system_rx_sop_in();
            input_eop = (uint32_t)operation_reg == DMA_NETWORK_CPU
                ? rx_eop_in() : system_rx_eop_in();
            if ((uint32_t)operation_reg == DMA_NETWORK_CPU
                && ((uint32_t)active_flags_reg
                    & (FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)) != 0) {
                if (input_valid
                    && (((uint32_t)active_flags_reg & FLAG_NETWORK_SYSTEM) == 0
                        || system_tx_ready_in())) {
                    bytes = input_bytes(input_keep);
                    if ((bool)first_beat_reg != input_sop) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
                    }
                    if (bytes == 0 || bytes > (uint32_t)remaining_reg) {
                        protocol_error_reg._next = true;
                        protocol_error_reason_reg._next =
                            PACKET_DMA_ERROR_BEAT_LENGTH;
                    }
                    if (input_eop) {
                        if (bytes != (uint32_t)remaining_reg) {
                            protocol_error_reg._next = true;
                            protocol_error_reason_reg._next =
                                PACKET_DMA_ERROR_EOP_LENGTH;
                        }
                        completed_reg._next = completed_reg + 1;
                        last_operation_reg._next = operation_reg;
                        state_reg._next = PACKET_DMA_IDLE;
                        pop = count != 0;
                    }
                    else {
                        if (bytes != AXI_BYTES
                            || bytes >= (uint32_t)remaining_reg) {
                            protocol_error_reg._next = true;
                            protocol_error_reason_reg._next =
                                PACKET_DMA_ERROR_NON_EOP_LENGTH;
                        }
                        remaining_reg._next = remaining_reg - bytes;
                        first_beat_reg._next = false;
                    }
                }
            }
            else if (input_valid) {
                beat_data_reg._next = input_data;
                beat_keep_reg._next = input_keep;
                beat_sop_reg._next = input_sop;
                beat_eop_reg._next = input_eop;
                if ((bool)first_beat_reg != input_sop) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_SOP;
                }
                first_beat_reg._next = false;
                state_reg._next = PACKET_DMA_WRITE_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_ADDRESS
            && l2_dma.awready_in()) {
            state_reg._next = PACKET_DMA_WRITE_DATA;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_DATA
            && l2_dma.wready_in()) {
            state_reg._next = PACKET_DMA_WRITE_RESPONSE;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WRITE_RESPONSE
            && l2_dma.bvalid_in()) {
            bytes = beat_bytes();
            if (bytes == 0 || bytes > (uint32_t)remaining_reg) {
                protocol_error_reg._next = true;
                protocol_error_reason_reg._next = PACKET_DMA_ERROR_BEAT_LENGTH;
            }
            if (beat_eop_reg) {
                if (bytes != (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next = PACKET_DMA_ERROR_EOP_LENGTH;
                }
                completed_reg._next = completed_reg + 1;
                last_operation_reg._next = operation_reg;
                state_reg._next = PACKET_DMA_IDLE;
                pop = count != 0;
            }
            else {
                if (bytes != AXI_BYTES || bytes >= (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                    protocol_error_reason_reg._next =
                        PACKET_DMA_ERROR_NON_EOP_LENGTH;
                }
                destination_reg._next = destination_reg + AXI_BYTES;
                remaining_reg._next = remaining_reg - bytes;
                state_reg._next = PACKET_DMA_WAIT_INPUT;
            }
        }
        else if ((uint32_t)state_reg == PACKET_DMA_READ_ADDRESS
            && l2_dma.arready_in()) {
            state_reg._next = PACKET_DMA_READ_DATA;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_READ_DATA
            && l2_dma.rvalid_in()) {
            beat_data_reg._next = l2_dma.rdata_in();
            beat_keep_reg._next = output_keep_comb_func();
            beat_sop_reg._next = first_beat_reg;
            beat_eop_reg._next = (uint32_t)remaining_reg <= AXI_BYTES;
            state_reg._next = PACKET_DMA_SEND_OUTPUT;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_SEND_OUTPUT
            && output_ready()) {
            if ((uint32_t)remaining_reg <= AXI_BYTES) {
                completed_reg._next = completed_reg + 1;
                last_operation_reg._next = operation_reg;
                state_reg._next = PACKET_DMA_IDLE;
                pop = count != 0;
            }
            else {
                source_reg._next = source_reg + AXI_BYTES;
                remaining_reg._next = remaining_reg - AXI_BYTES;
                first_beat_reg._next = false;
                state_reg._next = PACKET_DMA_READ_ADDRESS;
            }
        }

        if (pop) {
            command_head_reg._next = ((uint32_t)command_head_reg + 1)
                & (CMD_DEPTH - 1);
            --count;
        }
        command_count_reg._next = count;

        if (reset) {
            command_head_reg.clr();
            command_tail_reg.clr();
            command_count_reg.clr();
            stage_handle_reg.clr();
            stage_length_reg.clr();
            stage_source_reg.clr();
            stage_destination_reg.clr();
            stage_flags_reg.clr();
            state_reg.clr();
            operation_reg.clr();
            active_flags_reg.clr();
            source_reg.clr();
            destination_reg.clr();
            remaining_reg.clr();
            beat_data_reg.clr();
            beat_keep_reg.clr();
            beat_sop_reg.clr();
            beat_eop_reg.clr();
            first_beat_reg.clr();
            completed_reg.clr();
            last_operation_reg.clr();
            protocol_error_reg.clr();
            protocol_error_reason_reg.clr();
            write_addr_reg.clr();
            write_id_reg.clr();
            write_addr_valid_reg.clr();
            write_response_valid_reg.clr();
            read_id_reg.clr();
            read_data_reg.clr();
            read_valid_reg.clr();
            for (slot = 0; slot < CMD_DEPTH; ++slot) command_reg[slot].clr();
        }
    }

    void _strobe()
    {
        uint32_t slot;
        for (slot = 0; slot < CMD_DEPTH; ++slot) command_reg[slot].strobe();
        command_head_reg.strobe();
        command_tail_reg.strobe();
        command_count_reg.strobe();
        stage_handle_reg.strobe();
        stage_length_reg.strobe();
        stage_source_reg.strobe();
        stage_destination_reg.strobe();
        stage_flags_reg.strobe();
        state_reg.strobe();
        operation_reg.strobe();
        active_flags_reg.strobe();
        source_reg.strobe();
        destination_reg.strobe();
        remaining_reg.strobe();
        beat_data_reg.strobe();
        beat_keep_reg.strobe();
        beat_sop_reg.strobe();
        beat_eop_reg.strobe();
        first_beat_reg.strobe();
        completed_reg.strobe();
        last_operation_reg.strobe();
        protocol_error_reg.strobe();
        protocol_error_reason_reg.strobe();
        write_addr_reg.strobe();
        write_id_reg.strobe();
        write_addr_valid_reg.strobe();
        write_response_valid_reg.strobe();
        read_id_reg.strobe();
        read_data_reg.strobe();
        read_valid_reg.strobe();
    }
};

template class PacketDMA<16, 14, 8, 32, 4, 256>;
