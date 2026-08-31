#pragma once

// Temporary hardware packet-processing engine for board bring-up. It consumes
// complete Network descriptors, reads the owning packet from RxRAM, and writes
// it unchanged into the opposite physical-port TxFifo. Each ingress owns an
// independent RxRAM read/stream engine so both 10G directions can run at once.

#include <cpphdl.h>
#include "../network/RxFifo.h"
#include "../../fpga/UART_PROBE.h"

using namespace cpphdl;

template<size_t HANDLE_BITS = 16, size_t FRAME_LENGTH_BITS = 14>
class ProcessingStub : public Module
{
public:
    static constexpr size_t STREAMS = 2;
    static constexpr size_t DATA_WIDTH = 256;
    static constexpr size_t KEEP_WIDTH = DATA_WIDTH / 8;
    static constexpr size_t DESCRIPTOR_WORDS = 5;
    static constexpr size_t RAW_DESCRIPTOR_FLAG = 1;
    static constexpr size_t PROBE_SCHEMA = 0x4b424c50; // "PLBK"

    _PORT(bool) descriptor_valid_in;
    _PORT(logic<DATA_WIDTH>) descriptor_data_in;
    _PORT(u<3>) descriptor_word_in;
    _PORT(bool) descriptor_sop_in;
    _PORT(bool) descriptor_eop_in;
    _PORT(bool) descriptor_ready_out;

    _PORT(logic<STREAMS>) rx_read_valid_out;
    _PORT(logic<STREAMS * HANDLE_BITS>) rx_read_handle_out;
    _PORT(logic<STREAMS * FRAME_LENGTH_BITS>) rx_read_length_out;
    _PORT(logic<STREAMS>) rx_read_ready_in;
    _PORT(logic<STREAMS>) rx_valid_in;
    _PORT(logic<STREAMS * DATA_WIDTH>) rx_data_in;
    _PORT(logic<STREAMS * KEEP_WIDTH>) rx_keep_in;
    _PORT(logic<STREAMS>) rx_sop_in;
    _PORT(logic<STREAMS>) rx_eop_in;
    _PORT(logic<STREAMS>) rx_ready_out;

    // Rx port N always drives Tx stream N XOR 1, with no shared packet
    // datapath or output arbitration.
    _PORT(logic<STREAMS>) tx_valid_out;
    _PORT(logic<STREAMS * DATA_WIDTH>) tx_data_out;
    _PORT(logic<STREAMS * KEEP_WIDTH>) tx_keep_out;
    _PORT(logic<STREAMS>) tx_sop_out;
    _PORT(logic<STREAMS>) tx_eop_out;
    _PORT(logic<STREAMS>) tx_ready_in;

    _PORT(logic<16>) system_status_in;
    _PORT(logic<4>) mac_tx_status_in;
    _PORT(bool) uart_rx_in;
    _PORT(bool) uart_trigger_in;
    _PORT(bool) uart_tx_out;
    _PORT(bool) probe_dumping_out;
    _PORT(bool) protocol_error_out;

private:
    UARTProbe<156'250'000, 115'200, 1, 1'024, PROBE_SCHEMA> uart_probe;

    reg<u<3>> descriptor_expected_word_reg;
    reg<u1> descriptor_active_reg;
    reg<u1> descriptor_source_reg;
    reg<u1> descriptor_source_valid_reg;
    reg<u1> job_pending_reg[STREAMS];
    reg<u<HANDLE_BITS>> job_handle_reg[STREAMS];
    reg<u<FRAME_LENGTH_BITS>> job_length_reg[STREAMS];
    reg<u1> stream_active_reg[STREAMS];
    reg<u1> stream_first_reg[STREAMS];
    reg<u<10>> stream_word_reg[STREAMS];
    reg<u32> received_packet_count_reg[STREAMS];
    reg<u32> transmitted_packet_count_reg[STREAMS];
    reg<u1> protocol_error_reg;
    reg<u1> probe_trigger_toggle_reg;
    reg<u8> probe_trigger_delay_reg;

    bool descriptor_ready_comb;
    logic<STREAMS> rx_read_valid_comb;
    logic<STREAMS * HANDLE_BITS> rx_read_handle_comb;
    logic<STREAMS * FRAME_LENGTH_BITS> rx_read_length_comb;
    logic<STREAMS> rx_ready_comb;
    logic<STREAMS> tx_valid_comb;
    logic<STREAMS * DATA_WIDTH> tx_data_comb;
    logic<STREAMS * KEEP_WIDTH> tx_keep_comb;
    logic<STREAMS> tx_sop_comb;
    logic<STREAMS> tx_eop_comb;
    logic<96> probe_data_comb;
    bool probe_trigger_comb;

