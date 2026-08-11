#pragma once

// Processing level.  Complete descriptors are distributed round-robin to
// per-cluster prefetch queues.  Each four-core Tribe cluster owns one coherent
// PacketDMA and one independent RxRAM read channel.  Stream CDC FIFOs isolate
// the L2/network clock from the faster Tribe core/MMIO clock.

#include "../../Config.h"
#include "CPU.h"
#include "DescriptorFetcher.h"
#include "PacketDMA.h"
#define ASYNC_FIFO_CPU_CLOCK_NAMES 1
#include "../common/AsyncFifo.h"
#undef ASYNC_FIFO_CPU_CLOCK_NAMES
#include "../../cpphdl/tribe_cpu/common/Axi4RegionMux.h"

using namespace cpphdl;

template<size_t CPU_COUNT = CPUS_USED, size_t HANDLE_BITS = 16,
    size_t FRAME_LENGTH_BITS = 14>
class Processing : public Module
{
public:
    static constexpr size_t DESCRIPTOR_CDC_BITS = 256 + 3 + 1 + 1;
    static constexpr size_t READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    static constexpr size_t RX_STREAM_BITS = 256 + 32 + 1 + 1;
    static constexpr size_t TARGET_BITS = CPU_COUNT <= 1 ? 1 : clog2(CPU_COUNT);
    static constexpr uint32_t FETCHER_BASE = 0x0000;
    static constexpr uint32_t FETCHER_SIZE = 0x1000;
    static constexpr uint32_t DMA_BASE = 0x1000;
    static constexpr uint32_t DMA_SIZE = 0x1000;

    static_assert(CPU_COUNT >= 1 && CPU_COUNT <= 8,
        "CPUS_USED must select between one and eight Tribe clusters");

    CPU cpu[CPU_COUNT];
    DescriptorFetcher<> descriptor_fetcher[CPU_COUNT];
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

    // Per-cluster external DDR ports.  CPU_MEMORY defines each address region;
    // the storage implementation belongs to the system/board level.
    Axi4MasterIf<CPU::EXTERNAL_ADDR_WIDTH, 4, 256> memory[CPU_COUNT];

    _PORT(bool) software_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) timer_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) external_irq_in[CPU_COUNT * CPU::CORES];
    _PORT(bool) cache_invalidate_in[CPU_COUNT];

private:
    AsyncFifoL2ToNet<DESCRIPTOR_CDC_BITS, 16> descriptor_cdc[CPU_COUNT];
    AsyncFifoNetToL2<READ_COMMAND_BITS, 16> read_command_cdc[CPU_COUNT];
    AsyncFifoL2ToNet<RX_STREAM_BITS, 16> rx_stream_cdc[CPU_COUNT];
    Axi4RegionMux<2, 32, 4, 256> iomem_mux[CPU_COUNT];
    reg<u<TARGET_BITS>> descriptor_target_reg;

    logic<DESCRIPTOR_CDC_BITS> descriptor_pack_comb;
    logic<CPU_COUNT> rx_read_valid_comb;
    logic<CPU_COUNT * HANDLE_BITS> rx_read_handle_comb;
    logic<CPU_COUNT * FRAME_LENGTH_BITS> rx_read_length_comb;
    logic<CPU_COUNT> rx_ready_comb;
    logic<RX_STREAM_BITS> rx_stream_pack_comb[CPU_COUNT];

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

            AXI4_MASTER_FROM_MASTER(memory[index], cpu[index].memory);
            AXI4_MASTER_RESPONDER_FROM_MASTER(cpu[index].memory,
                memory[index]);
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
        }
        descriptor_target_reg.strobe();
    }
};

template class Processing<CPUS_USED, 16, 14>;
