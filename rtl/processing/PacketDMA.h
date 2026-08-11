#pragma once

// Per-CPU packet DMA.  Software stages an RxRAM handle, packet length and CPU
// physical destination, then pushes the command into a small FIFO.  Packet
// beats are written through Tribe's coherent external-L2 AXI port; L2 write
// allocation marks the line dirty and therefore does not write through on the
// critical packet path.

#include "../common/Axi4Master.h"

using namespace cpphdl;

enum PacketDmaState : uint8_t
{
    PACKET_DMA_IDLE,
    PACKET_DMA_ISSUE_READ,
    PACKET_DMA_WAIT_PACKET,
    PACKET_DMA_WRITE_ADDRESS,
    PACKET_DMA_WRITE_DATA,
    PACKET_DMA_WRITE_RESPONSE
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
        "PacketDMA is matched to the Tribe 256-bit L2 port");
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
        REG_COMPLETED = 0x18
    };

    static constexpr uint32_t COMMAND_PUSH = 1u << 0;
    static constexpr uint32_t FLAG_CACHE_ALLOCATE = 1u << 0;
    static constexpr uint32_t STATUS_BUSY = 1u << 0;
    static constexpr uint32_t STATUS_CMD_READY = 1u << 1;
    static constexpr uint32_t STATUS_ERROR = 1u << 2;

    struct Command
    {
        u<HANDLE_BITS> handle;
        u<FRAME_LENGTH_BITS> length;
        u32 destination;
        u8 flags;
    } __PACKED;

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> mmio;
    Axi4MasterIf<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> l2_dma;

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

    _PORT(bool) busy_out;
    _PORT(bool) command_ready_out;
    _PORT(u<32>) completed_count_out;
    _PORT(bool) protocol_error_out;

