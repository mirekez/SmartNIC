#pragma once

// Processing level.  Complete descriptors are distributed round-robin to
// per-cluster prefetch queues.  Each four-core Tribe cluster owns one coherent
// PacketDMA and one independent RxRAM read channel.  Stream CDC FIFOs isolate
// the L2/network clock from the faster Tribe core/MMIO clock.

#include "../../Config.h"
#include "CPU.h"
#include "DescriptorFetcher.h"
#include "PacketDMA.h"
#include "../common/AsyncFifo.h"
#include "../../cpphdl/tribe_cpu/common/Axi4RegionMux.h"

using namespace cpphdl;

template<size_t CPU_COUNT = CPUS_USED,
    size_t HANDLE_BITS = clog2(RX_RAM_BANK_DEPTH * 2) + 3,
    size_t FRAME_LENGTH_BITS = 14>
class Processing : public Module
{
public:
    static constexpr size_t DESCRIPTOR_CDC_BITS = 256 + 3 + 1 + 1;
    static constexpr size_t READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    static constexpr size_t RX_STREAM_BITS = 256 + 32 + 1 + 1;
    static constexpr size_t DMA_LINE_BITS = 32 + 256 + 32 + 1;
    static constexpr size_t TARGET_BITS = CPU_COUNT <= 1 ? 1 : clog2(CPU_COUNT);
    static constexpr uint32_t FETCHER_BASE = 0x0000;
    static constexpr uint32_t FETCHER_SIZE = 0x1000;
    static constexpr uint32_t DMA_BASE = 0x1000;
    static constexpr uint32_t DMA_SIZE = 0x1000;

    static_assert(CPU_COUNT >= 1 && CPU_COUNT <= 8,
        "CPUS_USED must select between one and eight Tribe clusters");

    CPU cpu[CPU_COUNT];
    DescriptorFetcher<4, 32, 4, 256, HANDLE_BITS>
        descriptor_fetcher[CPU_COUNT];
    PacketDMA<HANDLE_BITS, FRAME_LENGTH_BITS> packet_dma[CPU_COUNT];

    // Aggregate descriptor stream from SmartNIC's L2-side CDC boundary.
    _PORT(bool) descriptor_valid_in;
    _PORT(logic<256>) descriptor_data_in;
    _PORT(u<3>) descriptor_word_in;
    _PORT(bool) descriptor_sop_in;
    _PORT(bool) descriptor_eop_in;
    _PORT(bool) descriptor_ready_out;

    // One independent SmartNIC RxRAM read channel per Tribe cluster.
    _PORT(logic<CPU_COUNT>) rx_read_valid_out;
    _PORT(logic<CPU_COUNT * HANDLE_BITS>) rx_read_handle_out;
    _PORT(logic<CPU_COUNT * FRAME_LENGTH_BITS>) rx_read_length_out;
    _PORT(logic<CPU_COUNT>) rx_read_ready_in;
    _PORT(logic<CPU_COUNT>) rx_valid_in;
    _PORT(logic<CPU_COUNT * 256>) rx_data_in;
    _PORT(logic<CPU_COUNT * 32>) rx_keep_in;
    _PORT(logic<CPU_COUNT>) rx_sop_in;
    _PORT(logic<CPU_COUNT>) rx_eop_in;
    _PORT(logic<CPU_COUNT>) rx_ready_out;

    // PacketDMA streams at the L2-clock boundary.  The System level adds the
    // final L2-to-host-clock CDC before its eight RxQueue/TxQueue instances.
    _PORT(logic<CPU_COUNT>) to_system_valid_out;
    _PORT(logic<CPU_COUNT * 256>) to_system_data_out;
    _PORT(logic<CPU_COUNT * 32>) to_system_keep_out;
    _PORT(logic<CPU_COUNT>) to_system_sop_out;
    _PORT(logic<CPU_COUNT>) to_system_eop_out;
    _PORT(logic<CPU_COUNT>) to_system_ready_in;
    _PORT(logic<CPU_COUNT>) from_system_valid_in;
    _PORT(logic<CPU_COUNT * 256>) from_system_data_in;
    _PORT(logic<CPU_COUNT * 32>) from_system_keep_in;
    _PORT(logic<CPU_COUNT>) from_system_sop_in;
    _PORT(logic<CPU_COUNT>) from_system_eop_in;
    _PORT(logic<CPU_COUNT>) from_system_ready_out;

