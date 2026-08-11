#pragma once

// Store-and-forward packet queue shared by RxQueue and TxQueue.  Packet data
// uses the processing 256-bit framed-stream format.  A packet is not exposed
// to the reader until its EOP and length metadata have both been committed.

#include "../common/Fifo.cpp"

using namespace cpphdl;

template<size_t DEPTH = 256, size_t DATA_WIDTH = 256,
    size_t LENGTH_BITS = 16>
class PacketQueue : public Module
{
public:
    static constexpr size_t DATA_BYTES = DATA_WIDTH / 8;
    static constexpr size_t ENTRY_BITS = DATA_WIDTH + DATA_BYTES + 2;
    static constexpr size_t ENTRY_BYTES = (ENTRY_BITS + 7) / 8;
    static constexpr size_t COUNT_BITS = clog2(DEPTH + 1);

    static_assert(DATA_WIDTH == 256,
        "System packet queues match the 256-bit processing datapath");
    static_assert(DEPTH >= 4 && (DEPTH & (DEPTH - 1)) == 0,
        "Packet queue depth must be a power of two");

    _PORT(bool) write_valid_in;
    _PORT(logic<DATA_WIDTH>) write_data_in;
    _PORT(logic<DATA_BYTES>) write_keep_in;
    _PORT(bool) write_sop_in;
    _PORT(bool) write_eop_in;
    _PORT(bool) write_ready_out;

    _PORT(bool) read_valid_out;
    _PORT(logic<DATA_WIDTH>) read_data_out;
    _PORT(logic<DATA_BYTES>) read_keep_out;
    _PORT(bool) read_sop_out;
    _PORT(bool) read_eop_out;
    _PORT(bool) read_ready_in;

    _PORT(bool) empty_out;
    _PORT(bool) full_out;
    _PORT(u<LENGTH_BITS>) packet_length_out;
    _PORT(u<COUNT_BITS>) packet_count_out;
    _PORT(bool) protocol_error_out;
    _PORT(bool) clear_in;

private:
    Fifo<ENTRY_BYTES, DEPTH, true, false> data_fifo;
    Fifo<LENGTH_BITS / 8, DEPTH, true, false> length_fifo;
    reg<u<LENGTH_BITS>> assembling_length_reg;
    reg<u<COUNT_BITS>> packet_count_reg;
    reg<u1> assembling_reg;
    reg<u1> protocol_error_reg;
    logic<ENTRY_BYTES * 8> write_entry_comb;
    logic<LENGTH_BITS> write_length_comb;

    logic<ENTRY_BYTES * 8>& write_entry_comb_func()
    {
        write_entry_comb = 0;
        write_entry_comb.bits(DATA_WIDTH - 1, 0) = write_data_in();
        write_entry_comb.bits(DATA_WIDTH + DATA_BYTES - 1, DATA_WIDTH) =
            write_keep_in();
        write_entry_comb[DATA_WIDTH + DATA_BYTES] = write_sop_in();
        write_entry_comb[DATA_WIDTH + DATA_BYTES + 1] = write_eop_in();
        return write_entry_comb;
    }

    uint32_t input_bytes()
    {
        uint32_t byte;
        uint32_t count;
        count = 0;
        for (byte = 0; byte < DATA_BYTES; ++byte) {
            if (write_keep_in()[byte]) ++count;
        }
        return count;
    }

    bool input_keep_contiguous()
    {
        uint32_t byte;
        bool gap;
        gap = false;
        for (byte = 0; byte < DATA_BYTES; ++byte) {
            if (write_keep_in()[byte] && gap) return false;
            if (!write_keep_in()[byte]) gap = true;
        }
        return true;
    }

    logic<LENGTH_BITS>& write_length_comb_func()
    {
        write_length_comb = (write_sop_in()
            ? 0 : (uint32_t)assembling_length_reg) + input_bytes();
        return write_length_comb;
    }

public:
    void _assign()
    {
        data_fifo.write_data_in = _ASSIGN_COMB(write_entry_comb_func());
        data_fifo.clear_in = clear_in;

        length_fifo.write_data_in = _ASSIGN_COMB(write_length_comb_func());
        length_fifo.clear_in = clear_in;

#ifndef SYNTHESIS
        data_fifo.__inst_name = __inst_name + "/data";
        length_fifo.__inst_name = __inst_name + "/length";
#endif
        data_fifo._assign();
        length_fifo._assign();

        write_ready_out = _ASSIGN(!data_fifo.full_out()
            && (!write_valid_in() || !write_eop_in() || !length_fifo.full_out()));
        read_valid_out = _ASSIGN(!data_fifo.empty_out()
            && !length_fifo.empty_out());
        read_data_out = _ASSIGN((logic<DATA_WIDTH>)
            data_fifo.read_data_out().bits(DATA_WIDTH - 1, 0));
        read_keep_out = _ASSIGN((logic<DATA_BYTES>)data_fifo.read_data_out().bits(
            DATA_WIDTH + DATA_BYTES - 1, DATA_WIDTH));
        read_sop_out = _ASSIGN(data_fifo.read_data_out()[DATA_WIDTH + DATA_BYTES]);
        read_eop_out = _ASSIGN(data_fifo.read_data_out()[DATA_WIDTH + DATA_BYTES + 1]);
        empty_out = _ASSIGN((uint32_t)packet_count_reg == 0);
        full_out = data_fifo.full_out;
        packet_length_out = _ASSIGN((u<LENGTH_BITS>)length_fifo.read_data_out());
        packet_count_out = _ASSIGN_REG(packet_count_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);

        data_fifo.write_in = _ASSIGN(write_valid_in() && write_ready_out());
        data_fifo.read_in = _ASSIGN(read_valid_out() && read_ready_in());
        length_fifo.write_in = _ASSIGN(write_valid_in() && write_ready_out()
            && write_eop_in());
        length_fifo.read_in = _ASSIGN(read_valid_out() && read_ready_in()
            && read_eop_out());
    }

    void _work(bool reset)
    {
        uint32_t bytes;
        uint32_t count;
        bool write_fire;
        bool read_fire;

        write_fire = write_valid_in() && write_ready_out();
        read_fire = read_valid_out() && read_ready_in();
        count = (uint32_t)packet_count_reg;

        if (write_fire) {
            bytes = input_bytes();
            if (bytes == 0 || !input_keep_contiguous()
                || (write_sop_in() != !(bool)assembling_reg)) {
                protocol_error_reg._next = true;
            }
            if (write_sop_in()) {
                assembling_length_reg._next = bytes;
                assembling_reg._next = true;
            }
            else {
                assembling_length_reg._next = assembling_length_reg + bytes;
            }
            if (write_eop_in()) {
                assembling_length_reg._next = 0;
                assembling_reg._next = false;
                ++count;
            }
        }
        if (read_fire && read_eop_out()) {
            if (count == 0) protocol_error_reg._next = true;
            else --count;
        }
        packet_count_reg._next = count;

        data_fifo._work(reset);
        length_fifo._work(reset);
        if (clear_in()) {
            assembling_length_reg._next = 0;
            packet_count_reg._next = 0;
            assembling_reg._next = false;
            protocol_error_reg._next = false;
        }
        if (reset) {
            assembling_length_reg.clr();
            packet_count_reg.clr();
            assembling_reg.clr();
            protocol_error_reg.clr();
        }
    }

    void _strobe()
    {
        data_fifo._strobe();
        length_fifo._strobe();
        assembling_length_reg.strobe();
        packet_count_reg.strobe();
        assembling_reg.strobe();
        protocol_error_reg.strobe();
    }
};
