#pragma once

// Processing level.  Complete descriptors are distributed round-robin to
// the single prefetch queue.  One Tribe cluster owns one coherent
// PacketDMA and one RxRAM read channel. Network, L2, and processing share the
// 156.25 MHz clock, so their former asynchronous FIFOs are unnecessary.

#include "../../Config.h"
#include "CPU.h"
#include "DescriptorFetcher.h"
#include "PacketDMA.h"
#include "../../cpphdl/tribe_cpu/common/Axi4RegionMux.h"

using namespace cpphdl;

template<size_t CPU_COUNT = CPUS_USED, size_t HANDLE_BITS = 16,
    size_t FRAME_LENGTH_BITS = 14>
class Processing : public Module
{
public:
    static constexpr size_t READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    static constexpr size_t RX_STREAM_BITS = 256 + 32 + 1 + 1;
    static constexpr size_t TARGET_BITS = CPU_COUNT <= 1 ? 1 : clog2(CPU_COUNT);
    static constexpr uint32_t FETCHER_BASE = 0x0000;
    static constexpr uint32_t FETCHER_SIZE = 0x1000;
    static constexpr uint32_t DMA_BASE = 0x1000;
    static constexpr uint32_t DMA_SIZE = 0x1000;

    static_assert(CPU_COUNT == 1,
        "Kintex-7 downgrade uses one Tribe cluster");

    CPU cpu[CPU_COUNT];
    DescriptorFetcher<> descriptor_fetcher[CPU_COUNT];
    PacketDMA<HANDLE_BITS, FRAME_LENGTH_BITS> packet_dma[CPU_COUNT];

    // Aggregate descriptor stream from SmartNIC on the shared clock.
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

    // PacketDMA streams at the processing boundary. The System level retains
    // the required processing-to-PCIe-clock CDC around its one queue pair.
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

    // CPU-to-network packet streams feed the matching synchronous converters.
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
    Axi4RegionMux<2, 32, 4, 256> iomem_mux[CPU_COUNT];

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

