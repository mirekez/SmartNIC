#pragma once

// SmartNIC system level. One processing-to-host RxQueue and one
// host-to-processing TxQueue sit behind explicit 156.25/125 MHz CDC FIFOs.
// A host-programmed controller consumes RX/TX descriptor rings and shares one
// host-memory DMA engine across the queue pairs.

#include "../../Config.h"
#include "Controller.h"
#include "MasterDMA.h"
#include "RxQueue.h"
#include "TxQueue.h"
#include "../common/AsyncFifo.h"

using namespace cpphdl;

template<size_t QUEUES = SYSTEM_QUEUES, size_t QUEUE_DEPTH = 256>
class System : public Module
{
public:
    static constexpr size_t DATA_WIDTH = 256;
    static constexpr size_t DATA_BYTES = 32;
    static constexpr size_t STREAM_BITS = DATA_WIDTH + DATA_BYTES + 2;

    static_assert(QUEUES == 1, "Kintex-7 system contains one RX/TX queue pair");

    // L2-clock Processing boundary.  CPU_SYSTEM writes l2_rx; SYSTEM_CPU reads
    // l2_tx.  CDC is complete before either synchronous System queue.
    _PORT(logic<QUEUES>) l2_rx_valid_in;
    _PORT(logic<QUEUES * DATA_WIDTH>) l2_rx_data_in;
    _PORT(logic<QUEUES * DATA_BYTES>) l2_rx_keep_in;
    _PORT(logic<QUEUES>) l2_rx_sop_in;
    _PORT(logic<QUEUES>) l2_rx_eop_in;
    _PORT(logic<QUEUES>) l2_rx_ready_out;

    _PORT(logic<QUEUES>) l2_tx_valid_out;
    _PORT(logic<QUEUES * DATA_WIDTH>) l2_tx_data_out;
    _PORT(logic<QUEUES * DATA_BYTES>) l2_tx_keep_out;
    _PORT(logic<QUEUES>) l2_tx_sop_out;
    _PORT(logic<QUEUES>) l2_tx_eop_out;
    _PORT(logic<QUEUES>) l2_tx_ready_in;

#if HOST_AXI4
    Axi4If<32, 4, HOST_DATA_WIDTH> host_control;
    Axi4MasterIf<HOST_ADDR_WIDTH, 4, HOST_DATA_WIDTH> host_dma;
#else
    AvalonIf<32, HOST_DATA_WIDTH> host_control;
    AvalonIf<HOST_ADDR_WIDTH, HOST_DATA_WIDTH> host_dma_out;
#endif

    _PORT(logic<QUEUES>) rx_queue_empty_out;
    _PORT(logic<QUEUES>) tx_queue_empty_out;
    _PORT(bool) protocol_error_out;

private:
    Controller<QUEUES, 1024, HOST_DATA_WIDTH> controller;
    MasterDMA<HOST_ADDR_WIDTH, HOST_DATA_WIDTH, 4, 16> master_dma;
    RxQueue<QUEUE_DEPTH> rx_queue[QUEUES];
    TxQueue<QUEUE_DEPTH> tx_queue[QUEUES];
    AsyncFifoL2ToSystem<STREAM_BITS, 16> rx_cdc[QUEUES];
    AsyncFifoSystemToL2<STREAM_BITS, 16> tx_cdc[QUEUES];

    logic<STREAM_BITS> rx_pack_comb[QUEUES];
    logic<QUEUES> l2_rx_ready_comb;
    logic<QUEUES> l2_tx_valid_comb;
    logic<QUEUES * DATA_WIDTH> l2_tx_data_comb;
    logic<QUEUES * DATA_BYTES> l2_tx_keep_comb;
    logic<QUEUES> l2_tx_sop_comb;
    logic<QUEUES> l2_tx_eop_comb;
    logic<QUEUES> rx_empty_comb;
    logic<QUEUES> tx_empty_comb;
    logic<QUEUES> tx_full_comb;
    logic<QUEUES * 16> rx_length_comb;
    logic<QUEUES * 16> rx_count_comb;
    logic<QUEUES * 16> tx_count_comb;
    bool selected_rx_valid_comb;
    logic<256> selected_rx_data_comb;
    logic<32> selected_rx_keep_comb;
    bool selected_rx_sop_comb;
    bool selected_rx_eop_comb;
    bool protocol_error_comb;

