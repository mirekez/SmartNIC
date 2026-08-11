#pragma once

// Host-to-processing packet queue.  Scatter-gather fragments are committed as
// one packet when the final fragment supplies EOP.

#include "PacketQueue.h"

using namespace cpphdl;

template<size_t DEPTH = 256>
class TxQueue : public Module
{
public:
    PacketQueue<DEPTH> queue;

    _PORT(bool) write_valid_in;
    _PORT(logic<256>) write_data_in;
    _PORT(logic<32>) write_keep_in;
    _PORT(bool) write_sop_in;
    _PORT(bool) write_eop_in;
    _PORT(bool) write_ready_out;
    _PORT(bool) read_valid_out;
    _PORT(logic<256>) read_data_out;
    _PORT(logic<32>) read_keep_out;
    _PORT(bool) read_sop_out;
    _PORT(bool) read_eop_out;
    _PORT(bool) read_ready_in;
    _PORT(bool) empty_out;
    _PORT(bool) full_out;
    _PORT(u<16>) packet_length_out;
    _PORT(u<clog2(DEPTH + 1)>) packet_count_out;
    _PORT(bool) protocol_error_out;
    _PORT(bool) clear_in;

    void _assign()
    {
        queue.write_valid_in = write_valid_in;
        queue.write_data_in = write_data_in;
        queue.write_keep_in = write_keep_in;
        queue.write_sop_in = write_sop_in;
        queue.write_eop_in = write_eop_in;
        queue.read_ready_in = read_ready_in;
        queue.clear_in = clear_in;
#ifndef SYNTHESIS
        queue.__inst_name = __inst_name + "/queue";
#endif
        queue._assign();

        write_ready_out = queue.write_ready_out;
        read_valid_out = queue.read_valid_out;
        read_data_out = queue.read_data_out;
        read_keep_out = queue.read_keep_out;
        read_sop_out = queue.read_sop_out;
        read_eop_out = queue.read_eop_out;
        empty_out = queue.empty_out;
        full_out = queue.full_out;
        packet_length_out = queue.packet_length_out;
        packet_count_out = queue.packet_count_out;
        protocol_error_out = queue.protocol_error_out;
    }
    void _work(bool reset) { queue._work(reset); }
    void _strobe() { queue._strobe(); }
};

template class TxQueue<256>;