    logic<CPU_COUNT>& rx_read_valid_comb_func()
    {
        uint32_t index;
        rx_read_valid_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            rx_read_valid_comb[index] = packet_dma[index].rx_read_valid_out();
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
            command = cat(packet_dma[index].rx_read_length_out(),
                packet_dma[index].rx_read_handle_out());
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
            command = cat(packet_dma[index].rx_read_length_out(),
                packet_dma[index].rx_read_handle_out());
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
            rx_ready_comb[index] = packet_dma[index].rx_ready_out();
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

#define PROCESSING_STREAM_OUTPUT_FUNCTIONS(prefix, valid_port, data_port, keep_port, sop_port, eop_port) \
    logic<CPU_COUNT>& prefix##_valid_comb_func() \
    { \
        uint32_t index; \
        prefix##_valid_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_valid_comb[index] = packet_dma[index].valid_port(); \
        return prefix##_valid_comb; \
    } \
    logic<CPU_COUNT * 256>& prefix##_data_comb_func() \
    { \
        uint32_t index; uint32_t bit; \
        prefix##_data_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            for (bit = 0; bit < 256; ++bit) \
                prefix##_data_comb[index * 256 + bit] = \
                    packet_dma[index].data_port()[bit]; \
        return prefix##_data_comb; \
    } \
    logic<CPU_COUNT * 32>& prefix##_keep_comb_func() \
    { \
        uint32_t index; uint32_t bit; \
        prefix##_keep_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            for (bit = 0; bit < 32; ++bit) \
                prefix##_keep_comb[index * 32 + bit] = \
                    packet_dma[index].keep_port()[bit]; \
        return prefix##_keep_comb; \
    } \
    logic<CPU_COUNT>& prefix##_sop_comb_func() \
    { \
        uint32_t index; \
        prefix##_sop_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_sop_comb[index] = packet_dma[index].sop_port(); \
        return prefix##_sop_comb; \
    } \
    logic<CPU_COUNT>& prefix##_eop_comb_func() \
    { \
        uint32_t index; \
        prefix##_eop_comb = 0; \
        for (index = 0; index < CPU_COUNT; ++index) \
            prefix##_eop_comb[index] = packet_dma[index].eop_port(); \
        return prefix##_eop_comb; \
    }
    PROCESSING_STREAM_OUTPUT_FUNCTIONS(to_system, system_tx_valid_out,
        system_tx_data_out, system_tx_keep_out, system_tx_sop_out,
        system_tx_eop_out)
    PROCESSING_STREAM_OUTPUT_FUNCTIONS(to_network, network_tx_valid_out,
        network_tx_data_out, network_tx_keep_out, network_tx_sop_out,
        network_tx_eop_out)
#undef PROCESSING_STREAM_OUTPUT_FUNCTIONS

    logic<CPU_COUNT>& from_system_ready_comb_func()
    {
        uint32_t index;
        from_system_ready_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            from_system_ready_comb[index] =
                packet_dma[index].system_rx_ready_out();
        }
        return from_system_ready_comb;
    }

public:
    void _assign()
    {
        uint32_t index;
        uint32_t core;

        descriptor_ready_out = _ASSIGN(
            descriptor_fetcher[0].descriptor_ready_out());
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
            descriptor_fetcher[index].descriptor_valid_in =
                descriptor_valid_in;
            descriptor_fetcher[index].descriptor_data_in = descriptor_data_in;
            descriptor_fetcher[index].descriptor_word_in = descriptor_word_in;
            descriptor_fetcher[index].descriptor_sop_in = descriptor_sop_in;
            descriptor_fetcher[index].descriptor_eop_in = descriptor_eop_in;

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

            packet_dma[index].rx_read_ready_in =
                _ASSIGN_INDEXED((index), rx_read_ready_in()[index]);
            packet_dma[index].rx_valid_in = _ASSIGN_INDEXED((index),
                rx_valid_in()[index]);
            packet_dma[index].rx_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)rx_data_in().bits(index * 256 + 255,
                    index * 256));
            packet_dma[index].rx_keep_in = _ASSIGN_INDEXED((index),
                (logic<32>)rx_keep_in().bits(index * 32 + 31,
                    index * 32));
            packet_dma[index].rx_sop_in = _ASSIGN_INDEXED((index),
                rx_sop_in()[index]);
            packet_dma[index].rx_eop_in = _ASSIGN_INDEXED((index),
                rx_eop_in()[index]);

            // All processing packet streams are synchronous at 156.25 MHz.
            packet_dma[index].system_tx_ready_in =
                _ASSIGN_INDEXED((index), to_system_ready_in()[index]);
            packet_dma[index].system_rx_valid_in =
                _ASSIGN_INDEXED((index), from_system_valid_in()[index]);
            packet_dma[index].system_rx_data_in = _ASSIGN_INDEXED((index),
                (logic<256>)from_system_data_in().bits(index * 256 + 255,
                    index * 256));
            packet_dma[index].system_rx_keep_in = _ASSIGN_INDEXED((index),
                (logic<32>)from_system_keep_in().bits(index * 32 + 31,
                    index * 32));
            packet_dma[index].system_rx_sop_in = _ASSIGN_INDEXED((index),
                from_system_sop_in()[index]);
            packet_dma[index].system_rx_eop_in = _ASSIGN_INDEXED((index),
                from_system_eop_in()[index]);

            packet_dma[index].network_tx_ready_in =
                _ASSIGN_INDEXED((index), to_network_ready_in()[index]);

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
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(cpu[index].dma_in,
                packet_dma[index].l2_dma);
            AXI4_MASTER_RESPONDER_FROM_TARGET(packet_dma[index].l2_dma,
                cpu[index].dma_in);
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
        }
    }

    void _strobe()
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._strobe();
            descriptor_fetcher[index]._strobe();
            packet_dma[index]._strobe();
            iomem_mux[index]._strobe();
        }
    }

    void _strobe_l2_clock()
    {
        uint32_t index;
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu[index]._strobe_l2_clock();
        }
    }
};

template class Processing<CPUS_USED, 16, 14>;