    logic<STREAM_BITS> (&rx_pack_comb_func())[QUEUES]
    {
        uint32_t queue;
        uint32_t bit;
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_pack_comb[queue] = 0;
            for (bit = 0; bit < DATA_WIDTH; ++bit) {
                rx_pack_comb[queue][bit] =
                    l2_rx_data_in()[queue * DATA_WIDTH + bit];
            }
            for (bit = 0; bit < DATA_BYTES; ++bit) {
                rx_pack_comb[queue][DATA_WIDTH + bit] =
                    l2_rx_keep_in()[queue * DATA_BYTES + bit];
            }
            rx_pack_comb[queue][DATA_WIDTH + DATA_BYTES] = l2_rx_sop_in()[queue];
            rx_pack_comb[queue][DATA_WIDTH + DATA_BYTES + 1] = l2_rx_eop_in()[queue];
        }
        return rx_pack_comb;
    }

    logic<QUEUES>& l2_rx_ready_comb_func()
    {
        uint32_t queue;
        l2_rx_ready_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            l2_rx_ready_comb[queue] = rx_cdc[queue].write_ready_out();
        }
        return l2_rx_ready_comb;
    }

    logic<QUEUES>& l2_tx_valid_comb_func()
    {
        uint32_t queue;
        l2_tx_valid_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            l2_tx_valid_comb[queue] = tx_cdc[queue].read_valid_out();
        }
        return l2_tx_valid_comb;
    }

    logic<QUEUES * DATA_WIDTH>& l2_tx_data_comb_func()
    {
        uint32_t queue;
        uint32_t bit;
        l2_tx_data_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            for (bit = 0; bit < DATA_WIDTH; ++bit) {
                l2_tx_data_comb[queue * DATA_WIDTH + bit] =
                    tx_cdc[queue].read_data_out()[bit];
            }
        }
        return l2_tx_data_comb;
    }

    logic<QUEUES * DATA_BYTES>& l2_tx_keep_comb_func()
    {
        uint32_t queue;
        uint32_t bit;
        l2_tx_keep_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            for (bit = 0; bit < DATA_BYTES; ++bit) {
                l2_tx_keep_comb[queue * DATA_BYTES + bit] =
                    tx_cdc[queue].read_data_out()[DATA_WIDTH + bit];
            }
        }
        return l2_tx_keep_comb;
    }

    logic<QUEUES>& l2_tx_sop_comb_func()
    {
        uint32_t queue;
        l2_tx_sop_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            l2_tx_sop_comb[queue] =
                tx_cdc[queue].read_data_out()[DATA_WIDTH + DATA_BYTES];
        }
        return l2_tx_sop_comb;
    }

    logic<QUEUES>& l2_tx_eop_comb_func()
    {
        uint32_t queue;
        l2_tx_eop_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            l2_tx_eop_comb[queue] =
                tx_cdc[queue].read_data_out()[DATA_WIDTH + DATA_BYTES + 1];
        }
        return l2_tx_eop_comb;
    }

    logic<QUEUES>& rx_empty_comb_func()
    {
        uint32_t queue;
        rx_empty_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_empty_comb[queue] = rx_queue[queue].empty_out();
        }
        return rx_empty_comb;
    }

    logic<QUEUES>& tx_empty_comb_func()
    {
        uint32_t queue;
        tx_empty_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            tx_empty_comb[queue] = tx_queue[queue].empty_out();
        }
        return tx_empty_comb;
    }

    logic<QUEUES>& tx_full_comb_func()
    {
        uint32_t queue;
        tx_full_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            tx_full_comb[queue] = tx_queue[queue].full_out();
        }
        return tx_full_comb;
    }

    logic<QUEUES * 16>& rx_length_comb_func()
    {
        uint32_t queue;
        uint32_t bit;
        rx_length_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            for (bit = 0; bit < 16; ++bit) {
                rx_length_comb[queue * 16 + bit] =
                    rx_queue[queue].packet_length_out()[bit];
            }
        }
        return rx_length_comb;
    }

    logic<QUEUES * 16>& rx_count_comb_func()
    {
        uint32_t queue;
        uint32_t bit;
        rx_count_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            for (bit = 0; bit < 16; ++bit) {
                if (bit < clog2(QUEUE_DEPTH + 1)) {
                    rx_count_comb[queue * 16 + bit] =
                        rx_queue[queue].packet_count_out()[bit];
                }
            }
        }
        return rx_count_comb;
    }

    logic<QUEUES * 16>& tx_count_comb_func()
    {
        uint32_t queue;
        uint32_t bit;
        tx_count_comb = 0;
        for (queue = 0; queue < QUEUES; ++queue) {
            for (bit = 0; bit < 16; ++bit) {
                if (bit < clog2(QUEUE_DEPTH + 1)) {
                    tx_count_comb[queue * 16 + bit] =
                        tx_queue[queue].packet_count_out()[bit];
                }
            }
        }
        return tx_count_comb;
    }

    bool& protocol_error_comb_func()
    {
        uint32_t queue;
        protocol_error_comb = controller.protocol_error_out()
            || master_dma.protocol_error_out();
        for (queue = 0; queue < QUEUES; ++queue) {
            protocol_error_comb = protocol_error_comb
                || rx_queue[queue].protocol_error_out()
                || tx_queue[queue].protocol_error_out();
        }
        return protocol_error_comb;
    }

    bool& selected_rx_valid_comb_func()
    {
        selected_rx_valid_comb =
            rx_queue[(uint32_t)master_dma.active_queue_out()].read_valid_out();
        return selected_rx_valid_comb;
    }
    logic<256>& selected_rx_data_comb_func()
    {
        selected_rx_data_comb =
            rx_queue[(uint32_t)master_dma.active_queue_out()].read_data_out();
        return selected_rx_data_comb;
    }
    logic<32>& selected_rx_keep_comb_func()
    {
        selected_rx_keep_comb =
            rx_queue[(uint32_t)master_dma.active_queue_out()].read_keep_out();
        return selected_rx_keep_comb;
    }
    bool& selected_rx_sop_comb_func()
    {
        selected_rx_sop_comb =
            rx_queue[(uint32_t)master_dma.active_queue_out()].read_sop_out();
        return selected_rx_sop_comb;
    }
    bool& selected_rx_eop_comb_func()
    {
        selected_rx_eop_comb =
            rx_queue[(uint32_t)master_dma.active_queue_out()].read_eop_out();
        return selected_rx_eop_comb;
    }