    bool& descriptor_ready_comb_func()
    {
        uint32_t source;
        descriptor_ready_comb = descriptor_active_reg;
        if (!descriptor_active_reg) {
            if (!descriptor_valid_in()) descriptor_ready_comb = 1;
            else {
                source = (uint32_t)descriptor_data_in().bits(71, 64);
                descriptor_ready_comb = (uint32_t)descriptor_word_in() == 0
                    && source < STREAMS
                    && !job_pending_reg[source];
            }
        }
        return descriptor_ready_comb;
    }

    logic<STREAMS>& rx_read_valid_comb_func()
    {
        uint32_t source;
        rx_read_valid_comb = 0;
        for (source = 0; source < STREAMS; ++source)
            rx_read_valid_comb[source] = job_pending_reg[source];
        return rx_read_valid_comb;
    }

    logic<STREAMS * HANDLE_BITS>& rx_read_handle_comb_func()
    {
        uint32_t source;
        uint32_t bit;
        rx_read_handle_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            for (bit = 0; bit < HANDLE_BITS; ++bit)
                rx_read_handle_comb[source * HANDLE_BITS + bit] =
                    job_handle_reg[source][bit];
        }
        return rx_read_handle_comb;
    }

    logic<STREAMS * FRAME_LENGTH_BITS>& rx_read_length_comb_func()
    {
        uint32_t source;
        uint32_t bit;
        rx_read_length_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            for (bit = 0; bit < FRAME_LENGTH_BITS; ++bit)
                rx_read_length_comb[source * FRAME_LENGTH_BITS + bit] =
                    job_length_reg[source][bit];
        }
        return rx_read_length_comb;
    }

    logic<STREAMS>& rx_ready_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        rx_ready_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            rx_ready_comb[source] = (bool)tx_ready_in()[destination];
        }
        return rx_ready_comb;
    }

    logic<STREAMS>& tx_valid_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        tx_valid_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            tx_valid_comb[destination] = (bool)rx_valid_in()[source];
        }
        return tx_valid_comb;
    }

    logic<STREAMS * DATA_WIDTH>& tx_data_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        uint32_t bit;
        tx_data_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            for (bit = 0; bit < DATA_WIDTH; ++bit)
                tx_data_comb[destination * DATA_WIDTH + bit] =
                    rx_data_in()[source * DATA_WIDTH + bit];
        }
        return tx_data_comb;
    }

    logic<STREAMS * KEEP_WIDTH>& tx_keep_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        uint32_t byte;
        tx_keep_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            for (byte = 0; byte < KEEP_WIDTH; ++byte)
                tx_keep_comb[destination * KEEP_WIDTH + byte] =
                    rx_keep_in()[source * KEEP_WIDTH + byte];
        }
        return tx_keep_comb;
    }

    logic<STREAMS>& tx_sop_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        tx_sop_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            tx_sop_comb[destination] = (bool)rx_valid_in()[source]
                && (bool)rx_sop_in()[source];
        }
        return tx_sop_comb;
    }

    logic<STREAMS>& tx_eop_comb_func()
    {
        uint32_t source;
        uint32_t destination;
        tx_eop_comb = 0;
        for (source = 0; source < STREAMS; ++source) {
            destination = source ^ 1;
            tx_eop_comb[destination] = (bool)rx_valid_in()[source]
                && (bool)rx_eop_in()[source];
        }
        return tx_eop_comb;
    }

    logic<96>& probe_data_comb_func()
    {
        uint32_t bit;
        uint32_t probe_source;
        probe_data_comb = 0;
        probe_source = (bool)rx_valid_in()[0] ? 0 : 1;
        for (bit = 0; bit < 48; ++bit)
            probe_data_comb[bit] =
                rx_data_in()[probe_source * DATA_WIDTH + bit];
        probe_data_comb[48] = (bool)rx_valid_in()[0]
            || (bool)rx_valid_in()[1];
        probe_data_comb[49] = ((bool)rx_valid_in()[0]
                && (bool)rx_ready_comb_func()[0])
            || ((bool)rx_valid_in()[1] && (bool)rx_ready_comb_func()[1]);
        probe_data_comb[50] = (bool)rx_sop_in()[0]
            || (bool)rx_sop_in()[1];
        probe_data_comb[51] = (bool)rx_eop_in()[0]
            || (bool)rx_eop_in()[1];
        probe_data_comb[52] = tx_valid_comb_func()[0];
        probe_data_comb[53] = tx_ready_in()[0];
        probe_data_comb[54] = tx_valid_comb_func()[1];
        probe_data_comb[55] = tx_ready_in()[1];
        probe_data_comb[56] = job_pending_reg[0] || job_pending_reg[1];
        probe_data_comb[57] = (bool)rx_read_ready_in()[0]
            || (bool)rx_read_ready_in()[1];
        probe_data_comb[58] = descriptor_valid_in();
        probe_data_comb[59] = descriptor_ready_comb_func();
        probe_data_comb[60] = stream_active_reg[0] || stream_active_reg[1];
        probe_data_comb[61] = descriptor_active_reg;
        probe_data_comb[62] = probe_source;
        probe_data_comb[63] = probe_source ^ 1;
        probe_data_comb.bits(73, 64) = stream_word_reg[probe_source];
        probe_data_comb[74] = protocol_error_reg;
        probe_data_comb[75] = uart_probe.dumping_out();
        probe_data_comb.bits(79, 76) = mac_tx_status_in();
        probe_data_comb.bits(95, 80) = system_status_in();
        return probe_data_comb;
    }

    bool& probe_trigger_comb_func()
    {
        probe_trigger_comb = probe_trigger_toggle_reg;
        return probe_trigger_comb;
    }

