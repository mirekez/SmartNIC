#pragma once

// Network datapath top level.  RX balances, parses and stores packets before
// producing RxFifo descriptors.  TX commits CPU/DMA packet words into eight
// TxFifos and merges them onto one ordered aggregate MAC stream.

#include "InputBalancer.h"
#include "PacketParser.h"
#include "RxRAM.h"
#include "RxFifo.h"
#include "OutputMerger.h"
#include "../common/ClockDomains.h"

using namespace cpphdl;

template<size_t LANE_WIDTH = 64, size_t READ_PORTS = 1,
    size_t BANK_DEPTH = 4096, size_t RX_FIFO_DEPTH = 64,
    size_t TX_FIFO_WORDS = 2048>
class Network : public Module
{
public:
    static constexpr size_t STREAMS = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t LOGICAL_ROWS = BANK_DEPTH * 2;
    static constexpr size_t LOGICAL_ROW_BITS = clog2(LOGICAL_ROWS);
    static constexpr size_t HANDLE_BITS = LOGICAL_ROW_BITS + 3;
    static constexpr size_t FRAME_LENGTH_BITS = 14;

    // One aggregate ordered MAC/PCS stream.  Lane 0 byte 0 is earliest.
    _PORT(bool) valid_in;
    _PORT(logic<INPUT_BITS>) data_in;
    _PORT(logic<INPUT_BYTES>) keep_in;
    _PORT(logic<INPUT_BYTES>) sop_in;
    _PORT(logic<INPUT_BYTES>) eop_in;
    _PORT(bool) raw_in;
    _PORT(bool) ready_out;

    // Completed receive descriptors from RxFifo.
    _PORT(bool) descriptor_valid_out;
    _PORT(RxDescriptorWord) descriptor_data_out;
    _PORT(bool) descriptor_ready_in;

    // Processing-side packet reads forwarded to RxRAM.
    _PORT(logic<READ_PORTS>) read_valid_in;
    _PORT(logic<READ_PORTS * HANDLE_BITS>) read_handle_in;
    _PORT(logic<READ_PORTS * LOGICAL_ROW_BITS>) read_word_in;
    _PORT(logic<READ_PORTS>) read_ready_out;
    _PORT(logic<READ_PORTS * LANE_WIDTH>) read_data_out;
    _PORT(logic<READ_PORTS>) read_valid_out;
    _PORT(logic<READ_PORTS>) read_ready_in;
    _PORT(logic<READ_PORTS>) release_valid_in;
    _PORT(logic<READ_PORTS * HANDLE_BITS>) release_handle_in;
    _PORT(logic<READ_PORTS * FRAME_LENGTH_BITS>) release_length_in;

    // Two CPU/DMA transmit streams.  Every packet begins at byte zero of a
    // TxFifo word and becomes visible to the merger only when EOP is written.
    _PORT(logic<STREAMS>) tx_valid_in;
    _PORT(logic<INPUT_BITS>) tx_data_in;
    _PORT(logic<INPUT_BYTES>) tx_keep_in;
    _PORT(logic<STREAMS>) tx_sop_in;
    _PORT(logic<STREAMS>) tx_eop_in;
    _PORT(logic<STREAMS>) tx_ready_out;
    _PORT(logic<STREAMS>) tx_almost_full_out;

    // Ordered aggregate Ethernet output.  Byte zero is earliest on the wire.
    _PORT(bool) tx_valid_out;
    _PORT(logic<INPUT_BITS>) tx_data_out;
    _PORT(logic<INPUT_BYTES>) tx_keep_out;
    _PORT(logic<INPUT_BYTES>) tx_sop_out;
    _PORT(logic<INPUT_BYTES>) tx_eop_out;
    _PORT(bool) tx_ready_in;

    _PORT(bool) protocol_error_out;
    _PORT(bool) storage_full_out;

private:
    InputBalancer<LANE_WIDTH> balancer;
    PacketParser<LANE_WIDTH> parser;
    RxRAM<LANE_WIDTH, READ_PORTS, BANK_DEPTH> rx_ram;
    RxFifo<RX_FIFO_DEPTH> rx_fifo;
    OutputMerger<LANE_WIDTH, TX_FIFO_WORDS, 12> output_merger;

    reg<logic<512>> parser_word0_reg[STREAMS];
    reg<logic<512>> parser_word1_reg[STREAMS];
    reg<u1> parser_raw_reg[STREAMS];
    reg<u1> parser_first_reg[STREAMS];
    reg<u1> parser_complete_reg[STREAMS];

