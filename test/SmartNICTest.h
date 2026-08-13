#pragma once

// Shared full-SoC simulation harness. It composes the Network SmartNIC root,
// eight Tribe processing clusters, the System queues/controller/MasterDMA,
// external CPU DDR models, a wire-rate Ethernet source, and an Avalon host.

#include "../Config.h"
#include "../rtl/SmartNIC.h"
#include "../rtl/processing/Processing.h"
#include "../rtl/system/System.h"
#include "../cpphdl/tribe_cpu/common/Axi4Ram.h"
#include "TrafficGenerator.h"
#include "AvalonHost.h"

using namespace cpphdl;

template<size_t LANE_WIDTH = NET_LANE_WIDTH, size_t CPU_COUNT = CPUS_USED,
    size_t TRAFFIC_DEPTH = 1024, size_t CPU_RAM_WORDS = 4096,
    size_t HOST_MEMORY_BYTES = 4 * 1024 * 1024,
    size_t RX_RAM_DEPTH = RX_RAM_BANK_DEPTH>
class SmartNICTest : public Module
{
public:
    static constexpr size_t STREAMS = 8;
    static constexpr size_t L2_WIDTH = 256;
    static constexpr size_t L2_BYTES = 32;
    static constexpr size_t NET_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t NET_BYTES = NET_BITS / 8;
    static constexpr size_t HANDLE_BITS = clog2(RX_RAM_DEPTH * 2) + 3;
    static constexpr size_t FRAME_LENGTH_BITS = 14;

    static_assert(CPU_COUNT >= 1 && CPU_COUNT <= STREAMS,
        "capture harness supports one through eight Tribe clusters");

    SmartNIC<LANE_WIDTH, RX_RAM_DEPTH, 64, 1024> smartnic;
    Processing<CPU_COUNT, HANDLE_BITS, FRAME_LENGTH_BITS> processing;
    System<8, 256> system;
    TrafficGenerator<LANE_WIDTH, TRAFFIC_DEPTH> traffic;
    AvalonHost<HOST_MEMORY_BYTES> host;
    Axi4Ram<CPU::EXTERNAL_ADDR_WIDTH, CPU::ID_WIDTH,
        CPU::DATA_WIDTH, CPU_RAM_WORDS> cpu_memory[CPU_COUNT];

    // Traffic image loader and launch interface.
    _PORT(bool) traffic_load_valid_in;
    _PORT(logic<NET_BITS>) traffic_load_data_in;
    _PORT(logic<NET_BYTES>) traffic_load_keep_in;
    _PORT(logic<NET_BYTES>) traffic_load_sop_in;
    _PORT(logic<NET_BYTES>) traffic_load_eop_in;
    _PORT(bool) traffic_load_ready_out;
    _PORT(bool) traffic_start_in;
    _PORT(bool) traffic_clear_in;
    _PORT(u<16>) traffic_repeat_count_in;
    _PORT(bool) traffic_done_out;
    _PORT(u32) traffic_emitted_beats_out;
    _PORT(u32) traffic_backpressure_cycles_out;

    // Host-driver Avalon master controls System registers and descriptor rings.
    _PORT(bool) host_read_in;
    _PORT(bool) host_write_in;
    _PORT(u32) host_address_in;
    _PORT(logic<HOST_DATA_WIDTH>) host_writedata_in;
    _PORT(logic<HOST_DATA_WIDTH / 8>) host_byteenable_in;
    _PORT(bool) host_waitrequest_out;
    _PORT(logic<HOST_DATA_WIDTH>) host_readdata_out;
    _PORT(bool) host_readdatavalid_out;