    // CPU-to-network packet streams feed the matching SmartNIC L2 TxFIFO CDC.
    _PORT(logic<CPU_COUNT>) to_network_valid_out;
    _PORT(logic<CPU_COUNT * 256>) to_network_data_out;
    _PORT(logic<CPU_COUNT * 32>) to_network_keep_out;
    _PORT(logic<CPU_COUNT>) to_network_sop_out;
    _PORT(logic<CPU_COUNT>) to_network_eop_out;
    _PORT(logic<CPU_COUNT>) to_network_ready_in;

    // One external DDR AXI4 master per Tribe cluster.  CPU_MEMORY defines the
    // addressable region, while the DDR4 controller and storage remain outside
    // Processing.  Keeping the ports independent avoids an implicit bandwidth
    // bottleneck; a system-level DDR interconnect may arbitrate them later.
    Axi4MasterIf<CPU::EXTERNAL_ADDR_WIDTH, CPU::ID_WIDTH,
        CPU::DATA_WIDTH> ddr[CPU_COUNT];

    _PORT(bool) software_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) timer_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) external_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) cache_invalidate_in[CPU_COUNT];

private:
    AsyncFifoL2ToCpu<DESCRIPTOR_CDC_BITS, 16> descriptor_cdc[CPU_COUNT];
    AsyncFifoCpuToL2<READ_COMMAND_BITS, 16> read_command_cdc[CPU_COUNT];
    AsyncFifoL2ToCpu<RX_STREAM_BITS, 16> rx_stream_cdc[CPU_COUNT];
    AsyncFifoCpuToL2<RX_STREAM_BITS, 16> to_system_cdc[CPU_COUNT];
    AsyncFifoL2ToCpu<RX_STREAM_BITS, 16> from_system_cdc[CPU_COUNT];
    AsyncFifoCpuToL2<RX_STREAM_BITS, 16> to_network_cdc[CPU_COUNT];
    AsyncFifoCpuToL2<DMA_LINE_BITS, 16> dma_line_cdc[CPU_COUNT];
    AsyncFifoL2ToCpu<1, 4> dma_commit_cdc[CPU_COUNT];
    Axi4RegionMux<2, 32, 4, 256> iomem_mux[CPU_COUNT];
    reg<u<TARGET_BITS>> descriptor_target_reg;

    logic<DESCRIPTOR_CDC_BITS> descriptor_pack_comb;
    logic<CPU_COUNT> rx_read_valid_comb;
    logic<CPU_COUNT * HANDLE_BITS> rx_read_handle_comb;
    logic<CPU_COUNT * FRAME_LENGTH_BITS> rx_read_length_comb;
    logic<CPU_COUNT> rx_ready_comb;
    logic<RX_STREAM_BITS> rx_stream_pack_comb[CPU_COUNT];
    logic<RX_STREAM_BITS> from_system_pack_comb[CPU_COUNT];
    logic<CPU_COUNT> to_system_valid_comb;
    logic<CPU_COUNT * 256> to_system_data_comb;
    logic<CPU_COUNT * 32> to_system_keep_comb;
    logic<CPU_COUNT> to_system_sop_comb;
    logic<CPU_COUNT> to_system_eop_comb;
    logic<CPU_COUNT> from_system_ready_comb;
    logic<CPU_COUNT> to_network_valid_comb;
    logic<CPU_COUNT * 256> to_network_data_comb;
    logic<CPU_COUNT * 32> to_network_keep_comb;
    logic<CPU_COUNT> to_network_sop_comb;
    logic<CPU_COUNT> to_network_eop_comb;

    logic<DESCRIPTOR_CDC_BITS>& descriptor_pack_comb_func()
    {
        descriptor_pack_comb = 0;
        descriptor_pack_comb.bits(255, 0) = descriptor_data_in();
        descriptor_pack_comb.bits(258, 256) = descriptor_word_in();
        descriptor_pack_comb[259] = descriptor_sop_in();
        descriptor_pack_comb[260] = descriptor_eop_in();
        return descriptor_pack_comb;
    }

    logic<CPU_COUNT>& rx_read_valid_comb_func()
    {
        uint32_t index;
        rx_read_valid_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            rx_read_valid_comb[index] = read_command_cdc[index].read_valid_out();
        }
        return rx_read_valid_comb;
    }

    logic<CPU_COUNT * HANDLE_BITS>& rx_read_handle_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        logic<READ_COMMAND_BITS> command;
        rx_read_handle_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            command = read_command_cdc[index].read_data_out();
            for (bit = 0; bit < HANDLE_BITS; ++bit) {
                rx_read_handle_comb[index * HANDLE_BITS + bit] = command[bit];
            }
        }
        return rx_read_handle_comb;
    }

    logic<CPU_COUNT * FRAME_LENGTH_BITS>& rx_read_length_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        logic<READ_COMMAND_BITS> command;
        rx_read_length_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            command = read_command_cdc[index].read_data_out();
            for (bit = 0; bit < FRAME_LENGTH_BITS; ++bit) {
                rx_read_length_comb[index * FRAME_LENGTH_BITS + bit] =
                    command[HANDLE_BITS + bit];
            }
        }
        return rx_read_length_comb;
    }

    logic<CPU_COUNT>& rx_ready_comb_func()
    {
        uint32_t index;
        rx_ready_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            rx_ready_comb[index] = rx_stream_cdc[index].write_ready_out();
        }
        return rx_ready_comb;
    }

    logic<RX_STREAM_BITS> (&rx_stream_pack_comb_func())[CPU_COUNT]
    {
        uint32_t index;
        uint32_t bit;
        for (index = 0; index < CPU_COUNT; ++index) {
            rx_stream_pack_comb[index] = 0;
            for (bit = 0; bit < 256; ++bit) {
                rx_stream_pack_comb[index][bit] = rx_data_in()[index * 256 + bit];
            }
            for (bit = 0; bit < 32; ++bit) {
                rx_stream_pack_comb[index][256 + bit] =
                    rx_keep_in()[index * 32 + bit];
            }
            rx_stream_pack_comb[index][288] = rx_sop_in()[index];
            rx_stream_pack_comb[index][289] = rx_eop_in()[index];
        }
        return rx_stream_pack_comb;
    }

    logic<RX_STREAM_BITS> (&from_system_pack_comb_func())[CPU_COUNT]
    {
        uint32_t index;
        uint32_t bit;
        for (index = 0; index < CPU_COUNT; ++index) {
            from_system_pack_comb[index] = 0;
            for (bit = 0; bit < 256; ++bit) {
                from_system_pack_comb[index][bit] =
                    from_system_data_in()[index * 256 + bit];
            }
            for (bit = 0; bit < 32; ++bit) {
                from_system_pack_comb[index][256 + bit] =
                    from_system_keep_in()[index * 32 + bit];
            }
            from_system_pack_comb[index][288] = from_system_sop_in()[index];
            from_system_pack_comb[index][289] = from_system_eop_in()[index];
        }
        return from_system_pack_comb;
    }