    reg<u32> ram_address_reg[STREAMS];
    reg<u16> ram_length_reg[STREAMS];
    reg<u1> ram_complete_reg[STREAMS];
    reg<u1> protocol_error_reg;

    logic<STREAMS> balanced_ready_comb;
    logic<STREAMS> parser_valid_comb;
    logic<STREAMS> ram_valid_comb;
    logic<STREAMS> raw_mask_comb;
    logic<STREAMS> parser_ready_comb;
    logic<STREAMS> ram_completion_ready_comb;
    logic<STREAMS> descriptor_valid_comb;
    RxDescriptorInputBus descriptor_input_comb;
    bool error_comb;

    logic<STREAMS>& balanced_ready_comb_func()
    {
        uint32_t stream;
        balanced_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            balanced_ready_comb[stream] = parser.ready_out()[stream]
                && rx_ram.ready_out()[stream];
        }
        return balanced_ready_comb;
    }

    // Gate each consumer with the other's readiness.  This makes consumption
    // atomic even though both modules observe the same balanced output beat.
    logic<STREAMS>& parser_valid_comb_func()
    {
        uint32_t stream;
        parser_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            parser_valid_comb[stream] = balancer.valid_out()[stream]
                && rx_ram.ready_out()[stream];
        }
        return parser_valid_comb;
    }

    logic<STREAMS>& ram_valid_comb_func()
    {
        uint32_t stream;
        ram_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            ram_valid_comb[stream] = balancer.valid_out()[stream]
                && parser.ready_out()[stream];
        }
        return ram_valid_comb;
    }

    logic<STREAMS>& raw_mask_comb_func()
    {
        uint32_t stream;
        raw_mask_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            raw_mask_comb[stream] = raw_in();
        }
        return raw_mask_comb;
    }

    logic<STREAMS>& parser_ready_comb_func()
    {
        uint32_t stream;
        parser_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            parser_ready_comb[stream] = !(bool)parser_complete_reg[stream];
        }
        return parser_ready_comb;
    }

    logic<STREAMS>& ram_completion_ready_comb_func()
    {
        uint32_t stream;
        ram_completion_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            ram_completion_ready_comb[stream] =
                !(bool)ram_complete_reg[stream];
        }
        return ram_completion_ready_comb;
    }

    logic<STREAMS>& descriptor_valid_comb_func()
    {
        uint32_t stream;
        descriptor_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            descriptor_valid_comb[stream] = parser_complete_reg[stream]
                && ram_complete_reg[stream];
        }
        return descriptor_valid_comb;
    }

    RxDescriptorInputBus& descriptor_input_comb_func()
    {
        uint32_t stream;
        RxDescriptorWord word;
        for (stream = 0; stream < STREAMS; ++stream) {
            word.raw = 0;
            word.descriptor = {};
            word.descriptor.packet_address = ram_address_reg[stream];
            word.descriptor.packet_length = ram_length_reg[stream];
            word.descriptor.ingress_stream = stream;
            word.descriptor.flags = (bool)parser_raw_reg[stream]
                ? RX_DESCRIPTOR_FLAG_RAW : 0;
            word.descriptor.reserved = 0;
            word.descriptor.packet_word0.raw = parser_word0_reg[stream];
            word.descriptor.packet_word1.raw = parser_word1_reg[stream];
            descriptor_input_comb[stream] = word;
        }
        return descriptor_input_comb;
    }

    bool& error_comb_func()
    {
        error_comb = (bool)protocol_error_reg
            || balancer.protocol_error_out()
            || parser.protocol_error_out()
            || rx_ram.protocol_error_out()
            || output_merger.protocol_error_out();
        return error_comb;
    }

public:
#ifndef SYNTHESIS
    bool debug_balancer_error() { return balancer.protocol_error_out(); }
    bool debug_parser_error() { return parser.protocol_error_out(); }
    bool debug_rx_ram_error() { return rx_ram.protocol_error_out(); }
    bool debug_join_error() { return protocol_error_reg; }
    uint32_t debug_balancer_words() const
    {
        return balancer.debug_total_words();
    }
    uint32_t debug_balancer_max_words() const
    {
        return balancer.debug_max_words();
    }
    uint32_t debug_rx_fifo_descriptors() const
    {
        return rx_fifo.debug_total_descriptors();
    }
    uint32_t debug_rx_ram_completions() const
    {
        return rx_ram.debug_completion_count();
    }