public:
    void _assign()
    {
        descriptor_ready_out = _ASSIGN_COMB(descriptor_ready_comb_func());
        rx_read_valid_out = _ASSIGN_COMB(rx_read_valid_comb_func());
        rx_read_handle_out = _ASSIGN_COMB(rx_read_handle_comb_func());
        rx_read_length_out = _ASSIGN_COMB(rx_read_length_comb_func());
        rx_ready_out = _ASSIGN_COMB(rx_ready_comb_func());
        tx_valid_out = _ASSIGN_COMB(tx_valid_comb_func());
        tx_data_out = _ASSIGN_COMB(tx_data_comb_func());
        tx_keep_out = _ASSIGN_COMB(tx_keep_comb_func());
        tx_sop_out = _ASSIGN_COMB(tx_sop_comb_func());
        tx_eop_out = _ASSIGN_COMB(tx_eop_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);

        uart_probe.uart_rx_in = uart_rx_in;
        uart_probe.dump_trigger_in = _ASSIGN_COMB(probe_trigger_comb_func());
        uart_probe.probe_in = _ASSIGN_COMB(probe_data_comb_func());
        uart_probe.__inst_name = __inst_name + "/uart_probe";
        uart_probe._assign();
        uart_tx_out = _ASSIGN(uart_probe.uart_tx_out());
        probe_dumping_out = _ASSIGN(uart_probe.dumping_out());
    }

    void _work(bool reset)
    {
        bool descriptor_fire;
        bool command_fire;
        bool stream_fire;
        uint32_t source;
        uint32_t ingress;
        uint32_t flags;

        descriptor_fire = descriptor_valid_in()
            && descriptor_ready_comb_func();
        if (descriptor_fire) {
            if (descriptor_sop_in()) {
                if (descriptor_active_reg
                    || (uint32_t)descriptor_word_in() != 0)
                    protocol_error_reg._next = 1;
                descriptor_active_reg._next = 1;
                descriptor_expected_word_reg._next = 0;
            }
            if (!descriptor_active_reg && !descriptor_sop_in())
                protocol_error_reg._next = 1;
            if ((uint32_t)descriptor_word_in()
                != (uint32_t)descriptor_expected_word_reg)
                protocol_error_reg._next = 1;

            if ((uint32_t)descriptor_word_in() == 0) {
                ingress = (uint32_t)descriptor_data_in().bits(55, 48);
                flags = (uint32_t)descriptor_data_in().bits(63, 56);
                source = (uint32_t)descriptor_data_in().bits(71, 64);
                descriptor_source_reg._next = source;
                descriptor_source_valid_reg._next = source < STREAMS;
                if (source < STREAMS) {
                    job_handle_reg[source]._next =
                        descriptor_data_in().bits(HANDLE_BITS - 1, 0);
                    job_length_reg[source]._next = descriptor_data_in().bits(
                        32 + FRAME_LENGTH_BITS - 1, 32);
                }
                if (source >= STREAMS || ingress != source
                    || flags != RAW_DESCRIPTOR_FLAG)
                    protocol_error_reg._next = 1;
            }

            if (descriptor_eop_in()) {
                if ((uint32_t)descriptor_word_in()
                    != DESCRIPTOR_WORDS - 1)
                    protocol_error_reg._next = 1;
                descriptor_active_reg._next = 0;
                descriptor_expected_word_reg._next = 0;
                if (descriptor_source_valid_reg) {
                    source = (uint32_t)descriptor_source_reg;
                    job_pending_reg[source]._next = 1;
                    received_packet_count_reg[source]._next =
                        received_packet_count_reg[source] + 1;
                }
                descriptor_source_valid_reg._next = 0;
            }
            else descriptor_expected_word_reg._next = descriptor_word_in() + 1;
        }

        for (source = 0; source < STREAMS; ++source) {
            command_fire = job_pending_reg[source]
                && (bool)rx_read_ready_in()[source];
            stream_fire = (bool)rx_valid_in()[source]
                && (bool)rx_ready_comb_func()[source];
            if (command_fire) {
                job_pending_reg[source]._next = 0;
                stream_word_reg[source].clr();
                if ((uint32_t)job_length_reg[source] == 0)
                    protocol_error_reg._next = 1;
            }
            if (stream_fire) {
                if ((bool)rx_sop_in()[source]
                    != (bool)stream_first_reg[source])
                    protocol_error_reg._next = 1;
                if ((uint64_t)rx_keep_in().bits(
                    source * KEEP_WIDTH + KEEP_WIDTH - 1,
                    source * KEEP_WIDTH) == 0)
                    protocol_error_reg._next = 1;
                if ((bool)rx_sop_in()[source])
                    stream_active_reg[source]._next = 1;
                stream_first_reg[source]._next = 0;
                stream_word_reg[source]._next = stream_word_reg[source] + 1;
                if ((bool)rx_eop_in()[source]) {
                    stream_active_reg[source]._next = 0;
                    stream_first_reg[source]._next = 1;
                    transmitted_packet_count_reg[source]._next =
                        transmitted_packet_count_reg[source] + 1;
                    if ((uint32_t)probe_trigger_delay_reg == 0)
                        probe_trigger_delay_reg._next = 64;
                }
            }
        }

        if ((uint32_t)probe_trigger_delay_reg != 0) {
            probe_trigger_delay_reg._next = probe_trigger_delay_reg - 1;
            if ((uint32_t)probe_trigger_delay_reg == 1)
                probe_trigger_toggle_reg._next = !probe_trigger_toggle_reg;
        }

        uart_probe._work(reset);
        if (reset) {
            descriptor_expected_word_reg.clr();
            descriptor_active_reg.clr();
            descriptor_source_reg.clr();
            descriptor_source_valid_reg.clr();
            for (source = 0; source < STREAMS; ++source) {
                job_pending_reg[source].clr();
                job_handle_reg[source].clr();
                job_length_reg[source].clr();
                stream_active_reg[source].clr();
                stream_first_reg[source]._next = 1;
                stream_word_reg[source].clr();
                received_packet_count_reg[source].clr();
                transmitted_packet_count_reg[source].clr();
            }
            protocol_error_reg.clr();
            probe_trigger_toggle_reg.clr();
            probe_trigger_delay_reg.clr();
        }
    }

    void _strobe()
    {
        uint32_t source;
        descriptor_expected_word_reg.strobe();
        descriptor_active_reg.strobe();
        descriptor_source_reg.strobe();
        descriptor_source_valid_reg.strobe();
        for (source = 0; source < STREAMS; ++source) {
            job_pending_reg[source].strobe();
            job_handle_reg[source].strobe();
            job_length_reg[source].strobe();
            stream_active_reg[source].strobe();
            stream_first_reg[source].strobe();
            stream_word_reg[source].strobe();
            received_packet_count_reg[source].strobe();
            transmitted_packet_count_reg[source].strobe();
        }
        protocol_error_reg.strobe();
        probe_trigger_toggle_reg.strobe();
        probe_trigger_delay_reg.strobe();
        uart_probe._strobe();
    }
};

template class ProcessingStub<16, 14>;