#define PROCESSING_STREAM_OUTPUT_FUNCTIONS(prefix, fifo_name) \
    logic<CPU_COUNT>& prefix##_valid_comb_func() \
    { \
        uint32_t index; \
        prefix##_valid_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_valid_comb[index] = fifo_name[index].read_valid_out(); \
        return prefix##_valid_comb; \
    } \
    logic<CPU_COUNT * 256>& prefix##_data_comb_func() \
    { \
        uint32_t index; uint32_t bit; \
        prefix##_data_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            for (bit = 0; bit < 256; ++bit) \
                prefix##_data_comb[index * 256 + bit] = \
                    fifo_name[index].read_data_out()[bit]; \
        return prefix##_data_comb; \
    } \
    logic<CPU_COUNT * 32>& prefix##_keep_comb_func() \
    { \
        uint32_t index; uint32_t bit; \
        prefix##_keep_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            for (bit = 0; bit < 32; ++bit) \
                prefix##_keep_comb[index * 32 + bit] = \
                    fifo_name[index].read_data_out()[256 + bit]; \
        return prefix##_keep_comb; \
    } \
    logic<CPU_COUNT>& prefix##_sop_comb_func() \
    { \
        uint32_t index; \
        prefix##_sop_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_sop_comb[index] = fifo_name[index].read_data_out()[288]; \
        return prefix##_sop_comb; \
    } \
    logic<CPU_COUNT>& prefix##_eop_comb_func() \
    { \
        uint32_t index; \
        prefix##_eop_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_eop_comb[index] = fifo_name[index].read_data_out()[289]; \
        return prefix##_eop_comb; \
    }
    PROCESSING_STREAM_OUTPUT_FUNCTIONS(to_system, to_system_cdc)
    PROCESSING_STREAM_OUTPUT_FUNCTIONS(to_network, to_network_cdc)
