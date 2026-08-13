#pragma once

#define SMARTNIC_TWO_CLOCKS 1

// SmartNIC RTL root.  The external side is the ordered post-PCS Ethernet
// stream used by Network.  The L2 side uses 256-bit framed streams and packet
// read commands; all crossings use Gray-pointer asynchronous FIFOs.

#include "network/Network.h"
#include "common/AsyncFifo.h"
#include "common/AsyncPacketStream.h"
#include "Config.h"

using namespace cpphdl;

#define SMARTNIC_FOR_EACH_RX_PORT(M) \
    M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7)
#define SMARTNIC_FOR_EACH_TX_STREAM(M) \
    M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7)

template<size_t LANE_WIDTH = NET_LANE_WIDTH,
    size_t BANK_DEPTH = RX_RAM_BANK_DEPTH,
    size_t RX_FIFO_DEPTH = 64, size_t TX_FIFO_WORDS = 1024>
class SmartNIC : public Module
{
public:
    static constexpr size_t STREAMS = 8;
    static constexpr size_t READ_PORTS = 8;
    static constexpr size_t L2_WIDTH = 256;
    static constexpr size_t L2_BYTES = L2_WIDTH / 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t NET_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t NET_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t LOGICAL_ROWS = BANK_DEPTH * 2;
    static constexpr size_t LOGICAL_ROW_BITS = clog2(LOGICAL_ROWS);
    static constexpr size_t HANDLE_BITS = LOGICAL_ROW_BITS + 3;
    static constexpr size_t FRAME_LENGTH_BITS = 14;
    static constexpr size_t READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    static constexpr size_t READ_META_DEPTH = 8;

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320,
        "SmartNIC supports 400G (160-bit lanes) and 800G (320-bit lanes)");

    // Ordered post-PCS Ethernet receive input, passed directly to Network.
    _PORT(bool) net_rx_valid_in;
    _PORT(logic<NET_BITS>) net_rx_data_in;
    _PORT(logic<NET_BYTES>) net_rx_keep_in;
    _PORT(logic<NET_BYTES>) net_rx_sop_in;
    _PORT(logic<NET_BYTES>) net_rx_eop_in;
    _PORT(bool) net_rx_raw_in;
    _PORT(bool) net_rx_ready_out;

    // Ordered Ethernet transmit output, passed directly from Network.
    _PORT(bool) net_tx_valid_out;
    _PORT(logic<NET_BITS>) net_tx_data_out;
    _PORT(logic<NET_BYTES>) net_tx_keep_out;
    _PORT(logic<NET_BYTES>) net_tx_sop_out;
    _PORT(logic<NET_BYTES>) net_tx_eop_out;
    _PORT(bool) net_tx_ready_in;

    // Receive descriptors are five consecutive 256-bit words.
    _PORT(bool) l2_descriptor_valid_out;
    _PORT(logic<L2_WIDTH>) l2_descriptor_data_out;
    _PORT(u<3>) l2_descriptor_word_out;
    _PORT(bool) l2_descriptor_sop_out;
    _PORT(bool) l2_descriptor_eop_out;
    _PORT(bool) l2_descriptor_ready_in;

    // Eight packet read engines.  A command supplies the RxRAM handle from the
    // descriptor and exact packet length; output is a framed 256-bit stream.
    _PORT(logic<READ_PORTS>) l2_rx_read_valid_in;
    _PORT(logic<READ_PORTS * HANDLE_BITS>) l2_rx_read_handle_in;
    _PORT(logic<READ_PORTS * FRAME_LENGTH_BITS>) l2_rx_read_length_in;
    _PORT(logic<READ_PORTS>) l2_rx_read_ready_out;
    _PORT(logic<READ_PORTS>) l2_rx_valid_out;
    _PORT(logic<READ_PORTS * L2_WIDTH>) l2_rx_data_out;
    _PORT(logic<READ_PORTS * L2_BYTES>) l2_rx_keep_out;
    _PORT(logic<READ_PORTS>) l2_rx_sop_out;
    _PORT(logic<READ_PORTS>) l2_rx_eop_out;
    _PORT(logic<READ_PORTS>) l2_rx_ready_in;

    // Eight independent L2 transmit packet streams.
    _PORT(logic<STREAMS>) l2_tx_valid_in;
    _PORT(logic<STREAMS * L2_WIDTH>) l2_tx_data_in;
    _PORT(logic<STREAMS * L2_BYTES>) l2_tx_keep_in;
    _PORT(logic<STREAMS>) l2_tx_sop_in;
    _PORT(logic<STREAMS>) l2_tx_eop_in;
    _PORT(logic<STREAMS>) l2_tx_ready_out;

    _PORT(bool) protocol_error_out;
    _PORT(bool) storage_full_out;