public:
    void _assign()
    {
        uint32_t queue;

        master_dma._assign();

        for (queue = 0; queue < QUEUES; ++queue) {
            rx_cdc[queue].write_valid_in = _ASSIGN_INDEXED((queue),
                l2_rx_valid_in()[queue]);
            rx_cdc[queue].write_data_in = _ASSIGN_REG_INDEXED((queue),
                rx_pack_comb_func()[queue]);
            rx_cdc[queue]._assign();

            tx_cdc[queue].read_ready_in = _ASSIGN_INDEXED((queue),
                l2_tx_ready_in()[queue]);
            tx_cdc[queue]._assign();

            rx_queue[queue].write_valid_in = rx_cdc[queue].read_valid_out;
            rx_queue[queue].write_data_in = _ASSIGN_INDEXED((queue),
                (logic<256>)rx_cdc[queue].read_data_out().bits(255, 0));
            rx_queue[queue].write_keep_in = _ASSIGN_INDEXED((queue),
                (logic<32>)rx_cdc[queue].read_data_out().bits(287, 256));
            rx_queue[queue].write_sop_in = _ASSIGN_INDEXED((queue),
                rx_cdc[queue].read_data_out()[288]);
            rx_queue[queue].write_eop_in = _ASSIGN_INDEXED((queue),
                rx_cdc[queue].read_data_out()[289]);
            rx_queue[queue].read_ready_in = _ASSIGN_INDEXED((queue),
                master_dma.queue_input_ready_out()
                    && (uint32_t)master_dma.active_queue_out() == queue);
            rx_queue[queue].clear_in = _ASSIGN(false);
#ifndef SYNTHESIS
            rx_queue[queue].__inst_name = __inst_name + "/rx_queue"
                + std::to_string(queue);
#endif
            rx_queue[queue]._assign();
            rx_cdc[queue].read_ready_in = rx_queue[queue].write_ready_out;

            tx_queue[queue].write_valid_in = _ASSIGN_INDEXED((queue),
                master_dma.queue_output_valid_out()
                    && (uint32_t)master_dma.active_queue_out() == queue);
            tx_queue[queue].write_data_in = master_dma.queue_output_data_out;
            tx_queue[queue].write_keep_in = master_dma.queue_output_keep_out;
            tx_queue[queue].write_sop_in = master_dma.queue_output_sop_out;
            tx_queue[queue].write_eop_in = master_dma.queue_output_eop_out;
            tx_queue[queue].read_ready_in = tx_cdc[queue].write_ready_out;
            tx_queue[queue].clear_in = _ASSIGN(false);
#ifndef SYNTHESIS
            tx_queue[queue].__inst_name = __inst_name + "/tx_queue"
                + std::to_string(queue);
#endif
            tx_queue[queue]._assign();
            tx_cdc[queue].write_valid_in = tx_queue[queue].read_valid_out;
            tx_cdc[queue].write_data_in = _ASSIGN_INDEXED((queue), cat(
                (u<1>)tx_queue[queue].read_eop_out(),
                (u<1>)tx_queue[queue].read_sop_out(),
                tx_queue[queue].read_keep_out(), tx_queue[queue].read_data_out()));
        }

        controller.rx_empty_in = _ASSIGN_COMB(rx_empty_comb_func());
        controller.rx_packet_length_in = _ASSIGN_COMB(rx_length_comb_func());
        controller.tx_full_in = _ASSIGN_COMB(tx_full_comb_func());
        controller.rx_packet_count_in = _ASSIGN_COMB(rx_count_comb_func());
        controller.tx_packet_count_in = _ASSIGN_COMB(tx_count_comb_func());
        controller.dma_command_ready_in = master_dma.command_ready_out;
        controller.dma_completion_valid_in = master_dma.completion_valid_out;
        controller.dma_completion_queue_in = master_dma.completion_queue_out;
        controller.dma_completion_direction_in = master_dma.completion_direction_out;
#ifndef SYNTHESIS
        controller.__inst_name = __inst_name + "/controller";
#endif
        controller._assign();

        master_dma.command_valid_in = controller.dma_command_valid_out;
        master_dma.command_direction_in = controller.dma_command_direction_out;
        master_dma.command_queue_in = controller.dma_command_queue_out;
        master_dma.command_address_in = controller.dma_command_address_out;
        master_dma.command_length_in = controller.dma_command_length_out;
        master_dma.command_sop_in = controller.dma_command_sop_out;
        master_dma.command_eop_in = controller.dma_command_eop_out;
        master_dma.queue_input_valid_in = _ASSIGN_COMB(selected_rx_valid_comb_func());
        master_dma.queue_input_data_in = _ASSIGN_COMB(selected_rx_data_comb_func());
        master_dma.queue_input_keep_in = _ASSIGN_COMB(selected_rx_keep_comb_func());
        master_dma.queue_input_sop_in = _ASSIGN_COMB(selected_rx_sop_comb_func());
        master_dma.queue_input_eop_in = _ASSIGN_COMB(selected_rx_eop_comb_func());
        master_dma.queue_output_ready_in = _ASSIGN(
            tx_queue[(uint32_t)master_dma.active_queue_out()].write_ready_out());

#if HOST_AXI4
        AXI4_DRIVER_FROM(controller.host_control, host_control);
        AXI4_RESPONDER_FROM(host_control, controller.host_control);
        AXI4_MASTER_FROM_MASTER(host_dma, master_dma.host);
        AXI4_MASTER_RESPONDER_FROM_MASTER(master_dma.host, host_dma);
#else
        controller.host_control.address_in = host_control.address_in;
        controller.host_control.read_in = host_control.read_in;
        controller.host_control.write_in = host_control.write_in;
        controller.host_control.writedata_in = host_control.writedata_in;
        controller.host_control.byteenable_in = host_control.byteenable_in;
        host_control.waitrequest_out = controller.host_control.waitrequest_out;
        host_control.readdata_out = controller.host_control.readdata_out;
        host_control.readdatavalid_out = controller.host_control.readdatavalid_out;
        host_dma_out.address_in = master_dma.host_out.address_in;
        host_dma_out.read_in = master_dma.host_out.read_in;
        host_dma_out.write_in = master_dma.host_out.write_in;
        host_dma_out.writedata_in = master_dma.host_out.writedata_in;
        host_dma_out.byteenable_in = master_dma.host_out.byteenable_in;
        master_dma.host_out.waitrequest_out = host_dma_out.waitrequest_out;
        master_dma.host_out.readdata_out = host_dma_out.readdata_out;
        master_dma.host_out.readdatavalid_out = host_dma_out.readdatavalid_out;
#endif

        l2_rx_ready_out = _ASSIGN_COMB(l2_rx_ready_comb_func());
        l2_tx_valid_out = _ASSIGN_COMB(l2_tx_valid_comb_func());
        l2_tx_data_out = _ASSIGN_COMB(l2_tx_data_comb_func());
        l2_tx_keep_out = _ASSIGN_COMB(l2_tx_keep_comb_func());
        l2_tx_sop_out = _ASSIGN_COMB(l2_tx_sop_comb_func());
        l2_tx_eop_out = _ASSIGN_COMB(l2_tx_eop_comb_func());
        rx_queue_empty_out = _ASSIGN_COMB(rx_empty_comb_func());
        tx_queue_empty_out = _ASSIGN_COMB(tx_empty_comb_func());
        protocol_error_out = _ASSIGN_COMB(protocol_error_comb_func());
    }

    void _work_system_clock(bool reset)
    {
        uint32_t queue;
        master_dma._work(reset);
        controller._work(reset);
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_queue[queue]._work(reset);
            tx_queue[queue]._work(reset);
            rx_cdc[queue]._work_system_clock(reset);
            tx_cdc[queue]._work_system_clock(reset);
        }
    }

    void _work(bool reset)
    {
        uint32_t queue;
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_cdc[queue]._work_l2_clock(reset);
            tx_cdc[queue]._work_l2_clock(reset);
        }
    }

    void _strobe_system_clock()
    {
        uint32_t queue;
        master_dma._strobe();
        controller._strobe();
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_queue[queue]._strobe();
            tx_queue[queue]._strobe();
            rx_cdc[queue]._strobe_system_clock();
            tx_cdc[queue]._strobe_system_clock();
        }
    }

    void _strobe()
    {
        uint32_t queue;
        for (queue = 0; queue < QUEUES; ++queue) {
            rx_cdc[queue]._strobe_l2_clock();
            tx_cdc[queue]._strobe_l2_clock();
        }
    }
};

template class System<SYSTEM_QUEUES, 256>;
