#pragma once

// SmartNIC processing cluster: four Tribe RV32 cores, private L1 caches and a
// shared 256-bit L2.  General memory and uncached IOMEM remain external so a
// board-specific DDR controller and processing devices can be attached.

#include "../../Config.h"

#ifndef TRIBE_RAM_BYTES_CONFIG
#define TRIBE_RAM_BYTES_CONFIG CPU_MEMORY
#endif
#ifndef MULTICORE
#define MULTICORE
#endif

// The upstream Tribe defaults target a much larger system.  Load its feature
// header once, then apply the Kintex-7 SmartNIC geometry before Tribe itself is
// parsed.  Four jumbo frames plus cache working reserve fit in the 64 KiB L2;
// the private L1s stay deliberately small. The packet-processing firmware
// does not need atomics, interrupt routing, or address translation.
#include "../../cpphdl/tribe_cpu/Config.h"
#include "../../cpphdl/tribe_cpu/TribeTestModule.h"
#include "../common/Axi4Master.h"

using namespace cpphdl;

class CPU : public Module
{
public:
    static constexpr size_t CORES = 4;
    static constexpr size_t DATA_WIDTH = 256;
    static constexpr size_t ID_WIDTH = 4;
    static constexpr size_t MEMORY_BYTES = CPU_MEMORY;
    static constexpr size_t IO_BYTES = TRIBE_IO_REGION_SIZE;
    static constexpr size_t EXTERNAL_ADDR_WIDTH = L2_CACHE_ADDR_BITS;

    // These product-level aliases document and validate the selected Tribe
    // cache configuration at the point where the CPU enters this SoC.
    static constexpr size_t L1I_BYTES = L1_ICACHE_SIZE;
    static constexpr size_t L1D_BYTES = L1_DCACHE_SIZE;
    static constexpr size_t L2_BYTES = L2_CACHE_SIZE;
    static constexpr size_t CACHE_LINE_BYTES = CACHE_LINE_SIZE;
    static constexpr size_t L1_WAYS = L1_CACHE_ASSOCIATIONS;
    static constexpr size_t L2_WAYS = L2_CACHE_ASSOCIATIONS;

    static_assert(CPUS_PER_L2_CACHE == CORES,
        "SmartNIC CPU requires four Tribe cores per shared L2");
    static_assert(TRIBE_L2_AXI_WIDTH == DATA_WIDTH,
        "SmartNIC processing datapath requires Tribe's 256-bit L2");
    static_assert(MEMORY_BYTES + IO_BYTES == MAX_RAM_SIZE,
        "Tribe address layout must match CPU_MEMORY plus IOMEM");

    TribeTest<CORES> tribe;

    // Coherent, write-allocating ingress used by the packet DMA.
    Axi4If<32, ID_WIDTH, DATA_WIDTH> dma_in;
    // Downstream ports.  IOMEM is uncached in Tribe's L2 region table.
    // Interface member names are neutral because their fields already carry
    // explicit master directions; a second `_out` suffix would be inverted by
    // the CppHDL interface flattener.
    Axi4MasterIf<EXTERNAL_ADDR_WIDTH, ID_WIDTH, DATA_WIDTH> memory;
    Axi4MasterIf<32, ID_WIDTH, DATA_WIDTH> iomem;

    _PORT(u32) reset_pc_in;
    _PORT(u32) boot_hartid_in;
    _PORT(u32) boot_dtb_addr_in;
    _PORT(u<2>) boot_priv_in;
    _PORT(bool) cache_invalidate_in;
    _PORT(bool) software_irq_in[CORES];
    _PORT(bool) timer_irq_in[CORES];
    _PORT(bool) external_irq_in[CORES];

private:
    // Direct type references make the converter import the packages required
    // by TribeTest's remaining performance/debug child ports into CPU.sv.
    TribeSbiDebug debug_sbi_type_dependency;
    TribePerf debug_perf_type_dependency;

public:

    void _assign()
    {
        uint32_t core;
        uint32_t port;

        tribe.reset_pc_in = reset_pc_in;
        tribe.boot_hartid_in = boot_hartid_in;
        tribe.boot_dtb_addr_in = boot_dtb_addr_in;
        tribe.boot_priv_in = boot_priv_in;
        tribe.external_cache_invalidate_in = cache_invalidate_in;
        tribe.memory_base_in = _ASSIGN((uint32_t)0);
        tribe.memory_size_in = _ASSIGN((uint32_t)(MEMORY_BYTES + IO_BYTES));
        tribe.mem_region_size_in[0] = _ASSIGN((uint32_t)MEMORY_BYTES);
        tribe.mem_region_size_in[1] = _ASSIGN((uint32_t)0);
        tribe.mem_region_size_in[2] = _ASSIGN((uint32_t)0);
        tribe.mem_region_size_in[3] = _ASSIGN((uint32_t)IO_BYTES);
        tribe.debugen_in = false;

#if defined(ENABLE_ZICSR) && defined(ENABLE_ISR)
        tribe.time_lo_in = _ASSIGN((uint32_t)0);
        tribe.time_hi_in = _ASSIGN((uint32_t)0);
        for (core = 0; core < CORES; ++core) {
            tribe.clint_msip_per_core_in[core] = software_irq_in[core];
            tribe.clint_mtip_per_core_in[core] = timer_irq_in[core];
            tribe.external_irq_per_core_in[core] = external_irq_in[core];
        }
#endif

        // External coherent port zero belongs to this cluster's PacketDMA.
        AXI4_DRIVER_FROM(tribe.axi_in[0], dma_in);
        AXI4_RESPONDER_FROM(dma_in, tribe.axi_in[0]);
        for (port = 1; port < L2_MEM_PORTS; ++port) {
            tribe.axi_in[port].awvalid_in = _ASSIGN(false);
            tribe.axi_in[port].awaddr_in = _ASSIGN((u<32>)0);
            tribe.axi_in[port].awid_in = _ASSIGN((u<ID_WIDTH>)0);
            tribe.axi_in[port].wvalid_in = _ASSIGN(false);
            tribe.axi_in[port].wdata_in = _ASSIGN((logic<DATA_WIDTH>)0);
            tribe.axi_in[port].wstrb_in = _ASSIGN((logic<DATA_WIDTH / 8>)0);
            tribe.axi_in[port].wlast_in = _ASSIGN(false);
            tribe.axi_in[port].bready_in = _ASSIGN(false);
            tribe.axi_in[port].arvalid_in = _ASSIGN(false);
            tribe.axi_in[port].araddr_in = _ASSIGN((u<32>)0);
            tribe.axi_in[port].arid_in = _ASSIGN((u<ID_WIDTH>)0);
            tribe.axi_in[port].rready_in = _ASSIGN(false);
        }

        AXI4_MASTER_FROM_TARGET_IF(memory, tribe.axi_out[0]);
        AXI4_TARGET_IF_RESPONDER_FROM_MASTER(tribe.axi_out[0], memory);
        iomem.awvalid_out = tribe.axi_out[3].awvalid_in;
        iomem.awaddr_out = _ASSIGN((u<32>)tribe.axi_out[3].awaddr_in());
        iomem.awid_out = tribe.axi_out[3].awid_in;
        iomem.wvalid_out = tribe.axi_out[3].wvalid_in;
        iomem.wdata_out = tribe.axi_out[3].wdata_in;
        iomem.wstrb_out = tribe.axi_out[3].wstrb_in;
        iomem.wlast_out = tribe.axi_out[3].wlast_in;
        iomem.bready_out = tribe.axi_out[3].bready_in;
        iomem.arvalid_out = tribe.axi_out[3].arvalid_in;
        iomem.araddr_out = _ASSIGN((u<32>)tribe.axi_out[3].araddr_in());
        iomem.arid_out = tribe.axi_out[3].arid_in;
        iomem.rready_out = tribe.axi_out[3].rready_in;
        AXI4_TARGET_IF_RESPONDER_FROM_MASTER(tribe.axi_out[3], iomem);

        // Empty middle regions cannot be selected, but their responder inputs
        // are still tied to deterministic values for C++ simulation.
        for (port = 1; port < 3; ++port) {
            tribe.axi_out[port].awready_out = _ASSIGN(true);
            tribe.axi_out[port].wready_out = _ASSIGN(true);
            tribe.axi_out[port].bvalid_out = _ASSIGN(false);
            tribe.axi_out[port].bid_out = _ASSIGN((u<ID_WIDTH>)0);
            tribe.axi_out[port].arready_out = _ASSIGN(true);
            tribe.axi_out[port].rvalid_out = _ASSIGN(false);
            tribe.axi_out[port].rdata_out = _ASSIGN((logic<DATA_WIDTH>)0);
            tribe.axi_out[port].rlast_out = _ASSIGN(false);
            tribe.axi_out[port].rid_out = _ASSIGN((u<ID_WIDTH>)0);
        }

#ifndef SYNTHESIS
        tribe.__inst_name = __inst_name + "/tribe";
#endif
        tribe._assign();

        // Child output ports are populated by TribeTest::_assign().  Bind them
        // after elaborating the child so function_ref copies are never empty
        // in native C++ simulation.
        AXI4_RESPONDER_FROM(dma_in, tribe.axi_in[0]);
        AXI4_MASTER_FROM_TARGET_IF(memory, tribe.axi_out[0]);
        iomem.awvalid_out = tribe.axi_out[3].awvalid_in;
        iomem.awid_out = tribe.axi_out[3].awid_in;
        iomem.wvalid_out = tribe.axi_out[3].wvalid_in;
        iomem.wdata_out = tribe.axi_out[3].wdata_in;
        iomem.wstrb_out = tribe.axi_out[3].wstrb_in;
        iomem.wlast_out = tribe.axi_out[3].wlast_in;
        iomem.bready_out = tribe.axi_out[3].bready_in;
        iomem.arvalid_out = tribe.axi_out[3].arvalid_in;
        iomem.arid_out = tribe.axi_out[3].arid_in;
        iomem.rready_out = tribe.axi_out[3].rready_in;
    }

    // Tribe keeps its core/L1 and L2 clocks explicit.  Processing drives
    // _work at CPU_CLK_MULTIPLIER * L2_CLK_HZ and _work_l2_clock at L2_CLK_HZ.
    void _work(bool reset) { tribe._work(reset); }
    void _work_neg(bool reset) { tribe._work_neg(reset); }
    void _work_l2_clock(bool reset) { tribe._work_l2_clock(reset); }
    void _strobe() { tribe._strobe(); }
    void _strobe_l2_clock() { tribe._strobe_l2_clock(); }
};