#undef PROCESSING_STREAM_OUTPUT_FUNCTIONS

    logic<CPU_COUNT>& from_system_ready_comb_func()
    {
        uint32_t index;
        from_system_ready_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            from_system_ready_comb[index] =
                from_system_cdc[index].write_ready_out();
        }
        return from_system_ready_comb;
    }

public:
    void _assign()
    {
        uint32_t index;
        uint32_t core;

        descriptor_ready_out = _ASSIGN(
            descriptor_cdc[(uint32_t)descriptor_target_reg].write_ready_out());
        rx_read_valid_out = _ASSIGN_COMB(rx_read_valid_comb_func());
        rx_read_handle_out = _ASSIGN_COMB(rx_read_handle_comb_func());
        rx_read_length_out = _ASSIGN_COMB(rx_read_length_comb_func());
        rx_ready_out = _ASSIGN_COMB(rx_ready_comb_func());
        to_system_valid_out = _ASSIGN_COMB(to_system_valid_comb_func());
        to_system_data_out = _ASSIGN_COMB(to_system_data_comb_func());
        to_system_keep_out = _ASSIGN_COMB(to_system_keep_comb_func());
        to_system_sop_out = _ASSIGN_COMB(to_system_sop_comb_func());
        to_system_eop_out = _ASSIGN_COMB(to_system_eop_comb_func());
        from_system_ready_out = _ASSIGN_COMB(from_system_ready_comb_func());
        to_network_valid_out = _ASSIGN_COMB(to_network_valid_comb_func());
        to_network_data_out = _ASSIGN_COMB(to_network_data_comb_func());
        to_network_keep_out = _ASSIGN_COMB(to_network_keep_comb_func());
        to_network_sop_out = _ASSIGN_COMB(to_network_sop_comb_func());
        to_network_eop_out = _ASSIGN_COMB(to_network_eop_comb_func());

        for (index = 0; index < CPU_COUNT; ++index) {
            descriptor_cdc[index].write_valid_in = _ASSIGN_INDEXED((index),
                descriptor_valid_in() && (uint32_t)descriptor_target_reg == index);
            descriptor_cdc[index].write_data_in =
                _ASSIGN_REG_INDEXED((index), descriptor_pack_comb_func());
            descriptor_cdc[index].read_ready_in =
                descriptor_fetcher[index].descriptor_ready_out;
            descriptor_cdc[index]._assign();

            descriptor_fetcher[index].descriptor_valid_in =
                descriptor_cdc[index].read_valid_out;
            descriptor_fetcher[index].descriptor_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)descriptor_cdc[index].read_data_out().bits(255, 0));
            descriptor_fetcher[index].descriptor_word_in = _ASSIGN_INDEXED((index),
                (u<3>)descriptor_cdc[index].read_data_out().bits(258, 256));
            descriptor_fetcher[index].descriptor_sop_in = _ASSIGN_INDEXED((index),
                descriptor_cdc[index].read_data_out()[259]);
            descriptor_fetcher[index].descriptor_eop_in = _ASSIGN_INDEXED((index),
                descriptor_cdc[index].read_data_out()[260]);
            descriptor_fetcher[index].packet_command_ready_in =
                packet_dma[index].descriptor_command_ready_out;
            packet_dma[index].descriptor_command_valid_in =
                descriptor_fetcher[index].packet_command_valid_out;
            packet_dma[index].descriptor_command_handle_in =
                descriptor_fetcher[index].packet_command_handle_out;
            packet_dma[index].descriptor_command_length_in =
                descriptor_fetcher[index].packet_command_length_out;
            packet_dma[index].descriptor_command_system_in =
                descriptor_fetcher[index].packet_command_system_out;
            packet_dma[index].descriptor_command_cache_in =
                descriptor_fetcher[index].packet_command_cache_out;
            packet_dma[index].descriptor_command_destination_in =
                descriptor_fetcher[index].packet_command_destination_out;
            descriptor_fetcher[index].packet_cache_completed_in =
                packet_dma[index].cache_completed_count_out;

            // CPU uncached IOMEM is split into descriptor and DMA windows.
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(iomem_mux[index].slave_in,
                cpu[index].iomem);
            AXI4_MASTER_RESPONDER_FROM_TARGET(cpu[index].iomem,
                iomem_mux[index].slave_in);
            iomem_mux[index].region_base_in[0] = _ASSIGN(FETCHER_BASE);
            iomem_mux[index].region_size_in[0] = _ASSIGN(FETCHER_SIZE);
            iomem_mux[index].region_base_in[1] = _ASSIGN(DMA_BASE);
            iomem_mux[index].region_size_in[1] = _ASSIGN(DMA_SIZE);
            AXI4_DRIVER_FROM(descriptor_fetcher[index].mmio,
                iomem_mux[index].masters_out[0]);
            AXI4_RESPONDER_FROM(iomem_mux[index].masters_out[0],
                descriptor_fetcher[index].mmio);
            AXI4_DRIVER_FROM(packet_dma[index].mmio,
                iomem_mux[index].masters_out[1]);
            AXI4_RESPONDER_FROM(iomem_mux[index].masters_out[1],
                packet_dma[index].mmio);

            // Packet DMA occupies Tribe coherent master port zero.
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(cpu[index].dma_in,
                packet_dma[index].l2_dma);
            AXI4_MASTER_RESPONDER_FROM_TARGET(packet_dma[index].l2_dma,
                cpu[index].dma_in);

            // Cache-allocation writes cross from the fast core/MMIO domain to
            // the L2 RAM clock as complete 32-byte lines.  The reverse FIFO
            // carries an EOP commit token so firmware cannot observe a packet
            // before all of its cache lines are installed.
            dma_line_cdc[index].write_valid_in =
                packet_dma[index].l2_line_valid_out;
            dma_line_cdc[index].write_data_in = _ASSIGN_INDEXED((index), cat(
                (u<1>)packet_dma[index].l2_line_eop_out(),
                packet_dma[index].l2_line_keep_out(),
                packet_dma[index].l2_line_data_out(),
                packet_dma[index].l2_line_addr_out()));
            packet_dma[index].l2_line_ready_in =
                dma_line_cdc[index].write_ready_out;
            cpu[index].dma_line_valid_in = _ASSIGN_INDEXED((index),
                dma_line_cdc[index].read_valid_out()
                && (!dma_line_cdc[index].read_data_out()[320]
                    || dma_commit_cdc[index].write_ready_out()));
            cpu[index].dma_line_addr_in = _ASSIGN_INDEXED((index),
                (u32)dma_line_cdc[index].read_data_out().bits(31, 0));
            cpu[index].dma_line_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)dma_line_cdc[index].read_data_out().bits(287, 32));
            cpu[index].dma_line_keep_in = _ASSIGN_INDEXED((index),
                (logic<32>)dma_line_cdc[index].read_data_out().bits(319, 288));
            dma_line_cdc[index].read_ready_in = _ASSIGN_INDEXED((index),
                cpu[index].dma_line_ready_out()
                && (!dma_line_cdc[index].read_data_out()[320]
                    || dma_commit_cdc[index].write_ready_out()));
            dma_commit_cdc[index].write_valid_in = _ASSIGN_INDEXED((index),
                dma_line_cdc[index].read_valid_out()
                && dma_line_cdc[index].read_data_out()[320]
                && cpu[index].dma_line_ready_out());
            dma_commit_cdc[index].write_data_in = _ASSIGN((logic<1>)1);
            dma_commit_cdc[index].read_ready_in =
                packet_dma[index].l2_commit_ready_out;
            packet_dma[index].l2_commit_valid_in =
                dma_commit_cdc[index].read_valid_out;
            dma_line_cdc[index]._assign();
            dma_commit_cdc[index]._assign();

            read_command_cdc[index].write_valid_in =
                packet_dma[index].rx_read_valid_out;
            read_command_cdc[index].write_data_in = _ASSIGN_INDEXED((index), cat(
                packet_dma[index].rx_read_length_out(),
                packet_dma[index].rx_read_handle_out()));
            packet_dma[index].rx_read_ready_in =
                read_command_cdc[index].write_ready_out;
            read_command_cdc[index].read_ready_in = _ASSIGN_INDEXED((index),
                rx_read_ready_in()[index]);
            read_command_cdc[index]._assign();

            rx_stream_cdc[index].write_valid_in = _ASSIGN_INDEXED((index),
                rx_valid_in()[index]);
            rx_stream_cdc[index].write_data_in = _ASSIGN_REG_INDEXED((index),
                rx_stream_pack_comb_func()[index]);
            rx_stream_cdc[index].read_ready_in = packet_dma[index].rx_ready_out;
            rx_stream_cdc[index]._assign();
            packet_dma[index].rx_valid_in = rx_stream_cdc[index].read_valid_out;
            packet_dma[index].rx_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)rx_stream_cdc[index].read_data_out().bits(255, 0));
            packet_dma[index].rx_keep_in = _ASSIGN_INDEXED((index),
                (logic<32>)rx_stream_cdc[index].read_data_out().bits(287, 256));
            packet_dma[index].rx_sop_in = _ASSIGN_INDEXED((index),
                rx_stream_cdc[index].read_data_out()[288]);
            packet_dma[index].rx_eop_in = _ASSIGN_INDEXED((index),
                rx_stream_cdc[index].read_data_out()[289]);

            // CPU-domain PacketDMA streams cross back to the rate-matched L2
            // boundary before entering either System or Network CDC logic.
            to_system_cdc[index].write_valid_in =
                packet_dma[index].system_tx_valid_out;
            to_system_cdc[index].write_data_in = _ASSIGN_INDEXED((index), cat(
                (u<1>)packet_dma[index].system_tx_eop_out(),
                (u<1>)packet_dma[index].system_tx_sop_out(),
                packet_dma[index].system_tx_keep_out(),
                packet_dma[index].system_tx_data_out()));
            packet_dma[index].system_tx_ready_in =
                to_system_cdc[index].write_ready_out;
            to_system_cdc[index].read_ready_in = _ASSIGN_INDEXED((index),
                to_system_ready_in()[index]);
            to_system_cdc[index]._assign();

            from_system_cdc[index].write_valid_in = _ASSIGN_INDEXED((index),
                from_system_valid_in()[index]);
            from_system_cdc[index].write_data_in = _ASSIGN_REG_INDEXED((index),
                from_system_pack_comb_func()[index]);
            from_system_cdc[index].read_ready_in =
                packet_dma[index].system_rx_ready_out;
            from_system_cdc[index]._assign();
            packet_dma[index].system_rx_valid_in =
                from_system_cdc[index].read_valid_out;
            packet_dma[index].system_rx_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)from_system_cdc[index].read_data_out().bits(255, 0));
            packet_dma[index].system_rx_keep_in = _ASSIGN_INDEXED((index),
                (logic<32>)from_system_cdc[index].read_data_out().bits(287, 256));
            packet_dma[index].system_rx_sop_in = _ASSIGN_INDEXED((index),
                from_system_cdc[index].read_data_out()[288]);
            packet_dma[index].system_rx_eop_in = _ASSIGN_INDEXED((index),
                from_system_cdc[index].read_data_out()[289]);

            to_network_cdc[index].write_valid_in =
                packet_dma[index].network_tx_valid_out;
            to_network_cdc[index].write_data_in = _ASSIGN_INDEXED((index), cat(
                (u<1>)packet_dma[index].network_tx_eop_out(),
                (u<1>)packet_dma[index].network_tx_sop_out(),
                packet_dma[index].network_tx_keep_out(),
                packet_dma[index].network_tx_data_out()));
            packet_dma[index].network_tx_ready_in =
                to_network_cdc[index].write_ready_out;
            to_network_cdc[index].read_ready_in = _ASSIGN_INDEXED((index),
                to_network_ready_in()[index]);
            to_network_cdc[index]._assign();

            // Preserve every CPU-memory AXI request and response signal at the
            // Processing boundary for attachment to external DDR controllers.
            AXI4_MASTER_FROM_MASTER(ddr[index], cpu[index].memory);
            AXI4_MASTER_RESPONDER_FROM_MASTER(cpu[index].memory, ddr[index]);
            cpu[index].reset_pc_in = _ASSIGN((u32)0);
            cpu[index].boot_hartid_in = _ASSIGN_INDEXED((index),
                (u32)(index * CPU::CORES));
            cpu[index].boot_dtb_addr_in = _ASSIGN((u32)0);
            cpu[index].boot_priv_in = _ASSIGN((u<2>)3);
            cpu[index].cache_invalidate_in = cache_invalidate_in[index];
            for (core = 0; core < CPU::CORES; ++core) {
                cpu[index].software_irq_in[core] =
                    software_irq_in[index * CPU::CORES + core];
                cpu[index].timer_irq_in[core] =
                    timer_irq_in[index * CPU::CORES + core];
                cpu[index].external_irq_in[core] =
                    external_irq_in[index * CPU::CORES + core];
            }

