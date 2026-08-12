#pragma once

// Host-memory DMA used by the System controller.  Processing queues retain
// their 256-bit L2 width, while the host side is deliberately narrow enough
// for the KlusterLab Kintex-7 PCIe Gen2 x1 datapath.

#include "../../Config.h"
#include "../common/Axi4Master.h"
#include "../common/Avalon.h"

using namespace cpphdl;

enum MasterDmaDirection : uint8_t
{
    MASTER_DMA_QUEUE_TO_HOST = 0,
    MASTER_DMA_HOST_TO_QUEUE = 1
};

enum MasterDmaState : uint8_t
{
    MASTER_DMA_IDLE,
    MASTER_DMA_WAIT_QUEUE,
    MASTER_DMA_WRITE_ADDRESS,
    MASTER_DMA_WRITE_DATA,
    MASTER_DMA_WRITE_RESPONSE,
    MASTER_DMA_READ_ADDRESS,
    MASTER_DMA_READ_DATA,
    MASTER_DMA_SEND_QUEUE
};

template<size_t ADDR_WIDTH = HOST_ADDR_WIDTH, size_t DATA_WIDTH = HOST_DATA_WIDTH,
    size_t ID_WIDTH = 4, size_t LENGTH_BITS = 16>
class MasterDMA : public Module
{
public:
    static constexpr size_t DATA_BYTES = DATA_WIDTH / 8;
    static constexpr size_t QUEUE_DATA_WIDTH = 256;
    static constexpr size_t QUEUE_BYTES = QUEUE_DATA_WIDTH / 8;
    static constexpr size_t CHUNKS = QUEUE_DATA_WIDTH / DATA_WIDTH;
    static constexpr size_t CHUNK_BITS = clog2(CHUNKS);
    static_assert(DATA_WIDTH == 64,
        "Kintex-7 host DMA uses a 64-bit PCIe Gen2 x1 interface");
    static_assert(QUEUE_DATA_WIDTH % DATA_WIDTH == 0);

    _PORT(bool) command_valid_in;
    _PORT(bool) command_ready_out;
    _PORT(bool) command_direction_in;
    _PORT(u<3>) command_queue_in;
    _PORT(u<ADDR_WIDTH>) command_address_in;
    _PORT(u<LENGTH_BITS>) command_length_in;
    _PORT(bool) command_sop_in;
    _PORT(bool) command_eop_in;

    _PORT(bool) queue_input_valid_in;
    _PORT(logic<QUEUE_DATA_WIDTH>) queue_input_data_in;
    _PORT(logic<QUEUE_BYTES>) queue_input_keep_in;
    _PORT(bool) queue_input_sop_in;
    _PORT(bool) queue_input_eop_in;
    _PORT(bool) queue_input_ready_out;

    _PORT(bool) queue_output_valid_out;
    _PORT(logic<QUEUE_DATA_WIDTH>) queue_output_data_out;
    _PORT(logic<QUEUE_BYTES>) queue_output_keep_out;
    _PORT(bool) queue_output_sop_out;
    _PORT(bool) queue_output_eop_out;
    _PORT(bool) queue_output_ready_in;

#if HOST_AXI4
    Axi4MasterIf<ADDR_WIDTH, ID_WIDTH, DATA_WIDTH> host;
#else
    AvalonIf<ADDR_WIDTH, DATA_WIDTH> host_out;
#endif

    _PORT(bool) busy_out;
    _PORT(bool) completion_valid_out;
    _PORT(u<3>) active_queue_out;
    _PORT(u<3>) completion_queue_out;
    _PORT(bool) completion_direction_out;
    _PORT(u<32>) completed_count_out;
    _PORT(bool) protocol_error_out;

private:
    reg<u8> state_reg;
    reg<u1> direction_reg;
    reg<u<3>> queue_reg;
    reg<u<ADDR_WIDTH>> address_reg;
    reg<u<LENGTH_BITS>> remaining_reg;
    reg<u1> command_sop_reg;
    reg<u1> command_eop_reg;
    reg<u1> first_beat_reg;
    reg<u<CHUNK_BITS>> chunk_reg;
    reg<u<6>> queue_bytes_reg;
    reg<logic<QUEUE_DATA_WIDTH>> queue_data_reg;
    reg<logic<QUEUE_BYTES>> queue_keep_reg;
    reg<u1> queue_sop_reg;
    reg<u1> queue_eop_reg;
    reg<u1> completion_valid_reg;
    reg<u<3>> completion_queue_reg;
    reg<u1> completion_direction_reg;
    reg<u<32>> completed_reg;
    reg<u1> protocol_error_reg;
    logic<DATA_WIDTH> host_write_data_comb;
    logic<DATA_BYTES> host_write_keep_comb;