    _PORT(bool) protocol_error_out;
    _PORT(bool) storage_full_out;

private:
    logic<STREAMS> smartnic_rx_ready_comb;
    logic<STREAMS> smartnic_tx_valid_comb;
    logic<STREAMS * L2_WIDTH> smartnic_tx_data_comb;
    logic<STREAMS * L2_BYTES> smartnic_tx_keep_comb;
    logic<STREAMS> smartnic_tx_sop_comb;
    logic<STREAMS> smartnic_tx_eop_comb;
    logic<STREAMS> system_rx_valid_comb;
    logic<STREAMS * L2_WIDTH> system_rx_data_comb;
    logic<STREAMS * L2_BYTES> system_rx_keep_comb;
    logic<STREAMS> system_rx_sop_comb;
    logic<STREAMS> system_rx_eop_comb;
    logic<STREAMS> system_tx_ready_comb;
    bool protocol_error_comb;

    logic<STREAMS>& smartnic_rx_ready_comb_func()
    {
        uint32_t index;
        smartnic_rx_ready_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            smartnic_rx_ready_comb[index] = processing.rx_ready_out()[index];
        }
        return smartnic_rx_ready_comb;
    }

    logic<STREAMS>& smartnic_tx_valid_comb_func()
    {
        uint32_t index;
        smartnic_tx_valid_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            smartnic_tx_valid_comb[index] =
                processing.to_network_valid_out()[index];
        }
        return smartnic_tx_valid_comb;
    }

    logic<STREAMS * L2_WIDTH>& smartnic_tx_data_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        smartnic_tx_data_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            for (bit = 0; bit < L2_WIDTH; ++bit) {
                smartnic_tx_data_comb[index * L2_WIDTH + bit] =
                    processing.to_network_data_out()[index * L2_WIDTH + bit];
            }
        }
        return smartnic_tx_data_comb;
    }

    logic<STREAMS * L2_BYTES>& smartnic_tx_keep_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        smartnic_tx_keep_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            for (bit = 0; bit < L2_BYTES; ++bit) {
                smartnic_tx_keep_comb[index * L2_BYTES + bit] =
                    processing.to_network_keep_out()[index * L2_BYTES + bit];
            }
        }
        return smartnic_tx_keep_comb;
    }

    logic<STREAMS>& smartnic_tx_sop_comb_func()
    {
        uint32_t index;
        smartnic_tx_sop_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            smartnic_tx_sop_comb[index] =
                processing.to_network_sop_out()[index];
        }
        return smartnic_tx_sop_comb;
    }

    logic<STREAMS>& smartnic_tx_eop_comb_func()
    {
        uint32_t index;
        smartnic_tx_eop_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            smartnic_tx_eop_comb[index] =
                processing.to_network_eop_out()[index];
        }
        return smartnic_tx_eop_comb;
    }

    logic<STREAMS>& system_rx_valid_comb_func()
    {
        uint32_t index;
        system_rx_valid_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            system_rx_valid_comb[index] = processing.to_system_valid_out()[index];
        }
        return system_rx_valid_comb;
    }

    logic<STREAMS * L2_WIDTH>& system_rx_data_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        system_rx_data_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            for (bit = 0; bit < L2_WIDTH; ++bit) {
                system_rx_data_comb[index * L2_WIDTH + bit] =
                    processing.to_system_data_out()[index * L2_WIDTH + bit];
            }
        }
        return system_rx_data_comb;
    }

    logic<STREAMS * L2_BYTES>& system_rx_keep_comb_func()
    {
        uint32_t index;
        uint32_t bit;
        system_rx_keep_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            for (bit = 0; bit < L2_BYTES; ++bit) {
                system_rx_keep_comb[index * L2_BYTES + bit] =
                    processing.to_system_keep_out()[index * L2_BYTES + bit];
            }
        }
        return system_rx_keep_comb;
    }

    logic<STREAMS>& system_rx_sop_comb_func()
    {
        uint32_t index;
        system_rx_sop_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            system_rx_sop_comb[index] = processing.to_system_sop_out()[index];
        }
        return system_rx_sop_comb;
    }

    logic<STREAMS>& system_rx_eop_comb_func()
    {
        uint32_t index;
        system_rx_eop_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            system_rx_eop_comb[index] = processing.to_system_eop_out()[index];
        }
        return system_rx_eop_comb;
    }

    logic<STREAMS>& system_tx_ready_comb_func()
    {
        uint32_t index;
        system_tx_ready_comb = 0;
        for (index = 0; index < CPU_COUNT; ++index) {
            system_tx_ready_comb[index] = processing.from_system_ready_out()[index];
        }
        return system_tx_ready_comb;
    }

    bool& protocol_error_comb_func()
    {
        uint32_t index;
        protocol_error_comb = smartnic.protocol_error_out()
            || system.protocol_error_out()
            || traffic.protocol_error_out()
            || host.protocol_error_out();
        for (index = 0; index < CPU_COUNT; ++index) {
            protocol_error_comb = protocol_error_comb
                || processing.descriptor_fetcher[index].protocol_error_out()
                || processing.packet_dma[index].protocol_error_out();
        }
        return protocol_error_comb;
    }

    void bind_children()
    {
        uint32_t index;
        uint32_t core;

        traffic.load_valid_in = traffic_load_valid_in;
        traffic.load_data_in = traffic_load_data_in;
        traffic.load_keep_in = traffic_load_keep_in;
        traffic.load_sop_in = traffic_load_sop_in;
        traffic.load_eop_in = traffic_load_eop_in;
        traffic.start_in = traffic_start_in;
        traffic.clear_in = traffic_clear_in;
        traffic.repeat_count_in = traffic_repeat_count_in;
        traffic.ready_in = smartnic.net_rx_ready_out;

        smartnic.net_rx_valid_in = traffic.valid_out;
        smartnic.net_rx_data_in = traffic.data_out;
        smartnic.net_rx_keep_in = traffic.keep_out;
        smartnic.net_rx_sop_in = traffic.sop_out;
        smartnic.net_rx_eop_in = traffic.eop_out;
        smartnic.net_rx_raw_in = _ASSIGN(false);
        smartnic.net_tx_ready_in = _ASSIGN(true);

        processing.descriptor_valid_in = smartnic.l2_descriptor_valid_out;
        processing.descriptor_data_in = smartnic.l2_descriptor_data_out;
        processing.descriptor_word_in = smartnic.l2_descriptor_word_out;
        processing.descriptor_sop_in = smartnic.l2_descriptor_sop_out;
        processing.descriptor_eop_in = smartnic.l2_descriptor_eop_out;
        smartnic.l2_descriptor_ready_in = processing.descriptor_ready_out;

        smartnic.l2_rx_read_valid_in = _ASSIGN(
            (logic<STREAMS>)processing.rx_read_valid_out());
        smartnic.l2_rx_read_handle_in = _ASSIGN(
            (logic<STREAMS * HANDLE_BITS>)processing.rx_read_handle_out());
        smartnic.l2_rx_read_length_in = _ASSIGN(
            (logic<STREAMS * FRAME_LENGTH_BITS>)processing.rx_read_length_out());
        processing.rx_read_ready_in = _ASSIGN(
            (logic<CPU_COUNT>)smartnic.l2_rx_read_ready_out().bits(
                CPU_COUNT - 1, 0));
        processing.rx_valid_in = _ASSIGN(
            (logic<CPU_COUNT>)smartnic.l2_rx_valid_out().bits(CPU_COUNT - 1, 0));
        processing.rx_data_in = _ASSIGN(
            (logic<CPU_COUNT * L2_WIDTH>)smartnic.l2_rx_data_out().bits(
                CPU_COUNT * L2_WIDTH - 1, 0));
        processing.rx_keep_in = _ASSIGN(
            (logic<CPU_COUNT * L2_BYTES>)smartnic.l2_rx_keep_out().bits(
                CPU_COUNT * L2_BYTES - 1, 0));
        processing.rx_sop_in = _ASSIGN(
            (logic<CPU_COUNT>)smartnic.l2_rx_sop_out().bits(CPU_COUNT - 1, 0));
        processing.rx_eop_in = _ASSIGN(
            (logic<CPU_COUNT>)smartnic.l2_rx_eop_out().bits(CPU_COUNT - 1, 0));
        smartnic.l2_rx_ready_in = _ASSIGN_COMB(smartnic_rx_ready_comb_func());

        smartnic.l2_tx_valid_in = _ASSIGN_COMB(smartnic_tx_valid_comb_func());
        smartnic.l2_tx_data_in = _ASSIGN_COMB(smartnic_tx_data_comb_func());
        smartnic.l2_tx_keep_in = _ASSIGN_COMB(smartnic_tx_keep_comb_func());
        smartnic.l2_tx_sop_in = _ASSIGN_COMB(smartnic_tx_sop_comb_func());
        smartnic.l2_tx_eop_in = _ASSIGN_COMB(smartnic_tx_eop_comb_func());
        processing.to_network_ready_in = _ASSIGN(
            (logic<CPU_COUNT>)smartnic.l2_tx_ready_out().bits(CPU_COUNT - 1, 0));

        system.l2_rx_valid_in = _ASSIGN_COMB(system_rx_valid_comb_func());
        system.l2_rx_data_in = _ASSIGN_COMB(system_rx_data_comb_func());
        system.l2_rx_keep_in = _ASSIGN_COMB(system_rx_keep_comb_func());
        system.l2_rx_sop_in = _ASSIGN_COMB(system_rx_sop_comb_func());
        system.l2_rx_eop_in = _ASSIGN_COMB(system_rx_eop_comb_func());
        processing.to_system_ready_in = _ASSIGN(
            (logic<CPU_COUNT>)system.l2_rx_ready_out().bits(CPU_COUNT - 1, 0));
        processing.from_system_valid_in = _ASSIGN(
            (logic<CPU_COUNT>)system.l2_tx_valid_out().bits(CPU_COUNT - 1, 0));
        processing.from_system_data_in = _ASSIGN(
            (logic<CPU_COUNT * L2_WIDTH>)system.l2_tx_data_out().bits(
                CPU_COUNT * L2_WIDTH - 1, 0));
        processing.from_system_keep_in = _ASSIGN(
            (logic<CPU_COUNT * L2_BYTES>)system.l2_tx_keep_out().bits(
                CPU_COUNT * L2_BYTES - 1, 0));
        processing.from_system_sop_in = _ASSIGN(
            (logic<CPU_COUNT>)system.l2_tx_sop_out().bits(CPU_COUNT - 1, 0));
        processing.from_system_eop_in = _ASSIGN(
            (logic<CPU_COUNT>)system.l2_tx_eop_out().bits(CPU_COUNT - 1, 0));
        system.l2_tx_ready_in = _ASSIGN_COMB(system_tx_ready_comb_func());

        host.driver_read_in = host_read_in;
        host.driver_write_in = host_write_in;
        host.driver_address_in = host_address_in;
        host.driver_writedata_in = host_writedata_in;
        host.driver_byteenable_in = host_byteenable_in;

        system.host_control.address_in = host.control_out.address_in;
        system.host_control.read_in = host.control_out.read_in;
        system.host_control.write_in = host.control_out.write_in;
        system.host_control.writedata_in = host.control_out.writedata_in;
        system.host_control.byteenable_in = host.control_out.byteenable_in;
        host.control_out.waitrequest_out = system.host_control.waitrequest_out;
        host.control_out.readdata_out = system.host_control.readdata_out;
        host.control_out.readdatavalid_out = system.host_control.readdatavalid_out;

        host.dma.address_in = system.host_dma_out.address_in;
        host.dma.read_in = system.host_dma_out.read_in;
        host.dma.write_in = system.host_dma_out.write_in;
        host.dma.writedata_in = system.host_dma_out.writedata_in;
        host.dma.byteenable_in = system.host_dma_out.byteenable_in;
        system.host_dma_out.waitrequest_out = host.dma.waitrequest_out;
        system.host_dma_out.readdata_out = host.dma.readdata_out;
        system.host_dma_out.readdatavalid_out = host.dma.readdatavalid_out;

        for (index = 0; index < CPU_COUNT; ++index) {
            AXI4_TARGET_IF_DRIVER_FROM_MASTER(cpu_memory[index].axi_in,
                processing.ddr[index]);
            AXI4_MASTER_RESPONDER_FROM_TARGET(processing.ddr[index],
                cpu_memory[index].axi_in);
            cpu_memory[index].debugen_in = false;
            processing.cache_invalidate_in[index] = _ASSIGN(false);
            for (core = 0; core < CPU::CORES; ++core) {
                processing.software_irq_in[index * CPU::CORES + core] =
                    _ASSIGN(false);
                processing.timer_irq_in[index * CPU::CORES + core] =
                    _ASSIGN(false);
                processing.external_irq_in[index * CPU::CORES + core] =
                    _ASSIGN(false);
            }
        }
    }