#ifndef SYNTHESIS
            cpu[index].__inst_name = __inst_name + "/cpu" + std::to_string(index);
            descriptor_fetcher[index].__inst_name =
                __inst_name + "/descriptor_fetcher" + std::to_string(index);
            packet_dma[index].__inst_name =
                __inst_name + "/packet_dma" + std::to_string(index);
            iomem_mux[index].__inst_name =
                __inst_name + "/iomem_mux" + std::to_string(index);
#endif
            cpu[index]._assign();
            descriptor_fetcher[index]._assign();
            packet_dma[index]._assign();
            iomem_mux[index]._assign();

            // The child modules above create their output function bindings
            // in _assign(). Refresh peer and boundary links afterward so a
            // single parent elaboration pass cannot retain an empty port from
            // the earlier top-down setup.
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(iomem_mux[index].slave_in,
                cpu[index].iomem);
            AXI4_MASTER_RESPONDER_FROM_TARGET(cpu[index].iomem,
                iomem_mux[index].slave_in);
            AXI4_DRIVER_FROM(descriptor_fetcher[index].mmio,
                iomem_mux[index].masters_out[0]);
            AXI4_RESPONDER_FROM(iomem_mux[index].masters_out[0],
                descriptor_fetcher[index].mmio);
            AXI4_DRIVER_FROM(packet_dma[index].mmio,
                iomem_mux[index].masters_out[1]);
            AXI4_RESPONDER_FROM(iomem_mux[index].masters_out[1],
                packet_dma[index].mmio);
            descriptor_fetcher[index].packet_command_ready_in =
                packet_dma[index].descriptor_command_ready_out;
            packet_dma[index].descriptor_command_valid_in =
                descriptor_fetcher[index].packet_command_valid_out;
            packet_dma[index].descriptor_command_handle_in =
                descriptor_fetcher[index].packet_command_handle_out;
            packet_dma[index].descriptor_command_length_in =
                descriptor_fetcher[index].packet_command_length_out;
            packet_dma[index].descriptor_command_system_in =
                descriptor_fetcher[index].packet_command_system_out;
            packet_dma[index].descriptor_command_cache_in =
                descriptor_fetcher[index].packet_command_cache_out;
            packet_dma[index].descriptor_command_destination_in =
                descriptor_fetcher[index].packet_command_destination_out;
            descriptor_fetcher[index].packet_cache_completed_in =
                packet_dma[index].cache_completed_count_out;
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(cpu[index].dma_in,
                packet_dma[index].l2_dma);
            AXI4_MASTER_RESPONDER_FROM_TARGET(packet_dma[index].l2_dma,
                cpu[index].dma_in);
            dma_line_cdc[index].write_valid_in =
                packet_dma[index].l2_line_valid_out;
            packet_dma[index].l2_line_ready_in =
                dma_line_cdc[index].write_ready_out;
            dma_line_cdc[index].read_ready_in = _ASSIGN_INDEXED((index),
                cpu[index].dma_line_ready_out()
                && (!dma_line_cdc[index].read_data_out()[320]
                    || dma_commit_cdc[index].write_ready_out()));
            dma_commit_cdc[index].read_ready_in =
                packet_dma[index].l2_commit_ready_out;
            packet_dma[index].l2_commit_valid_in =
                dma_commit_cdc[index].read_valid_out;
            AXI4_MASTER_FROM_MASTER(ddr[index], cpu[index].memory);
            AXI4_MASTER_RESPONDER_FROM_MASTER(cpu[index].memory, ddr[index]);
        }
    }

    void _work(bool reset)
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._work(reset);
            descriptor_fetcher[index]._work(reset);
            packet_dma[index]._work(reset);
            iomem_mux[index]._work(reset);
            descriptor_cdc[index]._work_clk(reset);
            read_command_cdc[index]._work_clk(reset);
            rx_stream_cdc[index]._work_clk(reset);
            to_system_cdc[index]._work_clk(reset);
            from_system_cdc[index]._work_clk(reset);
            to_network_cdc[index]._work_clk(reset);
            dma_line_cdc[index]._work_clk(reset);
            dma_commit_cdc[index]._work_clk(reset);
        }
    }

    void _work_neg(bool reset)
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) cpu[index]._work_neg(reset);
    }

    void _work_l2_clock(bool reset)
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._work_l2_clock(reset);
            descriptor_cdc[index]._work_l2_clock(reset);
            read_command_cdc[index]._work_l2_clock(reset);
            rx_stream_cdc[index]._work_l2_clock(reset);
            to_system_cdc[index]._work_l2_clock(reset);
            from_system_cdc[index]._work_l2_clock(reset);
            to_network_cdc[index]._work_l2_clock(reset);
            dma_line_cdc[index]._work_l2_clock(reset);
            dma_commit_cdc[index]._work_l2_clock(reset);
        }
        if (descriptor_valid_in() && descriptor_ready_out()
            && descriptor_eop_in()) {
            descriptor_target_reg._next =
                (uint32_t)descriptor_target_reg + 1 == CPU_COUNT ?
                    (uint32_t)0 : (uint32_t)descriptor_target_reg + 1;
        }
        if (reset) descriptor_target_reg.clr();
    }

    void _strobe()
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._strobe();
            descriptor_fetcher[index]._strobe();
            packet_dma[index]._strobe();
            iomem_mux[index]._strobe();
            descriptor_cdc[index]._strobe_clk();
            read_command_cdc[index]._strobe_clk();
            rx_stream_cdc[index]._strobe_clk();
            to_system_cdc[index]._strobe_clk();
            from_system_cdc[index]._strobe_clk();
            to_network_cdc[index]._strobe_clk();
            dma_line_cdc[index]._strobe_clk();
            dma_commit_cdc[index]._strobe_clk();
        }
    }

    void _strobe_l2_clock()
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._strobe_l2_clock();
            descriptor_cdc[index]._strobe_l2_clock();
            read_command_cdc[index]._strobe_l2_clock();
            rx_stream_cdc[index]._strobe_l2_clock();
            to_system_cdc[index]._strobe_l2_clock();
            from_system_cdc[index]._strobe_l2_clock();
            to_network_cdc[index]._strobe_l2_clock();
            dma_line_cdc[index]._strobe_l2_clock();
            dma_commit_cdc[index]._strobe_l2_clock();
        }
        descriptor_target_reg.strobe();
    }
};

template class Processing<CPUS_USED, clog2(RX_RAM_BANK_DEPTH * 2) + 3, 14>;