private:
    reg<Command> command_reg[CMD_DEPTH];
    reg<u<CMD_PTR_BITS>> command_head_reg;
    reg<u<CMD_PTR_BITS>> command_tail_reg;
    reg<u<CMD_COUNT_BITS>> command_count_reg;

    reg<u<HANDLE_BITS>> stage_handle_reg;
    reg<u<FRAME_LENGTH_BITS>> stage_length_reg;
    reg<u32> stage_destination_reg;
    reg<u8> stage_flags_reg;

    reg<u8> state_reg;
    reg<u<AXI_ADDR_WIDTH>> destination_reg;
    reg<u<FRAME_LENGTH_BITS>> remaining_reg;
    reg<logic<AXI_DATA_WIDTH>> beat_data_reg;
    reg<logic<AXI_BYTES>> beat_keep_reg;
    reg<u1> beat_sop_reg;
    reg<u1> beat_eop_reg;
    reg<u1> first_beat_reg;
    reg<u<32>> completed_reg;
    reg<u1> protocol_error_reg;

    reg<u<AXI_ADDR_WIDTH>> write_addr_reg;
    reg<u<AXI_ID_WIDTH>> write_id_reg;
    reg<u1> write_addr_valid_reg;
    reg<u1> write_response_valid_reg;
    reg<u<AXI_ID_WIDTH>> read_id_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;
    reg<u1> read_valid_reg;

    u<HANDLE_BITS> current_handle_comb;
    u<FRAME_LENGTH_BITS> current_length_comb;

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

    uint32_t register_value(uint32_t address)
    {
        if (address == REG_RX_HANDLE) return (uint32_t)stage_handle_reg;
        if (address == REG_LENGTH) return (uint32_t)stage_length_reg;
        if (address == REG_DESTINATION) return (uint32_t)stage_destination_reg;
        if (address == REG_FLAGS) return (uint32_t)stage_flags_reg;
        if (address == REG_STATUS) {
            return ((uint32_t)state_reg != PACKET_DMA_IDLE ? STATUS_BUSY : 0)
                | ((uint32_t)command_count_reg < CMD_DEPTH ? STATUS_CMD_READY : 0)
                | ((bool)protocol_error_reg ? STATUS_ERROR : 0)
                | ((uint32_t)command_count_reg << 8);
        }
        if (address == REG_COMPLETED) return (uint32_t)completed_reg;
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
                if (gap) protocol_error_reg._next = true;
                ++count;
            }
            else {
                gap = true;
            }
        }
        return count;
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
        l2_dma.arvalid_out = _ASSIGN(false);
        l2_dma.araddr_out = _ASSIGN((u<AXI_ADDR_WIDTH>)0);
        l2_dma.arid_out = _ASSIGN((u<AXI_ID_WIDTH>)0);
        l2_dma.rready_out = _ASSIGN(false);

        rx_read_valid_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_ISSUE_READ);
        rx_read_handle_out = _ASSIGN_COMB(current_handle_comb_func());
        rx_read_length_out = _ASSIGN_COMB(current_length_comb_func());
        rx_ready_out = _ASSIGN((uint32_t)state_reg == PACKET_DMA_WAIT_PACKET);
        busy_out = _ASSIGN((uint32_t)state_reg != PACKET_DMA_IDLE
            || (uint32_t)command_count_reg != 0);
        command_ready_out = _ASSIGN((uint32_t)command_count_reg < CMD_DEPTH);
        completed_count_out = _ASSIGN_REG(completed_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
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
        Command command;
        Command staged;

        count = (uint32_t)command_count_reg;
        push = false;
        pop = false;
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
            else if (address == REG_DESTINATION) stage_destination_reg._next = value;
            else if (address == REG_FLAGS) stage_flags_reg._next = value;
            else if (address == REG_COMMAND && (value & COMMAND_PUSH) != 0) {
                push = count < CMD_DEPTH;
                if (!push || (uint32_t)stage_length_reg == 0
                    || ((uint32_t)stage_destination_reg & (AXI_BYTES - 1)) != 0
                    || ((uint32_t)stage_flags_reg & ~FLAG_CACHE_ALLOCATE) != 0) {
                    protocol_error_reg._next = true;
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

        if (push) {
            staged = {};
            staged.handle = stage_handle_reg;
            staged.length = stage_length_reg;
            staged.destination = stage_destination_reg;
            staged.flags = stage_flags_reg;
            command_reg[(uint32_t)command_tail_reg]._next = staged;
            command_tail_reg._next = ((uint32_t)command_tail_reg + 1)
                & (CMD_DEPTH - 1);
            ++count;
        }

        if ((uint32_t)state_reg == PACKET_DMA_IDLE && count != 0) {
            // When a command is pushed into an empty FIFO, use the staged
            // values immediately; the queue register commits at the edge.
            if ((uint32_t)command_count_reg == 0 && push) command = staged;
            destination_reg._next = command.destination;
            remaining_reg._next = command.length;
            first_beat_reg._next = true;
            state_reg._next = PACKET_DMA_ISSUE_READ;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_ISSUE_READ
            && rx_read_ready_in()) {
            state_reg._next = PACKET_DMA_WAIT_PACKET;
        }
        else if ((uint32_t)state_reg == PACKET_DMA_WAIT_PACKET
            && rx_valid_in()) {
            beat_data_reg._next = rx_data_in();
            beat_keep_reg._next = rx_keep_in();
            beat_sop_reg._next = rx_sop_in();
            beat_eop_reg._next = rx_eop_in();
            if ((bool)first_beat_reg != rx_sop_in()) {
                protocol_error_reg._next = true;
            }
            first_beat_reg._next = false;
            state_reg._next = PACKET_DMA_WRITE_ADDRESS;
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
            }
            if (beat_eop_reg) {
                if (bytes != (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                }
                completed_reg._next = completed_reg + 1;
                state_reg._next = PACKET_DMA_IDLE;
                pop = count != 0;
            }
            else {
                if (bytes != AXI_BYTES || bytes >= (uint32_t)remaining_reg) {
                    protocol_error_reg._next = true;
                }
                destination_reg._next = destination_reg + AXI_BYTES;
                remaining_reg._next = remaining_reg - bytes;
                state_reg._next = PACKET_DMA_WAIT_PACKET;
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
            stage_destination_reg.clr();
            stage_flags_reg.clr();
            state_reg.clr();
            destination_reg.clr();
            remaining_reg.clr();
            beat_data_reg.clr();
            beat_keep_reg.clr();
            beat_sop_reg.clr();
            beat_eop_reg.clr();
            first_beat_reg.clr();
            completed_reg.clr();
            protocol_error_reg.clr();
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
        stage_destination_reg.strobe();
        stage_flags_reg.strobe();
        state_reg.strobe();
        destination_reg.strobe();
        remaining_reg.strobe();
        beat_data_reg.strobe();
        beat_keep_reg.strobe();
        beat_sop_reg.strobe();
        beat_eop_reg.strobe();
        first_beat_reg.strobe();
        completed_reg.strobe();
        protocol_error_reg.strobe();
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