public:
    void _assign()
    {
        uint32_t index;
        bind_children();
        traffic.__inst_name = __inst_name + "/traffic";
        smartnic.__inst_name = __inst_name + "/smartnic";
        processing.__inst_name = __inst_name + "/processing";
        system.__inst_name = __inst_name + "/system";
        host.__inst_name = __inst_name + "/host";
        traffic._assign();
        smartnic._assign();
        processing._assign();
        system._assign();
        host._assign();
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu_memory[index].__inst_name = __inst_name + "/cpu_memory"
                + std::to_string(index);
            cpu_memory[index]._assign();
        }
        // Several hierarchy links consume ports assigned inside child
        // _assign methods. Re-elaborate once after the first bottom-up pass,
        // then bind the top-level links to the finalized child ports.
        bind_children();
        traffic._assign();
        smartnic._assign();
        processing._assign();
        system._assign();
        host._assign();
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu_memory[index]._assign();
        }
        bind_children();

        traffic_load_ready_out = traffic.load_ready_out;
        traffic_done_out = traffic.done_out;
        traffic_emitted_beats_out = traffic.emitted_beats_out;
        traffic_backpressure_cycles_out = traffic.backpressure_cycles_out;
        host_waitrequest_out = host.driver_waitrequest_out;
        host_readdata_out = host.driver_readdata_out;
        host_readdatavalid_out = host.driver_readdatavalid_out;
        protocol_error_out = _ASSIGN_COMB(protocol_error_comb_func());
        storage_full_out = smartnic.storage_full_out;
    }

    void _work_cpu_clk(bool reset)
    {
        uint32_t index;
        processing._work(reset);
        // Tribe's external AXI ports are on the primary CPU side of its
        // internal L2-to-primary CDC, so attached DDR controllers must sample
        // them on cpu_clk rather than l2_clk.
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu_memory[index]._work(reset);
        }
    }

    void _strobe_cpu_clk()
    {
        uint32_t index;
        processing._strobe();
        for (index = 0; index < CPU_COUNT; ++index) {
            cpu_memory[index]._strobe();
        }
    }

    void _work_l2_clk(bool reset)
    {
        smartnic._work_l2_clk(reset);
        processing._work_l2_clock(reset);
        system._work_l2_clock(reset);
    }

    void _strobe_l2_clk()
    {
        smartnic._strobe_l2_clk();
        processing._strobe_l2_clock();
        system._strobe_l2_clock();
    }

    void _work_net_clk(bool reset)
    {
        traffic._work_net_clk(reset);
        smartnic._work_net_clk(reset);
    }

    void _strobe_net_clk()
    {
        traffic._strobe_net_clk();
        smartnic._strobe_net_clk();
    }

    void _work_system_clk(bool reset)
    {
        system._work(reset);
        host._work_system_clock(reset);
    }

    void _strobe_system_clk()
    {
        system._strobe();
        host._strobe_system_clock();
    }

#ifndef SYNTHESIS
    void load_cpu_byte(size_t cluster, uint32_t address, uint8_t value)
    {
        if (cluster >= CPU_COUNT
            || address >= CPU_RAM_WORDS * CPU::DATA_WIDTH / 8) return;
        cpu_memory[cluster].ram.buffer.data[address / (CPU::DATA_WIDTH / 8)]
            [address % (CPU::DATA_WIDTH / 8)] = value;
    }

    uint8_t host_byte(uint64_t address) const
    {
        return host.read_byte(address);
    }
#endif
};
