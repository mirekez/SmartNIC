`default_nettype none

import Predef_pkg::*;
import Zicsr_pkg::*;
import Rv32ia_pkg::*;
import Rv32im_pkg::*;
import Rv32ic_pkg::*;
import Rv32i_pkg::*;
import Mem_pkg::*;
import Alu_pkg::*;
import Wb_pkg::*;
import Br_pkg::*;
import Sys_pkg::*;
import Trap_pkg::*;
import Amo_pkg::*;
import Csr_pkg::*;
import State_pkg::*;
import L1CacheFsmState_pkg::*;
import L1InputRequestComb_pkg::*;
import L1LookupComb_pkg::*;
import L1RefillLinesComb_pkg::*;
import L1CpuResponseComb_pkg::*;
import L1CachePerf_pkg::*;
import L1RequestGeometryComb_pkg::*;
import L1MemDriver_pkg::*;
import L1RequestState_pkg::*;
import L1RefillState_pkg::*;
import L1HeldResponse_pkg::*;
import TribeCoreDebug_pkg::*;
import TribeMmuDebug_pkg::*;
import TribeCacheDebug_pkg::*;
import TribeWritebackDebug_pkg::*;
import TribeCsrDebug_pkg::*;
import TribeIrqDebug_pkg::*;
import TribeRegsDebug_pkg::*;
import TribeBranchDebug_pkg::*;
import TribeDecodeDebug_pkg::*;
import TribeSbiDebug_pkg::*;
import TribePerf_pkg::*;
import Axi4WriteAddressReady_pkg::*;
import Axi4WriteDataReady_pkg::*;
import Axi4WriteResponse4_pkg::*;
import Axi4ReadAddressReady_pkg::*;
import Axi4ReadData4_256_pkg::*;
import Axi4Responder4_256_pkg::*;
import Axi4WriteAddress32_4_pkg::*;
import Axi4WriteData256_pkg::*;
import Axi4WriteResponseReady_pkg::*;
import Axi4ReadAddress32_4_pkg::*;
import Axi4ReadDataReady_pkg::*;
import Axi4Driver32_4_256_pkg::*;
import CacheRequest_pkg::*;
import L2ActiveRequestComb_pkg::*;
import L2CacheFsmState_pkg::*;
import L2RequestGeometryComb_pkg::*;
import L2EvictCandidateComb_pkg::*;
import L2HitLookupComb_pkg::*;
import L2WordPairComb_pkg::*;
import L2CpuWaitComb_pkg::*;
import L2IoWritePayloadComb_pkg::*;
import L2AxiRouteComb_pkg::*;
import L2AxiRequestNoveltyComb_pkg::*;
import CacheResponse_pkg::*;
import L1PeerStoreState_pkg::*;
import L1PeerInvalidateComb_pkg::*;


module CPU (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire dma_in__awvalid_in
,   output wire dma_in__awready_out
,   input wire[32-1:0] dma_in__awaddr_in
,   input wire[4-1:0] dma_in__awid_in
,   input wire dma_in__wvalid_in
,   output wire dma_in__wready_out
,   input wire[256-1:0] dma_in__wdata_in
,   input wire[256/'h8-1:0] dma_in__wstrb_in
,   input wire dma_in__wlast_in
,   output wire dma_in__bvalid_out
,   input wire dma_in__bready_in
,   output wire[4-1:0] dma_in__bid_out
,   input wire dma_in__arvalid_in
,   output wire dma_in__arready_out
,   input wire[32-1:0] dma_in__araddr_in
,   input wire[4-1:0] dma_in__arid_in
,   output wire dma_in__rvalid_out
,   input wire dma_in__rready_in
,   output wire[256-1:0] dma_in__rdata_out
,   output wire dma_in__rlast_out
,   output wire[4-1:0] dma_in__rid_out
,   output wire memory__awvalid_out
,   input wire memory__awready_in
,   output wire[31-1:0] memory__awaddr_out
,   output wire[4-1:0] memory__awid_out
,   output wire memory__wvalid_out
,   input wire memory__wready_in
,   output wire[256-1:0] memory__wdata_out
,   output wire[256/'h8-1:0] memory__wstrb_out
,   output wire memory__wlast_out
,   input wire memory__bvalid_in
,   output wire memory__bready_out
,   input wire[4-1:0] memory__bid_in
,   output wire memory__arvalid_out
,   input wire memory__arready_in
,   output wire[31-1:0] memory__araddr_out
,   output wire[4-1:0] memory__arid_out
,   input wire memory__rvalid_in
,   output wire memory__rready_out
,   input wire[256-1:0] memory__rdata_in
,   input wire memory__rlast_in
,   input wire[4-1:0] memory__rid_in
,   output wire iomem__awvalid_out
,   input wire iomem__awready_in
,   output wire[32-1:0] iomem__awaddr_out
,   output wire[4-1:0] iomem__awid_out
,   output wire iomem__wvalid_out
,   input wire iomem__wready_in
,   output wire[256-1:0] iomem__wdata_out
,   output wire[256/'h8-1:0] iomem__wstrb_out
,   output wire iomem__wlast_out
,   input wire iomem__bvalid_in
,   output wire iomem__bready_out
,   input wire[4-1:0] iomem__bid_in
,   output wire iomem__arvalid_out
,   input wire iomem__arready_in
,   output wire[32-1:0] iomem__araddr_out
,   output wire[4-1:0] iomem__arid_out
,   input wire iomem__rvalid_in
,   output wire iomem__rready_out
,   input wire[256-1:0] iomem__rdata_in
,   input wire iomem__rlast_in
,   input wire[4-1:0] iomem__rid_in
,   input wire[32-1:0] reset_pc_in
,   input wire[32-1:0] boot_hartid_in
,   input wire[32-1:0] boot_dtb_addr_in
,   input wire[2-1:0] boot_priv_in
,   input wire cache_invalidate_in
,   input wire software_irq_in[4]
,   input wire timer_irq_in[4]
,   input wire external_irq_in[4]
);
    parameter  CORES = 64'h4;
    parameter  DATA_WIDTH = 64'h100;
    parameter  ID_WIDTH = 64'h4;
    parameter  MEMORY_BYTES = 64'h40000000;
    parameter  IO_BYTES = 64'h400000;
    parameter  EXTERNAL_ADDR_WIDTH = 64'h1F;
    parameter  L1I_BYTES = 64'h1000;
    parameter  L1D_BYTES = 64'h400;
    parameter  L2_BYTES = 64'h2000;
    parameter  CACHE_LINE_BYTES = 64'h20;
    parameter  L1_WAYS = 64'h2;
    parameter  L2_WAYS = 64'h4;


    // regs and combs
    TribeCoreDebug debug_core_type_dependency;
    TribeMmuDebug debug_mmu_type_dependency;
    TribeCacheDebug debug_cache_type_dependency;
    TribeWritebackDebug debug_wb_type_dependency;
    TribeCsrDebug debug_csr_type_dependency;
    TribeIrqDebug debug_irq_type_dependency;
    TribeRegsDebug debug_regs_type_dependency;
    TribeBranchDebug debug_branch_type_dependency;
    TribeDecodeDebug debug_decode_type_dependency;
    TribeSbiDebug debug_sbi_type_dependency;
    TribePerf debug_perf_type_dependency;

    // members
    wire tribe__dmem_write_out;
    wire[31:0] tribe__dmem_write_data_out;
    wire[7:0] tribe__dmem_write_mask_out;
    wire tribe__dmem_read_out;
    wire[31:0] tribe__dmem_addr_out;
    wire[31:0] tribe__imem_read_addr_out;
    TribeCoreDebug tribe__debug_core_out;
    TribeMmuDebug tribe__debug_mmu_out;
    TribeCacheDebug tribe__debug_cache_out;
    TribeWritebackDebug tribe__debug_wb_out;
    TribeCsrDebug tribe__debug_csr_out;
    TribeIrqDebug tribe__debug_irq_out;
    TribeRegsDebug tribe__debug_regs_out;
    TribeBranchDebug tribe__debug_branch_out;
    TribeDecodeDebug tribe__debug_decode_out;
    wire tribe__sbi_set_timer_out;
    wire[31:0] tribe__sbi_timer_lo_out;
    wire[31:0] tribe__sbi_timer_hi_out;
    wire tribe__sbi_set_timer_per_core_out[4];
    wire[31:0] tribe__sbi_timer_lo_per_core_out[4];
    wire[31:0] tribe__sbi_timer_hi_per_core_out[4];
    TribeSbiDebug tribe__debug_sbi_out;
    TribePerf tribe__perf_out;
    wire[31:0] tribe__reset_pc_in;
    wire[31:0] tribe__boot_hartid_in;
    wire[31:0] tribe__boot_dtb_addr_in;
    wire[2-1:0] tribe__boot_priv_in;
    wire tribe__external_cache_invalidate_in;
    wire[31:0] tribe__memory_base_in;
    wire[31:0] tribe__memory_size_in;
    wire[31:0] tribe__mem_region_size_in[4];
    wire tribe__clint_msip_in;
    wire tribe__clint_mtip_in;
    wire[31:0] tribe__time_lo_in;
    wire[31:0] tribe__time_hi_in;
    wire tribe__external_irq_in;
    wire tribe__clint_msip_per_core_in[4];
    wire tribe__clint_mtip_per_core_in[4];
    wire tribe__external_irq_per_core_in[4];
    wire tribe__axi_in__awvalid_in[4];
    wire tribe__axi_in__awready_out[4];
    wire[32-1:0] tribe__axi_in__awaddr_in[4];
    wire[4-1:0] tribe__axi_in__awid_in[4];
    wire tribe__axi_in__wvalid_in[4];
    wire tribe__axi_in__wready_out[4];
    wire[256-1:0] tribe__axi_in__wdata_in[4];
    wire[256/'h8-1:0] tribe__axi_in__wstrb_in[4];
    wire tribe__axi_in__wlast_in[4];
    wire tribe__axi_in__bvalid_out[4];
    wire tribe__axi_in__bready_in[4];
    wire[4-1:0] tribe__axi_in__bid_out[4];
    wire tribe__axi_in__arvalid_in[4];
    wire tribe__axi_in__arready_out[4];
    wire[32-1:0] tribe__axi_in__araddr_in[4];
    wire[4-1:0] tribe__axi_in__arid_in[4];
    wire tribe__axi_in__rvalid_out[4];
    wire tribe__axi_in__rready_in[4];
    wire[256-1:0] tribe__axi_in__rdata_out[4];
    wire tribe__axi_in__rlast_out[4];
    wire[4-1:0] tribe__axi_in__rid_out[4];
    wire tribe__axi_out__awvalid_out[4];
    wire tribe__axi_out__awready_in[4];
    wire[31-1:0] tribe__axi_out__awaddr_out[4];
    wire[4-1:0] tribe__axi_out__awid_out[4];
    wire tribe__axi_out__wvalid_out[4];
    wire tribe__axi_out__wready_in[4];
    wire[256-1:0] tribe__axi_out__wdata_out[4];
    wire[256/'h8-1:0] tribe__axi_out__wstrb_out[4];
    wire tribe__axi_out__wlast_out[4];
    wire tribe__axi_out__bvalid_in[4];
    wire tribe__axi_out__bready_out[4];
    wire[4-1:0] tribe__axi_out__bid_in[4];
    wire tribe__axi_out__arvalid_out[4];
    wire tribe__axi_out__arready_in[4];
    wire[31-1:0] tribe__axi_out__araddr_out[4];
    wire[4-1:0] tribe__axi_out__arid_out[4];
    wire tribe__axi_out__rvalid_in[4];
    wire tribe__axi_out__rready_out[4];
    wire[256-1:0] tribe__axi_out__rdata_in[4];
    wire tribe__axi_out__rlast_in[4];
    wire[4-1:0] tribe__axi_out__rid_in[4];
    wire tribe__debugen_in;
    TribeTest #(
        4
    ) tribe (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .dmem_write_out(tribe__dmem_write_out)
,       .dmem_write_data_out(tribe__dmem_write_data_out)
,       .dmem_write_mask_out(tribe__dmem_write_mask_out)
,       .dmem_read_out(tribe__dmem_read_out)
,       .dmem_addr_out(tribe__dmem_addr_out)
,       .imem_read_addr_out(tribe__imem_read_addr_out)
,       .debug_core_out(tribe__debug_core_out)
,       .debug_mmu_out(tribe__debug_mmu_out)
,       .debug_cache_out(tribe__debug_cache_out)
,       .debug_wb_out(tribe__debug_wb_out)
,       .debug_csr_out(tribe__debug_csr_out)
,       .debug_irq_out(tribe__debug_irq_out)
,       .debug_regs_out(tribe__debug_regs_out)
,       .debug_branch_out(tribe__debug_branch_out)
,       .debug_decode_out(tribe__debug_decode_out)
,       .sbi_set_timer_out(tribe__sbi_set_timer_out)
,       .sbi_timer_lo_out(tribe__sbi_timer_lo_out)
,       .sbi_timer_hi_out(tribe__sbi_timer_hi_out)
,       .sbi_set_timer_per_core_out(tribe__sbi_set_timer_per_core_out)
,       .sbi_timer_lo_per_core_out(tribe__sbi_timer_lo_per_core_out)
,       .sbi_timer_hi_per_core_out(tribe__sbi_timer_hi_per_core_out)
,       .debug_sbi_out(tribe__debug_sbi_out)
,       .perf_out(tribe__perf_out)
,       .reset_pc_in(tribe__reset_pc_in)
,       .boot_hartid_in(tribe__boot_hartid_in)
,       .boot_dtb_addr_in(tribe__boot_dtb_addr_in)
,       .boot_priv_in(tribe__boot_priv_in)
,       .external_cache_invalidate_in(tribe__external_cache_invalidate_in)
,       .memory_base_in(tribe__memory_base_in)
,       .memory_size_in(tribe__memory_size_in)
,       .mem_region_size_in(tribe__mem_region_size_in)
,       .clint_msip_in(tribe__clint_msip_in)
,       .clint_mtip_in(tribe__clint_mtip_in)
,       .time_lo_in(tribe__time_lo_in)
,       .time_hi_in(tribe__time_hi_in)
,       .external_irq_in(tribe__external_irq_in)
,       .clint_msip_per_core_in(tribe__clint_msip_per_core_in)
,       .clint_mtip_per_core_in(tribe__clint_mtip_per_core_in)
,       .external_irq_per_core_in(tribe__external_irq_per_core_in)
,       .axi_in__awvalid_in(tribe__axi_in__awvalid_in)
,       .axi_in__awready_out(tribe__axi_in__awready_out)
,       .axi_in__awaddr_in(tribe__axi_in__awaddr_in)
,       .axi_in__awid_in(tribe__axi_in__awid_in)
,       .axi_in__wvalid_in(tribe__axi_in__wvalid_in)
,       .axi_in__wready_out(tribe__axi_in__wready_out)
,       .axi_in__wdata_in(tribe__axi_in__wdata_in)
,       .axi_in__wstrb_in(tribe__axi_in__wstrb_in)
,       .axi_in__wlast_in(tribe__axi_in__wlast_in)
,       .axi_in__bvalid_out(tribe__axi_in__bvalid_out)
,       .axi_in__bready_in(tribe__axi_in__bready_in)
,       .axi_in__bid_out(tribe__axi_in__bid_out)
,       .axi_in__arvalid_in(tribe__axi_in__arvalid_in)
,       .axi_in__arready_out(tribe__axi_in__arready_out)
,       .axi_in__araddr_in(tribe__axi_in__araddr_in)
,       .axi_in__arid_in(tribe__axi_in__arid_in)
,       .axi_in__rvalid_out(tribe__axi_in__rvalid_out)
,       .axi_in__rready_in(tribe__axi_in__rready_in)
,       .axi_in__rdata_out(tribe__axi_in__rdata_out)
,       .axi_in__rlast_out(tribe__axi_in__rlast_out)
,       .axi_in__rid_out(tribe__axi_in__rid_out)
,       .axi_out__awvalid_out(tribe__axi_out__awvalid_out)
,       .axi_out__awready_in(tribe__axi_out__awready_in)
,       .axi_out__awaddr_out(tribe__axi_out__awaddr_out)
,       .axi_out__awid_out(tribe__axi_out__awid_out)
,       .axi_out__wvalid_out(tribe__axi_out__wvalid_out)
,       .axi_out__wready_in(tribe__axi_out__wready_in)
,       .axi_out__wdata_out(tribe__axi_out__wdata_out)
,       .axi_out__wstrb_out(tribe__axi_out__wstrb_out)
,       .axi_out__wlast_out(tribe__axi_out__wlast_out)
,       .axi_out__bvalid_in(tribe__axi_out__bvalid_in)
,       .axi_out__bready_out(tribe__axi_out__bready_out)
,       .axi_out__bid_in(tribe__axi_out__bid_in)
,       .axi_out__arvalid_out(tribe__axi_out__arvalid_out)
,       .axi_out__arready_in(tribe__axi_out__arready_in)
,       .axi_out__araddr_out(tribe__axi_out__araddr_out)
,       .axi_out__arid_out(tribe__axi_out__arid_out)
,       .axi_out__rvalid_in(tribe__axi_out__rvalid_in)
,       .axi_out__rready_out(tribe__axi_out__rready_out)
,       .axi_out__rdata_in(tribe__axi_out__rdata_in)
,       .axi_out__rlast_in(tribe__axi_out__rlast_in)
,       .axi_out__rid_in(tribe__axi_out__rid_in)
,       .debugen_in(tribe__debugen_in)
    );

    // tmp variables


    generate  // _assign
        genvar gcore;
        genvar gport;
        assign tribe__reset_pc_in = reset_pc_in;
        assign tribe__boot_hartid_in = boot_hartid_in;
        assign tribe__boot_dtb_addr_in = boot_dtb_addr_in;
        assign tribe__boot_priv_in = boot_priv_in;
        assign tribe__external_cache_invalidate_in = cache_invalidate_in;
        assign tribe__memory_base_in = unsigned'(32'('h0));
        assign tribe__memory_size_in = unsigned'(32'((MEMORY_BYTES + IO_BYTES)));
        assign tribe__mem_region_size_in['h0] = unsigned'(32'(MEMORY_BYTES));
        assign tribe__mem_region_size_in['h1] = unsigned'(32'('h0));
        assign tribe__mem_region_size_in['h2] = unsigned'(32'('h0));
        assign tribe__mem_region_size_in['h3] = unsigned'(32'(IO_BYTES));
        assign tribe__debugen_in=0;
        assign tribe__time_lo_in = unsigned'(32'('h0));
        assign tribe__time_hi_in = unsigned'(32'('h0));
        for (gcore='h0;gcore < CORES;gcore=gcore+1) begin
            assign tribe__clint_msip_per_core_in[gcore] = software_irq_in[gcore];
            assign tribe__clint_mtip_per_core_in[gcore] = timer_irq_in[gcore];
            assign tribe__external_irq_per_core_in[gcore] = external_irq_in[gcore];
        end
        assign tribe__axi_in__awvalid_in['h0] = dma_in__awvalid_in;
        assign tribe__axi_in__awaddr_in['h0] = dma_in__awaddr_in;
        assign tribe__axi_in__awid_in['h0] = dma_in__awid_in;
        assign tribe__axi_in__wvalid_in['h0] = dma_in__wvalid_in;
        assign tribe__axi_in__wdata_in['h0] = dma_in__wdata_in;
        assign tribe__axi_in__wstrb_in['h0] = dma_in__wstrb_in;
        assign tribe__axi_in__wlast_in['h0] = dma_in__wlast_in;
        assign tribe__axi_in__bready_in['h0] = dma_in__bready_in;
        assign tribe__axi_in__arvalid_in['h0] = dma_in__arvalid_in;
        assign tribe__axi_in__araddr_in['h0] = dma_in__araddr_in;
        assign tribe__axi_in__arid_in['h0] = dma_in__arid_in;
        assign tribe__axi_in__rready_in['h0] = dma_in__rready_in;
        assign dma_in__awready_out = tribe__axi_in__awready_out['h0];
        assign dma_in__wready_out = tribe__axi_in__wready_out['h0];
        assign dma_in__bvalid_out = tribe__axi_in__bvalid_out['h0];
        assign dma_in__bid_out = tribe__axi_in__bid_out['h0];
        assign dma_in__arready_out = tribe__axi_in__arready_out['h0];
        assign dma_in__rvalid_out = tribe__axi_in__rvalid_out['h0];
        assign dma_in__rdata_out = tribe__axi_in__rdata_out['h0];
        assign dma_in__rlast_out = tribe__axi_in__rlast_out['h0];
        assign dma_in__rid_out = tribe__axi_in__rid_out['h0];
        for (gport='h1;gport < 'h4;gport=gport+1) begin
            assign tribe__axi_in__awvalid_in[gport] = 0;
            assign tribe__axi_in__awaddr_in[gport] = unsigned'(32'(unsigned'(32'h0)));
            assign tribe__axi_in__awid_in[gport] = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
            assign tribe__axi_in__wvalid_in[gport] = 0;
            assign tribe__axi_in__wdata_in[gport] = 'h0;
            assign tribe__axi_in__wstrb_in[gport] = 'h0;
            assign tribe__axi_in__wlast_in[gport] = 0;
            assign tribe__axi_in__bready_in[gport] = 0;
            assign tribe__axi_in__arvalid_in[gport] = 0;
            assign tribe__axi_in__araddr_in[gport] = unsigned'(32'(unsigned'(32'h0)));
            assign tribe__axi_in__arid_in[gport] = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
            assign tribe__axi_in__rready_in[gport] = 0;
        end
        assign memory__awvalid_out = tribe__axi_out__awvalid_out['h0];
        assign memory__awaddr_out = tribe__axi_out__awaddr_out['h0];
        assign memory__awid_out = tribe__axi_out__awid_out['h0];
        assign memory__wvalid_out = tribe__axi_out__wvalid_out['h0];
        assign memory__wdata_out = tribe__axi_out__wdata_out['h0];
        assign memory__wstrb_out = tribe__axi_out__wstrb_out['h0];
        assign memory__wlast_out = tribe__axi_out__wlast_out['h0];
        assign memory__bready_out = tribe__axi_out__bready_out['h0];
        assign memory__arvalid_out = tribe__axi_out__arvalid_out['h0];
        assign memory__araddr_out = tribe__axi_out__araddr_out['h0];
        assign memory__arid_out = tribe__axi_out__arid_out['h0];
        assign memory__rready_out = tribe__axi_out__rready_out['h0];
        assign tribe__axi_out__awready_in['h0] = memory__awready_in;
        assign tribe__axi_out__wready_in['h0] = memory__wready_in;
        assign tribe__axi_out__bvalid_in['h0] = memory__bvalid_in;
        assign tribe__axi_out__bid_in['h0] = memory__bid_in;
        assign tribe__axi_out__arready_in['h0] = memory__arready_in;
        assign tribe__axi_out__rvalid_in['h0] = memory__rvalid_in;
        assign tribe__axi_out__rdata_in['h0] = memory__rdata_in;
        assign tribe__axi_out__rlast_in['h0] = memory__rlast_in;
        assign tribe__axi_out__rid_in['h0] = memory__rid_in;
        assign iomem__awvalid_out = tribe__axi_out__awvalid_out['h3];
        assign iomem__awaddr_out = unsigned'(32'(unsigned'(32'(tribe__axi_out__awaddr_out['h3]))));
        assign iomem__awid_out = tribe__axi_out__awid_out['h3];
        assign iomem__wvalid_out = tribe__axi_out__wvalid_out['h3];
        assign iomem__wdata_out = tribe__axi_out__wdata_out['h3];
        assign iomem__wstrb_out = tribe__axi_out__wstrb_out['h3];
        assign iomem__wlast_out = tribe__axi_out__wlast_out['h3];
        assign iomem__bready_out = tribe__axi_out__bready_out['h3];
        assign iomem__arvalid_out = tribe__axi_out__arvalid_out['h3];
        assign iomem__araddr_out = unsigned'(32'(unsigned'(32'(tribe__axi_out__araddr_out['h3]))));
        assign iomem__arid_out = tribe__axi_out__arid_out['h3];
        assign iomem__rready_out = tribe__axi_out__rready_out['h3];
        assign tribe__axi_out__awready_in['h3] = iomem__awready_in;
        assign tribe__axi_out__wready_in['h3] = iomem__wready_in;
        assign tribe__axi_out__bvalid_in['h3] = iomem__bvalid_in;
        assign tribe__axi_out__bid_in['h3] = iomem__bid_in;
        assign tribe__axi_out__arready_in['h3] = iomem__arready_in;
        assign tribe__axi_out__rvalid_in['h3] = iomem__rvalid_in;
        assign tribe__axi_out__rdata_in['h3] = iomem__rdata_in;
        assign tribe__axi_out__rlast_in['h3] = iomem__rlast_in;
        assign tribe__axi_out__rid_in['h3] = iomem__rid_in;
        for (gport='h1;gport < 'h3;gport=gport+1) begin
            assign tribe__axi_out__awready_in[gport] = 1;
            assign tribe__axi_out__wready_in[gport] = 1;
            assign tribe__axi_out__bvalid_in[gport] = 0;
            assign tribe__axi_out__bid_in[gport] = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
            assign tribe__axi_out__arready_in[gport] = 1;
            assign tribe__axi_out__rvalid_in[gport] = 0;
            assign tribe__axi_out__rdata_in[gport] = 'h0;
            assign tribe__axi_out__rlast_in[gport] = 0;
            assign tribe__axi_out__rid_in[gport] = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
        end
        assign dma_in__awready_out = tribe__axi_in__awready_out['h0];
        assign dma_in__wready_out = tribe__axi_in__wready_out['h0];
        assign dma_in__bvalid_out = tribe__axi_in__bvalid_out['h0];
        assign dma_in__bid_out = tribe__axi_in__bid_out['h0];
        assign dma_in__arready_out = tribe__axi_in__arready_out['h0];
        assign dma_in__rvalid_out = tribe__axi_in__rvalid_out['h0];
        assign dma_in__rdata_out = tribe__axi_in__rdata_out['h0];
        assign dma_in__rlast_out = tribe__axi_in__rlast_out['h0];
        assign dma_in__rid_out = tribe__axi_in__rid_out['h0];
        assign memory__awvalid_out = tribe__axi_out__awvalid_out['h0];
        assign memory__awaddr_out = tribe__axi_out__awaddr_out['h0];
        assign memory__awid_out = tribe__axi_out__awid_out['h0];
        assign memory__wvalid_out = tribe__axi_out__wvalid_out['h0];
        assign memory__wdata_out = tribe__axi_out__wdata_out['h0];
        assign memory__wstrb_out = tribe__axi_out__wstrb_out['h0];
        assign memory__wlast_out = tribe__axi_out__wlast_out['h0];
        assign memory__bready_out = tribe__axi_out__bready_out['h0];
        assign memory__arvalid_out = tribe__axi_out__arvalid_out['h0];
        assign memory__araddr_out = tribe__axi_out__araddr_out['h0];
        assign memory__arid_out = tribe__axi_out__arid_out['h0];
        assign memory__rready_out = tribe__axi_out__rready_out['h0];
        assign iomem__awvalid_out = tribe__axi_out__awvalid_out['h3];
        assign iomem__awid_out = tribe__axi_out__awid_out['h3];
        assign iomem__wvalid_out = tribe__axi_out__wvalid_out['h3];
        assign iomem__wdata_out = tribe__axi_out__wdata_out['h3];
        assign iomem__wstrb_out = tribe__axi_out__wstrb_out['h3];
        assign iomem__wlast_out = tribe__axi_out__wlast_out['h3];
        assign iomem__bready_out = tribe__axi_out__bready_out['h3];
        assign iomem__arvalid_out = tribe__axi_out__arvalid_out['h3];
        assign iomem__arid_out = tribe__axi_out__arid_out['h3];
        assign iomem__rready_out = tribe__axi_out__rready_out['h3];
    endgenerate

    task _work (input logic reset);
    begin: _work
    end
    endtask

    task _work_neg (input logic reset);
    begin: _work_neg
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin

        _work(reset);

    end

    always_ff @(negedge clk) begin

        _work_neg(reset);

    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