private:
    Network<LANE_WIDTH, READ_PORTS, BANK_DEPTH, RX_FIFO_DEPTH,
        TX_FIFO_WORDS> network;
    AsyncFifoNetToL2<1280, 16> descriptor_fifo;
    AsyncFifoL2ToNet<READ_COMMAND_BITS, 16> read_command_fifo[READ_PORTS];
    AsyncPacketStreamNetToL2<LANE_WIDTH, L2_WIDTH, 16>
        rx_stream_cdc[READ_PORTS];
    AsyncPacketStreamL2ToNet<L2_WIDTH, LANE_WIDTH, 16>
        tx_stream_cdc[STREAMS];

    // Net-domain RxRAM sequential read engines and response metadata queues.
    reg<u1> read_active_reg[READ_PORTS];
    reg<u<HANDLE_BITS>> read_handle_reg[READ_PORTS];
    reg<u<FRAME_LENGTH_BITS>> read_length_reg[READ_PORTS];
    reg<u<FRAME_LENGTH_BITS>> read_remaining_reg[READ_PORTS];
    reg<u<LOGICAL_ROW_BITS>> read_word_reg[READ_PORTS];
    reg<u<6>> meta_bytes_reg[READ_PORTS][READ_META_DEPTH];
    reg<u1> meta_sop_reg[READ_PORTS][READ_META_DEPTH];
    reg<u1> meta_eop_reg[READ_PORTS][READ_META_DEPTH];
    reg<u<HANDLE_BITS>> meta_handle_reg[READ_PORTS][READ_META_DEPTH];
    reg<u<FRAME_LENGTH_BITS>> meta_length_reg[READ_PORTS][READ_META_DEPTH];
    reg<u<3>> meta_head_reg[READ_PORTS];
    reg<u<3>> meta_tail_reg[READ_PORTS];
    reg<u<4>> meta_count_reg[READ_PORTS];

    // L2-domain descriptor serializer.
    reg<logic<1280>> descriptor_hold_reg;
    reg<u<3>> descriptor_word_reg;
    reg<u1> descriptor_valid_reg;

    logic<READ_PORTS> network_read_valid_comb;
    logic<READ_PORTS * HANDLE_BITS> network_read_handle_comb;
    logic<READ_PORTS * LOGICAL_ROW_BITS> network_read_word_comb;
    logic<READ_PORTS> network_read_ready_comb;
    logic<READ_PORTS> network_release_valid_comb;
    logic<READ_PORTS * HANDLE_BITS> network_release_handle_comb;
    logic<READ_PORTS * FRAME_LENGTH_BITS> network_release_length_comb;
    logic<STREAMS> network_tx_valid_comb;
    logic<NET_BITS> network_tx_data_comb;
    logic<NET_BYTES> network_tx_keep_comb;
    logic<STREAMS> network_tx_sop_comb;
    logic<STREAMS> network_tx_eop_comb;
    logic<READ_PORTS> l2_read_command_ready_comb;
    logic<READ_PORTS> l2_rx_valid_comb;
    logic<READ_PORTS * L2_WIDTH> l2_rx_data_comb;
    logic<READ_PORTS * L2_BYTES> l2_rx_keep_comb;
    logic<READ_PORTS> l2_rx_sop_comb;
    logic<READ_PORTS> l2_rx_eop_comb;
    logic<STREAMS> l2_tx_ready_comb;
    logic<L2_WIDTH> descriptor_word_comb;

    logic<L2_WIDTH>& descriptor_word_comb_func()
    {
        uint32_t bit;
        uint32_t base;
        descriptor_word_comb = 0;
        base = (uint32_t)descriptor_word_reg * L2_WIDTH;
        for (bit = 0; bit < L2_WIDTH; ++bit) {
            descriptor_word_comb[bit] = descriptor_hold_reg[base + bit];
        }
        return descriptor_word_comb;
    }

    logic<READ_PORTS>& network_read_valid_comb_func()
    {
        uint32_t port;
        network_read_valid_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            network_read_valid_comb[port] = read_active_reg[port]
                && (uint32_t)meta_count_reg[port] < READ_META_DEPTH;
        }
        return network_read_valid_comb;
    }

    logic<READ_PORTS * HANDLE_BITS>& network_read_handle_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        network_read_handle_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < HANDLE_BITS; ++bit) {
                network_read_handle_comb[port * HANDLE_BITS + bit] =
                    read_handle_reg[port][bit];
            }
        }
        return network_read_handle_comb;
    }

    logic<READ_PORTS * LOGICAL_ROW_BITS>& network_read_word_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        network_read_word_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < LOGICAL_ROW_BITS; ++bit) {
                network_read_word_comb[port * LOGICAL_ROW_BITS + bit] =
                    read_word_reg[port][bit];
            }
        }
        return network_read_word_comb;
    }

    logic<READ_PORTS>& network_read_ready_comb_func()
    {
        uint32_t port;
        network_read_ready_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            network_read_ready_comb[port] =
                (uint32_t)meta_count_reg[port] != 0
                && rx_stream_cdc[port].ready_out();
        }
        return network_read_ready_comb;
    }

    logic<READ_PORTS>& network_release_valid_comb_func()
    {
        uint32_t port;
        uint32_t head;
        network_release_valid_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            head = (uint32_t)meta_head_reg[port];
            network_release_valid_comb[port] = network.read_valid_out()[port]
                && network_read_ready_comb_func()[port]
                && meta_eop_reg[port][head];
        }
        return network_release_valid_comb;
    }

    logic<READ_PORTS * HANDLE_BITS>& network_release_handle_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        network_release_handle_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < HANDLE_BITS; ++bit) {
                network_release_handle_comb[port * HANDLE_BITS + bit] =
                    meta_handle_reg[port][(uint32_t)meta_head_reg[port]][bit];
            }
        }
        return network_release_handle_comb;
    }

    logic<READ_PORTS * FRAME_LENGTH_BITS>& network_release_length_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        network_release_length_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < FRAME_LENGTH_BITS; ++bit) {
                network_release_length_comb[port * FRAME_LENGTH_BITS + bit] =
                    meta_length_reg[port][(uint32_t)meta_head_reg[port]][bit];
            }
        }
        return network_release_length_comb;
    }

    logic<READ_PORTS>& l2_read_command_ready_comb_func()
    {
        uint32_t port;
        l2_read_command_ready_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            l2_read_command_ready_comb[port] =
                read_command_fifo[port].write_ready_out();
        }
        return l2_read_command_ready_comb;
    }

    logic<READ_PORTS>& l2_rx_valid_comb_func()
    {
        uint32_t port;
        l2_rx_valid_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            l2_rx_valid_comb[port] = rx_stream_cdc[port].valid_out();
        }
        return l2_rx_valid_comb;
    }

    logic<READ_PORTS * L2_WIDTH>& l2_rx_data_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        l2_rx_data_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < L2_WIDTH; ++bit) {
                l2_rx_data_comb[port * L2_WIDTH + bit] =
                    rx_stream_cdc[port].data_out()[bit];
            }
        }
        return l2_rx_data_comb;
    }

    logic<READ_PORTS * L2_BYTES>& l2_rx_keep_comb_func()
    {
        uint32_t port;
        uint32_t byte;
        l2_rx_keep_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (byte = 0; byte < L2_BYTES; ++byte) {
                l2_rx_keep_comb[port * L2_BYTES + byte] =
                    rx_stream_cdc[port].keep_out()[byte];
            }
        }
        return l2_rx_keep_comb;
    }

    logic<READ_PORTS>& l2_rx_sop_comb_func()
    {
        uint32_t port;
        l2_rx_sop_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            l2_rx_sop_comb[port] = rx_stream_cdc[port].sop_out();
        }
        return l2_rx_sop_comb;
    }

    logic<READ_PORTS>& l2_rx_eop_comb_func()
    {
        uint32_t port;
        l2_rx_eop_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            l2_rx_eop_comb[port] = rx_stream_cdc[port].eop_out();
        }
        return l2_rx_eop_comb;
    }

    logic<STREAMS>& l2_tx_ready_comb_func()
    {
        uint32_t stream;
        l2_tx_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            l2_tx_ready_comb[stream] = tx_stream_cdc[stream].ready_out();
        }
        return l2_tx_ready_comb;
    }

    logic<STREAMS>& network_tx_valid_comb_func()
    {
        uint32_t stream;
        network_tx_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            network_tx_valid_comb[stream] = tx_stream_cdc[stream].valid_out();
        }
        return network_tx_valid_comb;
    }

    logic<NET_BITS>& network_tx_data_comb_func()
    {
        uint32_t stream;
        uint32_t bit;
        network_tx_data_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            for (bit = 0; bit < LANE_WIDTH; ++bit) {
                network_tx_data_comb[stream * LANE_WIDTH + bit] =
                    tx_stream_cdc[stream].data_out()[bit];
            }
        }
        return network_tx_data_comb;
    }

    logic<NET_BYTES>& network_tx_keep_comb_func()
    {
        uint32_t stream;
        uint32_t byte;
        network_tx_keep_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                network_tx_keep_comb[stream * LANE_BYTES + byte] =
                    tx_stream_cdc[stream].keep_out()[byte];
            }
        }
        return network_tx_keep_comb;
    }

    logic<STREAMS>& network_tx_sop_comb_func()
    {
        uint32_t stream;
        network_tx_sop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            network_tx_sop_comb[stream] = tx_stream_cdc[stream].sop_out();
        }
        return network_tx_sop_comb;
    }

    logic<STREAMS>& network_tx_eop_comb_func()
    {
        uint32_t stream;
        network_tx_eop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            network_tx_eop_comb[stream] = tx_stream_cdc[stream].eop_out();
        }
        return network_tx_eop_comb;
    }