#endif

    void _assign()
    {
        balancer.valid_in = valid_in;
        balancer.data_in = data_in;
        balancer.keep_in = keep_in;
        balancer.sop_in = sop_in;
        balancer.eop_in = eop_in;
        balancer.ready_in = _ASSIGN_COMB(balanced_ready_comb_func());
        balancer.__inst_name = __inst_name + "/balancer";
        balancer._assign();

        parser.valid_in = _ASSIGN_COMB(parser_valid_comb_func());
        parser.data_in = _ASSIGN(balancer.data_out());
        parser.keep_in = _ASSIGN(balancer.keep_out());
        parser.sop_in = _ASSIGN(balancer.sop_out());
        parser.eop_in = _ASSIGN(balancer.eop_out());
        parser.raw_in = _ASSIGN_COMB(raw_mask_comb_func());
        parser.ready_in = _ASSIGN_COMB(parser_ready_comb_func());
        parser.__inst_name = __inst_name + "/parser";
        parser._assign();

        rx_ram.valid_in = _ASSIGN_COMB(ram_valid_comb_func());
        rx_ram.data_in = _ASSIGN(balancer.data_out());
        rx_ram.keep_in = _ASSIGN(balancer.keep_out());
        rx_ram.sop_in = _ASSIGN(balancer.sop_out());
        rx_ram.eop_in = _ASSIGN(balancer.eop_out());
        rx_ram.packet_ready_in =
            _ASSIGN_COMB(ram_completion_ready_comb_func());
        rx_ram.read_valid_in = read_valid_in;
        rx_ram.read_handle_in = read_handle_in;
        rx_ram.read_word_in = read_word_in;
        rx_ram.read_ready_in = read_ready_in;
        rx_ram.release_valid_in = release_valid_in;
        rx_ram.release_handle_in = release_handle_in;
        rx_ram.release_length_in = release_length_in;
        rx_ram.__inst_name = __inst_name + "/rx_ram";
        rx_ram._assign();

        rx_fifo.valid_in = _ASSIGN_COMB(descriptor_valid_comb_func());
        rx_fifo.data_in = _ASSIGN_COMB(descriptor_input_comb_func());
        rx_fifo.ready_in = descriptor_ready_in;
        rx_fifo.clear_in = _ASSIGN(false);
        rx_fifo.__inst_name = __inst_name + "/rx_fifo";
        rx_fifo._assign();

        output_merger.tx_valid_in = tx_valid_in;
        output_merger.tx_data_in = tx_data_in;
        output_merger.tx_keep_in = tx_keep_in;
        output_merger.tx_sop_in = tx_sop_in;
        output_merger.tx_eop_in = tx_eop_in;
        output_merger.ready_in = tx_ready_in;
        output_merger.__inst_name = __inst_name + "/output_merger";
        output_merger._assign();

        ready_out = _ASSIGN(balancer.ready_out());
        descriptor_valid_out = _ASSIGN(rx_fifo.valid_out());
        descriptor_data_out = _ASSIGN(rx_fifo.data_out());
        read_ready_out = _ASSIGN(rx_ram.read_ready_out());
        read_data_out = _ASSIGN(rx_ram.read_data_out());
        read_valid_out = _ASSIGN(rx_ram.read_valid_out());
        tx_ready_out = _ASSIGN(output_merger.tx_ready_out());
        tx_almost_full_out = _ASSIGN(output_merger.tx_almost_full_out());
        tx_valid_out = _ASSIGN(output_merger.valid_out());
        tx_data_out = _ASSIGN(output_merger.data_out());
        tx_keep_out = _ASSIGN(output_merger.keep_out());
        tx_sop_out = _ASSIGN(output_merger.sop_out());
        tx_eop_out = _ASSIGN(output_merger.eop_out());
        protocol_error_out = _ASSIGN_COMB(error_comb_func());
        storage_full_out = _ASSIGN(rx_ram.storage_full_out());
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        uint32_t stream;
        uint32_t bit;
        uint32_t address;
        uint32_t length;
        bool parser_fire;
        bool parser_raw;
        bool parser_last;
        bool fifo_fire;
        PacketParserOutputBus parser_bus;
        PacketParserWord parser_word;
        logic<STREAMS * HANDLE_BITS> handles;
        logic<STREAMS * FRAME_LENGTH_BITS> lengths;

        if (reset) {
            for (stream = 0; stream < STREAMS; ++stream) {
                parser_word0_reg[stream].clr();
                parser_word1_reg[stream].clr();
                parser_raw_reg[stream].clr();
                parser_first_reg[stream].clr();
                parser_complete_reg[stream].clr();
                ram_address_reg[stream].clr();
                ram_length_reg[stream].clr();
                ram_complete_reg[stream].clr();
            }
            protocol_error_reg.clr();
            balancer._work(true);
            parser._work(true);
            rx_ram._work(true);
            rx_fifo._work(true);
            output_merger._work(true);
            return;
        }

        parser_bus = parser.data_out();
        handles = rx_ram.packet_handle_out();
        lengths = rx_ram.packet_length_out();
        for (stream = 0; stream < STREAMS; ++stream) {
            fifo_fire = (bool)descriptor_valid_comb_func()[stream]
                && (bool)rx_fifo.ready_out()[stream];
            if (fifo_fire) {
                parser_complete_reg[stream]._next = 0;
                parser_first_reg[stream]._next = 0;
                ram_complete_reg[stream]._next = 0;
            }

            parser_fire = (bool)parser.valid_out()[stream]
                && (bool)parser_ready_comb_func()[stream];
            if (parser_fire) {
                parser_word = parser_bus[stream];
                parser_raw = (bool)parser.raw_out()[stream];
                parser_last = (bool)parser.last_out()[stream];
                if (!parser_raw) {
                    parser_word0_reg[stream]._next = parser_word.raw;
                    parser_word1_reg[stream]._next = 0;
                    parser_raw_reg[stream]._next = 0;
                    parser_first_reg[stream]._next = 1;
                    parser_complete_reg[stream]._next = parser_last;
                    if (!parser_last) {
                        protocol_error_reg._next = 1;
                    }
                }
                else if (!(bool)parser_first_reg[stream]) {
                    parser_word0_reg[stream]._next = parser_word.raw;
                    parser_word1_reg[stream]._next = 0;
                    parser_raw_reg[stream]._next = 1;
                    parser_first_reg[stream]._next = 1;
                    parser_complete_reg[stream]._next = parser_last;
                }
                else {
                    parser_word1_reg[stream]._next = parser_word.raw;
                    parser_complete_reg[stream]._next = parser_last;
                    if (!parser_last) {
                        protocol_error_reg._next = 1;
                    }
                }
            }

            if ((bool)rx_ram.packet_valid_out()[stream]
                && (bool)ram_completion_ready_comb_func()[stream]) {
                address = 0;
                length = 0;
                for (bit = 0; bit < HANDLE_BITS; ++bit) {
                    address |= (uint32_t)(bool)handles[
                        stream * HANDLE_BITS + bit] << bit;
                }
                for (bit = 0; bit < FRAME_LENGTH_BITS; ++bit) {
                    length |= (uint32_t)(bool)lengths[
                        stream * FRAME_LENGTH_BITS + bit] << bit;
                }
                ram_address_reg[stream]._next = address;
                ram_length_reg[stream]._next = length;
                ram_complete_reg[stream]._next = 1;
            }
        }

        balancer._work(false);
        parser._work(false);
        rx_ram._work(false);
        rx_fifo._work(false);
        output_merger._work(false);
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        uint32_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            parser_word0_reg[stream].strobe();
            parser_word1_reg[stream].strobe();
            parser_raw_reg[stream].strobe();
            parser_first_reg[stream].strobe();
            parser_complete_reg[stream].strobe();
            ram_address_reg[stream].strobe();
            ram_length_reg[stream].strobe();
            ram_complete_reg[stream].strobe();
        }
        protocol_error_reg.strobe();
        balancer._strobe();
        parser._strobe();
        rx_ram._strobe();
        rx_fifo._strobe();
        output_merger._strobe();
    }
#endif

    void _strobe()
    {
        uint32_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            parser_word0_reg[stream].strobe(); parser_word1_reg[stream].strobe();
            parser_raw_reg[stream].strobe(); parser_first_reg[stream].strobe();
            parser_complete_reg[stream].strobe(); ram_address_reg[stream].strobe();
            ram_length_reg[stream].strobe(); ram_complete_reg[stream].strobe();
        }
        protocol_error_reg.strobe(); balancer._strobe(); parser._strobe();
        rx_ram._strobe(); rx_fifo._strobe(); output_merger._strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class Network<64, 1, 4096, 64, 1024>;