    logic<DATA_WIDTH>& host_write_data_comb_func()
    {
        uint32_t bit;
        uint32_t base;
        host_write_data_comb = 0;
        base = (uint32_t)chunk_reg * DATA_WIDTH;
        for (bit = 0; bit < DATA_WIDTH; ++bit) {
            host_write_data_comb[bit] = queue_data_reg[base + bit];
        }
        return host_write_data_comb;
    }

    logic<DATA_BYTES>& host_write_keep_comb_func()
    {
        uint32_t byte;
        uint32_t base;
        host_write_keep_comb = 0;
        base = (uint32_t)chunk_reg * DATA_BYTES;
        for (byte = 0; byte < DATA_BYTES; ++byte) {
            host_write_keep_comb[byte] = queue_keep_reg[base + byte];
        }
        return host_write_keep_comb;
    }

    uint32_t kept_bytes(logic<DATA_BYTES> keep)
    {
        uint32_t byte;
        uint32_t count;
        bool gap;
        count = 0;
        gap = false;
        for (byte = 0; byte < DATA_BYTES; ++byte) {
            if (keep[byte]) {
                if (gap) protocol_error_reg._next = true;
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    uint32_t kept_queue_bytes(logic<QUEUE_BYTES> keep)
    {
        uint32_t byte;
        uint32_t count;
        bool gap;
        count = 0;
        gap = false;
        for (byte = 0; byte < QUEUE_BYTES; ++byte) {
            if (keep[byte]) {
                if (gap) protocol_error_reg._next = true;
                ++count;
            }
            else gap = true;
        }
        return count;
    }

    void complete_command()
    {
        completion_valid_reg._next = true;
        completion_queue_reg._next = queue_reg;
        completion_direction_reg._next = direction_reg;
        completed_reg._next = completed_reg + 1;
        state_reg._next = MASTER_DMA_IDLE;
    }

public:
    void _assign()
    {
        command_ready_out = _ASSIGN((uint32_t)state_reg == MASTER_DMA_IDLE);
        queue_input_ready_out = _ASSIGN((uint32_t)state_reg
            == MASTER_DMA_WAIT_QUEUE);
        queue_output_valid_out = _ASSIGN((uint32_t)state_reg
            == MASTER_DMA_SEND_QUEUE);
        queue_output_data_out = _ASSIGN_REG(queue_data_reg);
        queue_output_keep_out = _ASSIGN_REG(queue_keep_reg);
        queue_output_sop_out = _ASSIGN_REG(queue_sop_reg);
        queue_output_eop_out = _ASSIGN_REG(queue_eop_reg);

#if HOST_AXI4
        host.awvalid_out = _ASSIGN((uint32_t)state_reg
            == MASTER_DMA_WRITE_ADDRESS);
        host.awaddr_out = _ASSIGN_REG(address_reg);
        host.awid_out = _ASSIGN((u<ID_WIDTH>)0);
        host.wvalid_out = _ASSIGN((uint32_t)state_reg == MASTER_DMA_WRITE_DATA);
        host.wdata_out = _ASSIGN_COMB(host_write_data_comb_func());
        host.wstrb_out = _ASSIGN_COMB(host_write_keep_comb_func());
        host.wlast_out = _ASSIGN(true);
        host.bready_out = _ASSIGN((uint32_t)state_reg
            == MASTER_DMA_WRITE_RESPONSE);
        host.arvalid_out = _ASSIGN((uint32_t)state_reg
            == MASTER_DMA_READ_ADDRESS);
        host.araddr_out = _ASSIGN_REG(address_reg);
        host.arid_out = _ASSIGN((u<ID_WIDTH>)0);
        host.rready_out = _ASSIGN((uint32_t)state_reg == MASTER_DMA_READ_DATA);
#else
        host_out.address_in = _ASSIGN_REG(address_reg);
        host_out.read_in = _ASSIGN((uint32_t)state_reg == MASTER_DMA_READ_ADDRESS);
        host_out.write_in = _ASSIGN((uint32_t)state_reg == MASTER_DMA_WRITE_ADDRESS);
        host_out.writedata_in = _ASSIGN_COMB(host_write_data_comb_func());
        host_out.byteenable_in = _ASSIGN_COMB(host_write_keep_comb_func());
#endif

        busy_out = _ASSIGN((uint32_t)state_reg != MASTER_DMA_IDLE);
        completion_valid_out = _ASSIGN_REG(completion_valid_reg);
        active_queue_out = _ASSIGN_REG(queue_reg);
        completion_queue_out = _ASSIGN_REG(completion_queue_reg);
        completion_direction_out = _ASSIGN((bool)completion_direction_reg);
        completed_count_out = _ASSIGN_REG(completed_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work(bool reset)
    {
        uint32_t bytes;
        uint32_t byte;
        uint32_t bit;
        uint32_t base;
        completion_valid_reg._next = false;

        if ((uint32_t)state_reg == MASTER_DMA_IDLE && command_valid_in()) {
            direction_reg._next = command_direction_in();
            queue_reg._next = command_queue_in();
            address_reg._next = command_address_in();
            remaining_reg._next = command_length_in();
            command_sop_reg._next = command_sop_in();
            command_eop_reg._next = command_eop_in();
            first_beat_reg._next = true;
            chunk_reg._next = 0;
            queue_bytes_reg._next = 0;
            queue_data_reg._next = 0;
            queue_keep_reg._next = 0;
            if ((uint32_t)command_length_in() == 0
                || ((uint64_t)command_address_in() & 3u) != 0
                || ((uint32_t)command_length_in() & 3u) != 0) {
                protocol_error_reg._next = true;
            }
            else if (command_direction_in() == MASTER_DMA_QUEUE_TO_HOST) {
                state_reg._next = MASTER_DMA_WAIT_QUEUE;
            }
            else state_reg._next = MASTER_DMA_READ_ADDRESS;
        }
        else if ((uint32_t)state_reg == MASTER_DMA_WAIT_QUEUE
            && queue_input_valid_in()) {
            bytes = kept_queue_bytes(queue_input_keep_in());
            queue_data_reg._next = queue_input_data_in();
            queue_keep_reg._next = queue_input_keep_in();
            queue_sop_reg._next = queue_input_sop_in();
            queue_eop_reg._next = queue_input_eop_in();
            queue_bytes_reg._next = bytes;
            chunk_reg._next = 0;
            if (bytes == 0 || bytes > (uint32_t)remaining_reg
                || (bool)first_beat_reg != queue_input_sop_in()) {
                protocol_error_reg._next = true;
            }
            state_reg._next = MASTER_DMA_WRITE_ADDRESS;
        }
#if HOST_AXI4
        else if ((uint32_t)state_reg == MASTER_DMA_WRITE_ADDRESS
            && host.awready_in()) state_reg._next = MASTER_DMA_WRITE_DATA;
        else if ((uint32_t)state_reg == MASTER_DMA_WRITE_DATA
            && host.wready_in()) state_reg._next = MASTER_DMA_WRITE_RESPONSE;
        else if ((uint32_t)state_reg == MASTER_DMA_WRITE_RESPONSE
            && host.bvalid_in()) {
#else
        else if ((uint32_t)state_reg == MASTER_DMA_WRITE_ADDRESS
            && !host_out.waitrequest_out()) {
#endif
            bytes = kept_bytes(host_write_keep_comb_func());
            if (bytes == 0 || bytes > (uint32_t)remaining_reg)
                protocol_error_reg._next = true;
            if (bytes >= (uint32_t)remaining_reg) {
                if (!queue_eop_reg || bytes != (uint32_t)remaining_reg)
                    protocol_error_reg._next = true;
                complete_command();
            }
            else if (((uint32_t)chunk_reg + 1) * DATA_BYTES
                < (uint32_t)queue_bytes_reg) {
                address_reg._next = address_reg + bytes;
                remaining_reg._next = remaining_reg - bytes;
                chunk_reg._next = chunk_reg + 1;
                state_reg._next = MASTER_DMA_WRITE_ADDRESS;
            }
            else {
                if (queue_eop_reg) protocol_error_reg._next = true;
                address_reg._next = address_reg + bytes;
                remaining_reg._next = remaining_reg - bytes;
                first_beat_reg._next = false;
                state_reg._next = MASTER_DMA_WAIT_QUEUE;
            }
        }
#if HOST_AXI4
        else if ((uint32_t)state_reg == MASTER_DMA_READ_ADDRESS
            && host.arready_in()) state_reg._next = MASTER_DMA_READ_DATA;
        else if ((uint32_t)state_reg == MASTER_DMA_READ_DATA
            && host.rvalid_in()) {
            base = (uint32_t)chunk_reg * DATA_WIDTH;
            bytes = (uint32_t)remaining_reg < DATA_BYTES
                ? (uint32_t)remaining_reg : DATA_BYTES;
            for (bit = 0; bit < DATA_WIDTH; ++bit)
                queue_data_reg._next[base + bit] = host.rdata_in()[bit];
#else
        else if ((uint32_t)state_reg == MASTER_DMA_READ_ADDRESS
            && !host_out.waitrequest_out()) state_reg._next = MASTER_DMA_READ_DATA;
        else if ((uint32_t)state_reg == MASTER_DMA_READ_DATA
            && host_out.readdatavalid_out()) {
            base = (uint32_t)chunk_reg * DATA_WIDTH;
            bytes = (uint32_t)remaining_reg < DATA_BYTES
                ? (uint32_t)remaining_reg : DATA_BYTES;
            for (bit = 0; bit < DATA_WIDTH; ++bit)
                queue_data_reg._next[base + bit] = host_out.readdata_out()[bit];
#endif
            base = (uint32_t)chunk_reg * DATA_BYTES;
            for (byte = 0; byte < DATA_BYTES; ++byte)
                queue_keep_reg._next[base + byte] = byte < bytes;
            if ((uint32_t)remaining_reg <= DATA_BYTES
                || (uint32_t)chunk_reg == CHUNKS - 1) {
                queue_sop_reg._next = first_beat_reg && command_sop_reg;
                queue_eop_reg._next = (uint32_t)remaining_reg <= DATA_BYTES
                    && command_eop_reg;
                state_reg._next = MASTER_DMA_SEND_QUEUE;
            }
            else {
                address_reg._next = address_reg + DATA_BYTES;
                remaining_reg._next = remaining_reg - DATA_BYTES;
                chunk_reg._next = chunk_reg + 1;
                state_reg._next = MASTER_DMA_READ_ADDRESS;
            }
        }
        else if ((uint32_t)state_reg == MASTER_DMA_SEND_QUEUE
            && queue_output_ready_in()) {
            bytes = (uint32_t)remaining_reg < DATA_BYTES
                ? (uint32_t)remaining_reg : DATA_BYTES;
            if ((uint32_t)remaining_reg <= DATA_BYTES) complete_command();
            else {
                address_reg._next = address_reg + bytes;
                remaining_reg._next = remaining_reg - bytes;
                first_beat_reg._next = false;
                chunk_reg._next = 0;
                queue_data_reg._next = 0;
                queue_keep_reg._next = 0;
                state_reg._next = MASTER_DMA_READ_ADDRESS;
            }
        }

        if (reset) {
            state_reg.clr();
            direction_reg.clr();
            queue_reg.clr();
            address_reg.clr();
            remaining_reg.clr();
            command_sop_reg.clr();
            command_eop_reg.clr();
            first_beat_reg.clr();
            chunk_reg.clr();
            queue_bytes_reg.clr();
            queue_data_reg.clr();
            queue_keep_reg.clr();
            queue_sop_reg.clr();
            queue_eop_reg.clr();
            completion_valid_reg.clr();
            completion_queue_reg.clr();
            completion_direction_reg.clr();
            completed_reg.clr();
            protocol_error_reg.clr();
        }
    }

    void _strobe()
    {
        state_reg.strobe();
        direction_reg.strobe();
        queue_reg.strobe();
        address_reg.strobe();
        remaining_reg.strobe();
        command_sop_reg.strobe();
        command_eop_reg.strobe();
        first_beat_reg.strobe();
        chunk_reg.strobe();
        queue_bytes_reg.strobe();
        queue_data_reg.strobe();
        queue_keep_reg.strobe();
        queue_sop_reg.strobe();
        queue_eop_reg.strobe();
        completion_valid_reg.strobe();
        completion_queue_reg.strobe();
        completion_direction_reg.strobe();
        completed_reg.strobe();
        protocol_error_reg.strobe();
    }
};

template class MasterDMA<HOST_ADDR_WIDTH, HOST_DATA_WIDTH, 4, 16>;