#define SMARTNIC_DECLARE_READ_PORT_FUNCS(number) \
    logic<READ_COMMAND_BITS> read_command_##number##_comb; \
    logic<READ_COMMAND_BITS>& read_command_##number##_comb_func() \
    { \
        read_command_##number##_comb = 0; \
        read_command_##number##_comb.bits(HANDLE_BITS - 1, 0) = \
            l2_rx_read_handle_in().bits(number * HANDLE_BITS + HANDLE_BITS - 1, \
                number * HANDLE_BITS); \
        read_command_##number##_comb.bits(READ_COMMAND_BITS - 1, HANDLE_BITS) = \
            l2_rx_read_length_in().bits(number * FRAME_LENGTH_BITS \
                + FRAME_LENGTH_BITS - 1, number * FRAME_LENGTH_BITS); \
        return read_command_##number##_comb; \
    } \
    bool read_command_pop_##number##_comb; \
    bool& read_command_pop_##number##_comb_func() \
    { \
        read_command_pop_##number##_comb = !(bool)read_active_reg[number] \
            || ((uint32_t)read_remaining_reg[number] <= LANE_BYTES \
                && (uint32_t)meta_count_reg[number] < READ_META_DEPTH \
                && (bool)network.read_ready_out()[number]); \
        return read_command_pop_##number##_comb; \
    } \
    logic<LANE_WIDTH> rx_input_data_##number##_comb; \
    logic<LANE_WIDTH>& rx_input_data_##number##_comb_func() \
    { \
        rx_input_data_##number##_comb = network.read_data_out().bits( \
            number * LANE_WIDTH + LANE_WIDTH - 1, number * LANE_WIDTH); \
        return rx_input_data_##number##_comb; \
    } \
    logic<LANE_BYTES> rx_input_keep_##number##_comb; \
    logic<LANE_BYTES>& rx_input_keep_##number##_comb_func() \
    { \
        uint32_t byte; \
        uint32_t head; \
        rx_input_keep_##number##_comb = 0; \
        head = (uint32_t)meta_head_reg[number]; \
        for (byte = 0; byte < LANE_BYTES; ++byte) { \
            rx_input_keep_##number##_comb[byte] = \
                byte < (uint32_t)meta_bytes_reg[number][head]; \
        } \
        return rx_input_keep_##number##_comb; \
    }
    SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_DECLARE_READ_PORT_FUNCS)
#undef SMARTNIC_DECLARE_READ_PORT_FUNCS

public:
#ifndef SYNTHESIS
    bool debug_network_balancer_error()
    {
        return network.debug_balancer_error();
    }
    bool debug_network_parser_error()
    {
        return network.debug_parser_error();
    }
    bool debug_network_rx_ram_error()
    {
        return network.debug_rx_ram_error();
    }
    bool debug_network_join_error()
    {
        return network.debug_join_error();
    }
    uint32_t debug_network_balancer_words() const
    {
        return network.debug_balancer_words();
    }
    uint32_t debug_network_balancer_max_words() const
    {
        return network.debug_balancer_max_words();
    }
    uint32_t debug_network_rx_fifo_descriptors() const
    {
        return network.debug_rx_fifo_descriptors();
    }
    uint32_t debug_network_rx_ram_completions() const
    {
        return network.debug_rx_ram_completions();
    }
#endif

    void _assign()
    {
        network.valid_in = net_rx_valid_in;
        network.data_in = net_rx_data_in;
        network.keep_in = net_rx_keep_in;
        network.sop_in = net_rx_sop_in;
        network.eop_in = net_rx_eop_in;
        network.raw_in = net_rx_raw_in;
        network.descriptor_ready_in = _ASSIGN(descriptor_fifo.write_ready_out());
        network.read_valid_in = _ASSIGN_COMB(network_read_valid_comb_func());
        network.read_handle_in = _ASSIGN_COMB(network_read_handle_comb_func());
        network.read_word_in = _ASSIGN_COMB(network_read_word_comb_func());
        network.read_ready_in = _ASSIGN_COMB(network_read_ready_comb_func());
        network.release_valid_in =
            _ASSIGN_COMB(network_release_valid_comb_func());
        network.release_handle_in =
            _ASSIGN_COMB(network_release_handle_comb_func());
        network.release_length_in =
            _ASSIGN_COMB(network_release_length_comb_func());
        network.tx_valid_in = _ASSIGN_COMB(network_tx_valid_comb_func());
        network.tx_data_in = _ASSIGN_COMB(network_tx_data_comb_func());
        network.tx_keep_in = _ASSIGN_COMB(network_tx_keep_comb_func());
        network.tx_sop_in = _ASSIGN_COMB(network_tx_sop_comb_func());
        network.tx_eop_in = _ASSIGN_COMB(network_tx_eop_comb_func());
        network.tx_ready_in = net_tx_ready_in;
        network.__inst_name = __inst_name + "/network";
        network._assign();

        descriptor_fifo.write_valid_in = _ASSIGN(network.descriptor_valid_out());
        descriptor_fifo.write_data_in =
            _ASSIGN(network.descriptor_data_out().raw);
        descriptor_fifo.read_ready_in =
            _ASSIGN(!(bool)descriptor_valid_reg);
        descriptor_fifo.__inst_name = __inst_name + "/descriptor_fifo";
        descriptor_fifo._assign();

#define SMARTNIC_BIND_READ_PORT(number) \
        read_command_fifo[number].write_valid_in = \
            _ASSIGN((bool)l2_rx_read_valid_in()[number]); \
        read_command_fifo[number].write_data_in = \
            _ASSIGN_COMB(read_command_##number##_comb_func()); \
        read_command_fifo[number].read_ready_in = \
            _ASSIGN_COMB(read_command_pop_##number##_comb_func()); \
        read_command_fifo[number].__inst_name = __inst_name \
            + "/read_command_fifo" + std::to_string(number); \
        read_command_fifo[number]._assign(); \
        rx_stream_cdc[number].valid_in = _ASSIGN( \
            (bool)network.read_valid_out()[number] \
            && (uint32_t)meta_count_reg[number] != 0); \
        rx_stream_cdc[number].data_in = \
            _ASSIGN_COMB(rx_input_data_##number##_comb_func()); \
        rx_stream_cdc[number].keep_in = \
            _ASSIGN_COMB(rx_input_keep_##number##_comb_func()); \
        rx_stream_cdc[number].sop_in = _ASSIGN((bool)meta_sop_reg[number][ \
            (uint32_t)meta_head_reg[number]]); \
        rx_stream_cdc[number].eop_in = _ASSIGN((bool)meta_eop_reg[number][ \
            (uint32_t)meta_head_reg[number]]); \
        rx_stream_cdc[number].ready_in = \
            _ASSIGN((bool)l2_rx_ready_in()[number]); \
        rx_stream_cdc[number].__inst_name = __inst_name \
            + "/rx_stream_cdc" + std::to_string(number); \
        rx_stream_cdc[number]._assign();
        SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_BIND_READ_PORT)
#undef SMARTNIC_BIND_READ_PORT

#define SMARTNIC_BIND_TX_STREAM(number) \
        tx_stream_cdc[number].valid_in = \
            _ASSIGN((bool)l2_tx_valid_in()[number]); \
        tx_stream_cdc[number].data_in = _ASSIGN(l2_tx_data_in().bits( \
            number * L2_WIDTH + L2_WIDTH - 1, number * L2_WIDTH)); \
        tx_stream_cdc[number].keep_in = _ASSIGN(l2_tx_keep_in().bits( \
            number * L2_BYTES + L2_BYTES - 1, number * L2_BYTES)); \
        tx_stream_cdc[number].sop_in = _ASSIGN((bool)l2_tx_sop_in()[number]); \
        tx_stream_cdc[number].eop_in = _ASSIGN((bool)l2_tx_eop_in()[number]); \
        tx_stream_cdc[number].ready_in = \
            _ASSIGN((bool)network.tx_ready_out()[number]); \
        tx_stream_cdc[number].__inst_name = __inst_name \
            + "/tx_stream_cdc" + std::to_string(number); \
        tx_stream_cdc[number]._assign();
        SMARTNIC_FOR_EACH_TX_STREAM(SMARTNIC_BIND_TX_STREAM)
#undef SMARTNIC_BIND_TX_STREAM

        net_rx_ready_out = _ASSIGN(network.ready_out());
        net_tx_valid_out = _ASSIGN(network.tx_valid_out());
        net_tx_data_out = _ASSIGN(network.tx_data_out());
        net_tx_keep_out = _ASSIGN(network.tx_keep_out());
        net_tx_sop_out = _ASSIGN(network.tx_sop_out());
        net_tx_eop_out = _ASSIGN(network.tx_eop_out());
        l2_descriptor_valid_out = _ASSIGN_REG(descriptor_valid_reg);
        l2_descriptor_data_out = _ASSIGN_COMB(descriptor_word_comb_func());
        l2_descriptor_word_out = _ASSIGN_REG(descriptor_word_reg);
        l2_descriptor_sop_out = _ASSIGN((bool)descriptor_valid_reg
            && (uint32_t)descriptor_word_reg == 0);
        l2_descriptor_eop_out = _ASSIGN((bool)descriptor_valid_reg
            && (uint32_t)descriptor_word_reg == 4);
        l2_rx_read_ready_out = _ASSIGN_COMB(l2_read_command_ready_comb_func());
        l2_rx_valid_out = _ASSIGN_COMB(l2_rx_valid_comb_func());
        l2_rx_data_out = _ASSIGN_COMB(l2_rx_data_comb_func());
        l2_rx_keep_out = _ASSIGN_COMB(l2_rx_keep_comb_func());
        l2_rx_sop_out = _ASSIGN_COMB(l2_rx_sop_comb_func());
        l2_rx_eop_out = _ASSIGN_COMB(l2_rx_eop_comb_func());
        l2_tx_ready_out = _ASSIGN_COMB(l2_tx_ready_comb_func());
        protocol_error_out = _ASSIGN(network.protocol_error_out());
        storage_full_out = _ASSIGN(network.storage_full_out());
    }

    void _work_net_clk(bool reset)
    {
        uint32_t port;
        uint32_t slot;
        uint32_t head;
        uint32_t tail;
        uint32_t count;
        uint32_t remaining;
        uint32_t bytes;
        bool command_fire;
        bool request_fire;
        bool response_fire;
        bool last_request;
        logic<READ_COMMAND_BITS> command;

#ifndef SYNTHESIS
        network._work_net_clk(reset);
        descriptor_fifo._work_net_clk(reset);
#define SMARTNIC_WORK_NET_RX(number) \
        read_command_fifo[number]._work_net_clk(reset); \
        rx_stream_cdc[number]._work_net_clk(reset);
        SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_WORK_NET_RX)
#undef SMARTNIC_WORK_NET_RX
#define SMARTNIC_WORK_NET_TX(number) \
        tx_stream_cdc[number]._work_net_clk(reset);
        SMARTNIC_FOR_EACH_TX_STREAM(SMARTNIC_WORK_NET_TX)
#undef SMARTNIC_WORK_NET_TX
#endif

        for (port = 0; port < READ_PORTS; ++port) {
            head = (uint32_t)meta_head_reg[port];
            tail = (uint32_t)meta_tail_reg[port];
            count = (uint32_t)meta_count_reg[port];
            request_fire = (bool)network_read_valid_comb_func()[port]
                && (bool)network.read_ready_out()[port];
            remaining = (uint32_t)read_remaining_reg[port];
            last_request = request_fire && remaining <= LANE_BYTES;
            command_fire = read_command_fifo[port].read_valid_out()
                && (!(bool)read_active_reg[port] || last_request);
            if (command_fire) {
                command = read_command_fifo[port].read_data_out();
                read_handle_reg[port]._next =
                    command.bits(HANDLE_BITS - 1, 0);
                read_remaining_reg[port]._next = command.bits(
                    READ_COMMAND_BITS - 1, HANDLE_BITS);
                read_length_reg[port]._next = command.bits(
                    READ_COMMAND_BITS - 1, HANDLE_BITS);
                read_word_reg[port]._next = 0;
                read_active_reg[port]._next =
                    command.bits(READ_COMMAND_BITS - 1, HANDLE_BITS) != 0;
            }

            response_fire = (bool)network.read_valid_out()[port]
                && (bool)network_read_ready_comb_func()[port];
            if (response_fire) {
                head = (head + 1) & (READ_META_DEPTH - 1);
                --count;
            }
            if (request_fire) {
                bytes = remaining > LANE_BYTES ? LANE_BYTES : remaining;
                meta_bytes_reg[port][tail]._next = bytes;
                meta_sop_reg[port][tail]._next =
                    (uint32_t)read_word_reg[port] == 0;
                meta_eop_reg[port][tail]._next = remaining <= LANE_BYTES;
                meta_handle_reg[port][tail]._next = read_handle_reg[port];
                meta_length_reg[port][tail]._next = read_length_reg[port];
                tail = (tail + 1) & (READ_META_DEPTH - 1);
                ++count;
                if (remaining <= LANE_BYTES) {
                    if (!command_fire) {
                        read_remaining_reg[port]._next = 0;
                        read_active_reg[port]._next = 0;
                    }
                }
                else {
                    read_word_reg[port]._next = read_word_reg[port] + 1;
                    read_remaining_reg[port]._next = remaining - LANE_BYTES;
                }
            }
            meta_head_reg[port]._next = head;
            meta_tail_reg[port]._next = tail;
            meta_count_reg[port]._next = count;
        }

        if (reset) {
            for (port = 0; port < READ_PORTS; ++port) {
                read_active_reg[port].clr();
                read_handle_reg[port].clr();
                read_remaining_reg[port].clr();
                read_length_reg[port].clr();
                read_word_reg[port].clr();
                meta_head_reg[port].clr();
                meta_tail_reg[port].clr();
                meta_count_reg[port].clr();
                for (slot = 0; slot < READ_META_DEPTH; ++slot) {
                    meta_bytes_reg[port][slot].clr();
                    meta_sop_reg[port][slot].clr();
                    meta_eop_reg[port][slot].clr();
                    meta_handle_reg[port][slot].clr();
                    meta_length_reg[port][slot].clr();
                }
            }
        }
    }

    void _strobe_net_clk()
    {
        uint32_t port;
        uint32_t slot;
#ifndef SYNTHESIS
        network._strobe_net_clk();
        descriptor_fifo._strobe_net_clk();
#define SMARTNIC_STROBE_NET_RX_CDC(number) \
        read_command_fifo[number]._strobe_net_clk(); \
        rx_stream_cdc[number]._strobe_net_clk();
        SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_STROBE_NET_RX_CDC)
#undef SMARTNIC_STROBE_NET_RX_CDC
#define SMARTNIC_STROBE_NET_TX_CDC(number) \
        tx_stream_cdc[number]._strobe_net_clk();
        SMARTNIC_FOR_EACH_TX_STREAM(SMARTNIC_STROBE_NET_TX_CDC)
#undef SMARTNIC_STROBE_NET_TX_CDC
#endif
        for (port = 0; port < READ_PORTS; ++port) {
            read_active_reg[port].strobe();
            read_handle_reg[port].strobe();
            read_length_reg[port].strobe();
            read_remaining_reg[port].strobe();
            read_word_reg[port].strobe();
            meta_head_reg[port].strobe();
            meta_tail_reg[port].strobe();
            meta_count_reg[port].strobe();
            for (slot = 0; slot < READ_META_DEPTH; ++slot) {
                meta_bytes_reg[port][slot].strobe();
                meta_sop_reg[port][slot].strobe();
                meta_eop_reg[port][slot].strobe();
                meta_handle_reg[port][slot].strobe();
                meta_length_reg[port][slot].strobe();
            }
        }
    }

    void _work_l2_clk(bool reset)
    {
        uint32_t port;
#ifndef SYNTHESIS
        descriptor_fifo._work_l2_clk(reset);
        network._work_l2_clk(reset);
#define SMARTNIC_WORK_L2_RX(number) \
        read_command_fifo[number]._work_l2_clk(reset); \
        rx_stream_cdc[number]._work_l2_clk(reset);
        SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_WORK_L2_RX)
#undef SMARTNIC_WORK_L2_RX
#define SMARTNIC_WORK_L2_TX(number) \
        tx_stream_cdc[number]._work_l2_clk(reset);
        SMARTNIC_FOR_EACH_TX_STREAM(SMARTNIC_WORK_L2_TX)
#undef SMARTNIC_WORK_L2_TX
#endif

        if (descriptor_fifo.read_valid_out()
            && !(bool)descriptor_valid_reg) {
            descriptor_hold_reg._next = descriptor_fifo.read_data_out();
            descriptor_word_reg._next = 0;
            descriptor_valid_reg._next = 1;
        }
        if ((bool)descriptor_valid_reg && l2_descriptor_ready_in()) {
            if ((uint32_t)descriptor_word_reg == 4) {
                descriptor_valid_reg._next = 0;
                descriptor_word_reg._next = 0;
            }
            else {
                descriptor_word_reg._next = descriptor_word_reg + 1;
            }
        }
        if (reset) {
            descriptor_hold_reg.clr();
            descriptor_word_reg.clr();
            descriptor_valid_reg.clr();
        }
    }

    void _strobe_l2_clk()
    {
        uint32_t port;
#ifndef SYNTHESIS
        descriptor_fifo._strobe_l2_clk();
        network._strobe_l2_clk();
#define SMARTNIC_STROBE_L2_RX(number) \
        read_command_fifo[number]._strobe_l2_clk(); \
        rx_stream_cdc[number]._strobe_l2_clk();
        SMARTNIC_FOR_EACH_RX_PORT(SMARTNIC_STROBE_L2_RX)
#undef SMARTNIC_STROBE_L2_RX
#define SMARTNIC_STROBE_L2_TX(number) \
        tx_stream_cdc[number]._strobe_l2_clk();
        SMARTNIC_FOR_EACH_TX_STREAM(SMARTNIC_STROBE_L2_TX)
#undef SMARTNIC_STROBE_L2_TX
#endif
        descriptor_hold_reg.strobe();
        descriptor_word_reg.strobe();
        descriptor_valid_reg.strobe();
    }
};

#ifdef SYNTHESIS
template class SmartNIC<160, RX_RAM_BANK_DEPTH, 64, 1024>;
#endif

#undef SMARTNIC_FOR_EACH_RX_PORT
#undef SMARTNIC_FOR_EACH_TX_STREAM
#undef SMARTNIC_TWO_CLOCKS
