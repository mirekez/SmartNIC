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


module TribeTest #(
    parameter CPU_CORES = 'h1
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   output wire dmem_write_out
,   output wire[31:0] dmem_write_data_out
,   output wire[7:0] dmem_write_mask_out
,   output wire dmem_read_out
,   output wire[31:0] dmem_addr_out
,   output wire[31:0] imem_read_addr_out
,   output TribeCoreDebug debug_core_out
,   output TribeMmuDebug debug_mmu_out
,   output TribeCacheDebug debug_cache_out
,   output TribeWritebackDebug debug_wb_out
,   output TribeCsrDebug debug_csr_out
,   output TribeIrqDebug debug_irq_out
,   output TribeRegsDebug debug_regs_out
,   output TribeBranchDebug debug_branch_out
,   output TribeDecodeDebug debug_decode_out
,   output wire sbi_set_timer_out
,   output wire[31:0] sbi_timer_lo_out
,   output wire[31:0] sbi_timer_hi_out
,   output wire sbi_set_timer_per_core_out[CPU_CORES]
,   output wire[31:0] sbi_timer_lo_per_core_out[CPU_CORES]
,   output wire[31:0] sbi_timer_hi_per_core_out[CPU_CORES]
,   output TribeSbiDebug debug_sbi_out
,   output TribePerf perf_out
,   input wire[31:0] reset_pc_in
,   input wire[31:0] boot_hartid_in
,   input wire[31:0] boot_dtb_addr_in
,   input wire[2-1:0] boot_priv_in
,   input wire external_cache_invalidate_in
,   input wire[31:0] memory_base_in
,   input wire[31:0] memory_size_in
,   input wire[31:0] mem_region_size_in[4]
,   input wire clint_msip_in
,   input wire clint_mtip_in
,   input wire[31:0] time_lo_in
,   input wire[31:0] time_hi_in
,   input wire external_irq_in
,   input wire clint_msip_per_core_in[CPU_CORES]
,   input wire clint_mtip_per_core_in[CPU_CORES]
,   input wire external_irq_per_core_in[CPU_CORES]
,   input wire axi_in__awvalid_in[4]
,   output wire axi_in__awready_out[4]
,   input wire[32-1:0] axi_in__awaddr_in[4]
,   input wire[4-1:0] axi_in__awid_in[4]
,   input wire axi_in__wvalid_in[4]
,   output wire axi_in__wready_out[4]
,   input wire[256-1:0] axi_in__wdata_in[4]
,   input wire[256/'h8-1:0] axi_in__wstrb_in[4]
,   input wire axi_in__wlast_in[4]
,   output wire axi_in__bvalid_out[4]
,   input wire axi_in__bready_in[4]
,   output wire[4-1:0] axi_in__bid_out[4]
,   input wire axi_in__arvalid_in[4]
,   output wire axi_in__arready_out[4]
,   input wire[32-1:0] axi_in__araddr_in[4]
,   input wire[4-1:0] axi_in__arid_in[4]
,   output wire axi_in__rvalid_out[4]
,   input wire axi_in__rready_in[4]
,   output wire[256-1:0] axi_in__rdata_out[4]
,   output wire axi_in__rlast_out[4]
,   output wire[4-1:0] axi_in__rid_out[4]
,   output wire axi_out__awvalid_out[4]
,   input wire axi_out__awready_in[4]
,   output wire[31-1:0] axi_out__awaddr_out[4]
,   output wire[4-1:0] axi_out__awid_out[4]
,   output wire axi_out__wvalid_out[4]
,   input wire axi_out__wready_in[4]
,   output wire[256-1:0] axi_out__wdata_out[4]
,   output wire[256/'h8-1:0] axi_out__wstrb_out[4]
,   output wire axi_out__wlast_out[4]
,   input wire axi_out__bvalid_in[4]
,   output wire axi_out__bready_out[4]
,   input wire[4-1:0] axi_out__bid_in[4]
,   output wire axi_out__arvalid_out[4]
,   input wire axi_out__arready_in[4]
,   output wire[31-1:0] axi_out__araddr_out[4]
,   output wire[4-1:0] axi_out__arid_out[4]
,   input wire axi_out__rvalid_in[4]
,   output wire axi_out__rready_out[4]
,   input wire[256-1:0] axi_out__rdata_in[4]
,   input wire axi_out__rlast_in[4]
,   input wire[4-1:0] axi_out__rid_in[4]
,   input wire debugen_in
);
    parameter  L2_TOTAL_SIZE = 64'h10000;
    parameter  L2_PORT_WIDTH = 64'h100;
    parameter  L2_LINE_SIZE = 64'h20;
    parameter  L2_WAYS = 64'h4;
    parameter  L2_ADDRESS_BITS = 64'h20;
    parameter  L2_RAM_ADDRESS_BITS = 64'h1F;
    parameter  L2_PORT_COUNT = 64'h4;
    parameter  ATOMIC_OWNER_BITS = (CPU_CORES > 'h1) ? ($clog2(CPU_CORES)) : ('h1);


    // regs and combs
    L1PeerStoreState peer_store_reg[CPU_CORES];
    reg atomic_owner_valid_reg;
    reg[ATOMIC_OWNER_BITS-1:0] atomic_owner_reg;
    reg[ATOMIC_OWNER_BITS-1:0] atomic_rr_reg;
    L1PeerInvalidateComb peer_invalidate_comb[CPU_CORES];
    logic[CPU_CORES-1:0] sbi_ipi_targets_comb;
;
    logic[CPU_CORES-1:0] sbi_fence_i_targets_comb;
;
    logic[CPU_CORES-1:0] sbi_sfence_targets_comb;
;
    logic[CPU_CORES-1:0] atomic_grant_comb;
;
    logic[CPU_CORES-1:0] atomic_data_access_comb;
;

    // members
    genvar __i;
    wire cores__dmem_write_out[CPU_CORES];
    wire[31:0] cores__dmem_write_data_out[CPU_CORES];
    wire[7:0] cores__dmem_write_mask_out[CPU_CORES];
    wire cores__dmem_read_out[CPU_CORES];
    wire[31:0] cores__dmem_addr_out[CPU_CORES];
    wire[31:0] cores__imem_read_addr_out[CPU_CORES];
    wire cores__atomic_request_out[CPU_CORES];
    wire cores__atomic_data_request_out[CPU_CORES];
    wire cores__atomic_complete_out[CPU_CORES];
    wire cores__atomic_grant_in[CPU_CORES];
    TribeCoreDebug cores__debug_core_out[CPU_CORES];
    TribeMmuDebug cores__debug_mmu_out[CPU_CORES];
    TribeCacheDebug cores__debug_cache_out[CPU_CORES];
    TribeWritebackDebug cores__debug_wb_out[CPU_CORES];
    TribeCsrDebug cores__debug_csr_out[CPU_CORES];
    TribeIrqDebug cores__debug_irq_out[CPU_CORES];
    TribeRegsDebug cores__debug_regs_out[CPU_CORES];
    TribeBranchDebug cores__debug_branch_out[CPU_CORES];
    TribeDecodeDebug cores__debug_decode_out[CPU_CORES];
    wire cores__sbi_set_timer_out[CPU_CORES];
    wire[31:0] cores__sbi_timer_lo_out[CPU_CORES];
    wire[31:0] cores__sbi_timer_hi_out[CPU_CORES];
    wire cores__sbi_send_ipi_out[CPU_CORES];
    wire cores__sbi_remote_fence_i_out[CPU_CORES];
    wire cores__sbi_remote_sfence_vma_out[CPU_CORES];
    wire[31:0] cores__sbi_hart_mask_out[CPU_CORES];
    wire[31:0] cores__sbi_hart_base_out[CPU_CORES];
    TribeSbiDebug cores__debug_sbi_out[CPU_CORES];
    wire[31:0] cores__reset_pc_in[CPU_CORES];
    wire[31:0] cores__boot_hartid_in[CPU_CORES];
    wire[31:0] cores__boot_dtb_addr_in[CPU_CORES];
    wire[2-1:0] cores__boot_priv_in[CPU_CORES];
    wire cores__external_cache_invalidate_in[CPU_CORES];
    wire cores__peer_cache_invalidate_in[CPU_CORES];
    wire[31:0] cores__peer_cache_invalidate_addr_in[CPU_CORES];
    wire[31:0] cores__memory_base_in[CPU_CORES];
    wire[31:0] cores__memory_size_in[CPU_CORES];
    wire[31:0] cores__mem_region_size_in[CPU_CORES][4];
    wire cores__i_mem_out__read_out[CPU_CORES];
    wire cores__i_mem_out__write_out[CPU_CORES];
    wire[31:0] cores__i_mem_out__addr_out[CPU_CORES];
    wire[31:0] cores__i_mem_out__write_data_out[CPU_CORES];
    wire[7:0] cores__i_mem_out__write_mask_out[CPU_CORES];
    wire cores__i_mem_out__cache_disable_out[CPU_CORES];
    wire[256-1:0] cores__i_mem_out__read_data_in[CPU_CORES];
    wire cores__i_mem_out__wait_in[CPU_CORES];
    wire cores__d_mem_out__read_out[CPU_CORES];
    wire cores__d_mem_out__write_out[CPU_CORES];
    wire[31:0] cores__d_mem_out__addr_out[CPU_CORES];
    wire[31:0] cores__d_mem_out__write_data_out[CPU_CORES];
    wire[7:0] cores__d_mem_out__write_mask_out[CPU_CORES];
    wire cores__d_mem_out__cache_disable_out[CPU_CORES];
    wire[256-1:0] cores__d_mem_out__read_data_in[CPU_CORES];
    wire cores__d_mem_out__wait_in[CPU_CORES];
    wire cores__clint_msip_in[CPU_CORES];
    wire cores__clint_mtip_in[CPU_CORES];
    wire[31:0] cores__time_lo_in[CPU_CORES];
    wire[31:0] cores__time_hi_in[CPU_CORES];
    wire cores__external_irq_in[CPU_CORES];
    wire cores__sbi_ipi_in[CPU_CORES];
    wire cores__remote_fence_i_in[CPU_CORES];
    wire cores__remote_sfence_vma_in[CPU_CORES];
    TribePerf cores__perf_out[CPU_CORES];
    wire cores__debugen_in[CPU_CORES];
    generate
    for (__i=0; __i < CPU_CORES; __i = __i + 1) begin
        Tribe          cores (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .dmem_write_out(cores__dmem_write_out[__i])
        ,           .dmem_write_data_out(cores__dmem_write_data_out[__i])
        ,           .dmem_write_mask_out(cores__dmem_write_mask_out[__i])
        ,           .dmem_read_out(cores__dmem_read_out[__i])
        ,           .dmem_addr_out(cores__dmem_addr_out[__i])
        ,           .imem_read_addr_out(cores__imem_read_addr_out[__i])
        ,           .sbi_set_timer_out(cores__sbi_set_timer_out[__i])
        ,           .sbi_timer_lo_out(cores__sbi_timer_lo_out[__i])
        ,           .sbi_timer_hi_out(cores__sbi_timer_hi_out[__i])
        ,           .debug_sbi_out(cores__debug_sbi_out[__i])
        ,           .reset_pc_in(cores__reset_pc_in[__i])
        ,           .boot_hartid_in(cores__boot_hartid_in[__i])
        ,           .boot_dtb_addr_in(cores__boot_dtb_addr_in[__i])
        ,           .boot_priv_in(cores__boot_priv_in[__i])
        ,           .external_cache_invalidate_in(cores__external_cache_invalidate_in[__i])
        ,           .peer_cache_invalidate_in(cores__peer_cache_invalidate_in[__i])
        ,           .peer_cache_invalidate_addr_in(cores__peer_cache_invalidate_addr_in[__i])
        ,           .memory_base_in(cores__memory_base_in[__i])
        ,           .memory_size_in(cores__memory_size_in[__i])
        ,           .mem_region_size_in(cores__mem_region_size_in[__i])
        ,           .i_mem_out__read_out(cores__i_mem_out__read_out[__i])
        ,           .i_mem_out__write_out(cores__i_mem_out__write_out[__i])
        ,           .i_mem_out__addr_out(cores__i_mem_out__addr_out[__i])
        ,           .i_mem_out__write_data_out(cores__i_mem_out__write_data_out[__i])
        ,           .i_mem_out__write_mask_out(cores__i_mem_out__write_mask_out[__i])
        ,           .i_mem_out__cache_disable_out(cores__i_mem_out__cache_disable_out[__i])
        ,           .i_mem_out__read_data_in(cores__i_mem_out__read_data_in[__i])
        ,           .i_mem_out__wait_in(cores__i_mem_out__wait_in[__i])
        ,           .d_mem_out__read_out(cores__d_mem_out__read_out[__i])
        ,           .d_mem_out__write_out(cores__d_mem_out__write_out[__i])
        ,           .d_mem_out__addr_out(cores__d_mem_out__addr_out[__i])
        ,           .d_mem_out__write_data_out(cores__d_mem_out__write_data_out[__i])
        ,           .d_mem_out__write_mask_out(cores__d_mem_out__write_mask_out[__i])
        ,           .d_mem_out__cache_disable_out(cores__d_mem_out__cache_disable_out[__i])
        ,           .d_mem_out__read_data_in(cores__d_mem_out__read_data_in[__i])
        ,           .d_mem_out__wait_in(cores__d_mem_out__wait_in[__i])
        ,           .perf_out(cores__perf_out[__i])
        ,           .debugen_in(cores__debugen_in[__i])
        );
    end
    endgenerate
    generate
    for (__i=0; __i < CPU_CORES; __i = __i + 1) begin : disabled_tribe_features
        assign cores__atomic_request_out[__i] = 1'b0;
        assign cores__atomic_data_request_out[__i] = 1'b0;
        assign cores__atomic_complete_out[__i] = 1'b0;
        assign cores__debug_core_out[__i] = '0;
        assign cores__debug_mmu_out[__i] = '0;
        assign cores__debug_cache_out[__i] = '0;
        assign cores__debug_wb_out[__i] = '0;
        assign cores__debug_csr_out[__i] = '0;
        assign cores__debug_irq_out[__i] = '0;
        assign cores__debug_regs_out[__i] = '0;
        assign cores__debug_branch_out[__i] = '0;
        assign cores__debug_decode_out[__i] = '0;
        assign cores__sbi_send_ipi_out[__i] = 1'b0;
        assign cores__sbi_remote_fence_i_out[__i] = 1'b0;
        assign cores__sbi_remote_sfence_vma_out[__i] = 1'b0;
        assign cores__sbi_hart_mask_out[__i] = 32'b0;
        assign cores__sbi_hart_base_out[__i] = 32'b0;
    end
    endgenerate
    wire i_mem_cdc__fast_in__read_in[CPU_CORES];
    wire i_mem_cdc__fast_in__write_in[CPU_CORES];
    wire[31:0] i_mem_cdc__fast_in__addr_in[CPU_CORES];
    wire[31:0] i_mem_cdc__fast_in__write_data_in[CPU_CORES];
    wire[7:0] i_mem_cdc__fast_in__write_mask_in[CPU_CORES];
    wire i_mem_cdc__fast_in__cache_disable_in[CPU_CORES];
    wire[256-1:0] i_mem_cdc__fast_in__read_data_out[CPU_CORES];
    wire i_mem_cdc__fast_in__wait_out[CPU_CORES];
    wire i_mem_cdc__slow_out__read_out[CPU_CORES];
    wire i_mem_cdc__slow_out__write_out[CPU_CORES];
    wire[31:0] i_mem_cdc__slow_out__addr_out[CPU_CORES];
    wire[31:0] i_mem_cdc__slow_out__write_data_out[CPU_CORES];
    wire[7:0] i_mem_cdc__slow_out__write_mask_out[CPU_CORES];
    wire i_mem_cdc__slow_out__cache_disable_out[CPU_CORES];
    wire[256-1:0] i_mem_cdc__slow_out__read_data_in[CPU_CORES];
    wire i_mem_cdc__slow_out__wait_in[CPU_CORES];
    generate
    for (__i=0; __i < CPU_CORES; __i = __i + 1) begin
        L1MemFastToSlowCdc #(
        256
        ) i_mem_cdc (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .fast_in__read_in(i_mem_cdc__fast_in__read_in[__i])
        ,           .fast_in__write_in(i_mem_cdc__fast_in__write_in[__i])
        ,           .fast_in__addr_in(i_mem_cdc__fast_in__addr_in[__i])
        ,           .fast_in__write_data_in(i_mem_cdc__fast_in__write_data_in[__i])
        ,           .fast_in__write_mask_in(i_mem_cdc__fast_in__write_mask_in[__i])
        ,           .fast_in__cache_disable_in(i_mem_cdc__fast_in__cache_disable_in[__i])
        ,           .fast_in__read_data_out(i_mem_cdc__fast_in__read_data_out[__i])
        ,           .fast_in__wait_out(i_mem_cdc__fast_in__wait_out[__i])
        ,           .slow_out__read_out(i_mem_cdc__slow_out__read_out[__i])
        ,           .slow_out__write_out(i_mem_cdc__slow_out__write_out[__i])
        ,           .slow_out__addr_out(i_mem_cdc__slow_out__addr_out[__i])
        ,           .slow_out__write_data_out(i_mem_cdc__slow_out__write_data_out[__i])
        ,           .slow_out__write_mask_out(i_mem_cdc__slow_out__write_mask_out[__i])
        ,           .slow_out__cache_disable_out(i_mem_cdc__slow_out__cache_disable_out[__i])
        ,           .slow_out__read_data_in(i_mem_cdc__slow_out__read_data_in[__i])
        ,           .slow_out__wait_in(i_mem_cdc__slow_out__wait_in[__i])
        );
    end
    endgenerate
    wire d_mem_cdc__fast_in__read_in[CPU_CORES];
    wire d_mem_cdc__fast_in__write_in[CPU_CORES];
    wire[31:0] d_mem_cdc__fast_in__addr_in[CPU_CORES];
    wire[31:0] d_mem_cdc__fast_in__write_data_in[CPU_CORES];
    wire[7:0] d_mem_cdc__fast_in__write_mask_in[CPU_CORES];
    wire d_mem_cdc__fast_in__cache_disable_in[CPU_CORES];
    wire[256-1:0] d_mem_cdc__fast_in__read_data_out[CPU_CORES];
    wire d_mem_cdc__fast_in__wait_out[CPU_CORES];
    wire d_mem_cdc__slow_out__read_out[CPU_CORES];
    wire d_mem_cdc__slow_out__write_out[CPU_CORES];
    wire[31:0] d_mem_cdc__slow_out__addr_out[CPU_CORES];
    wire[31:0] d_mem_cdc__slow_out__write_data_out[CPU_CORES];
    wire[7:0] d_mem_cdc__slow_out__write_mask_out[CPU_CORES];
    wire d_mem_cdc__slow_out__cache_disable_out[CPU_CORES];
    wire[256-1:0] d_mem_cdc__slow_out__read_data_in[CPU_CORES];
    wire d_mem_cdc__slow_out__wait_in[CPU_CORES];
    generate
    for (__i=0; __i < CPU_CORES; __i = __i + 1) begin
        L1MemFastToSlowCdc #(
        256
        ) d_mem_cdc (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .fast_in__read_in(d_mem_cdc__fast_in__read_in[__i])
        ,           .fast_in__write_in(d_mem_cdc__fast_in__write_in[__i])
        ,           .fast_in__addr_in(d_mem_cdc__fast_in__addr_in[__i])
        ,           .fast_in__write_data_in(d_mem_cdc__fast_in__write_data_in[__i])
        ,           .fast_in__write_mask_in(d_mem_cdc__fast_in__write_mask_in[__i])
        ,           .fast_in__cache_disable_in(d_mem_cdc__fast_in__cache_disable_in[__i])
        ,           .fast_in__read_data_out(d_mem_cdc__fast_in__read_data_out[__i])
        ,           .fast_in__wait_out(d_mem_cdc__fast_in__wait_out[__i])
        ,           .slow_out__read_out(d_mem_cdc__slow_out__read_out[__i])
        ,           .slow_out__write_out(d_mem_cdc__slow_out__write_out[__i])
        ,           .slow_out__addr_out(d_mem_cdc__slow_out__addr_out[__i])
        ,           .slow_out__write_data_out(d_mem_cdc__slow_out__write_data_out[__i])
        ,           .slow_out__write_mask_out(d_mem_cdc__slow_out__write_mask_out[__i])
        ,           .slow_out__cache_disable_out(d_mem_cdc__slow_out__cache_disable_out[__i])
        ,           .slow_out__read_data_in(d_mem_cdc__slow_out__read_data_in[__i])
        ,           .slow_out__wait_in(d_mem_cdc__slow_out__wait_in[__i])
        );
    end
    endgenerate
    wire l2cache__i_mem_in__read_in[CPU_CORES];
    wire l2cache__i_mem_in__write_in[CPU_CORES];
    wire[31:0] l2cache__i_mem_in__addr_in[CPU_CORES];
    wire[31:0] l2cache__i_mem_in__write_data_in[CPU_CORES];
    wire[7:0] l2cache__i_mem_in__write_mask_in[CPU_CORES];
    wire l2cache__i_mem_in__cache_disable_in[CPU_CORES];
    wire[L2_PORT_WIDTH-1:0] l2cache__i_mem_in__read_data_out[CPU_CORES];
    wire l2cache__i_mem_in__wait_out[CPU_CORES];
    wire l2cache__d_mem_in__read_in[CPU_CORES];
    wire l2cache__d_mem_in__write_in[CPU_CORES];
    wire[31:0] l2cache__d_mem_in__addr_in[CPU_CORES];
    wire[31:0] l2cache__d_mem_in__write_data_in[CPU_CORES];
    wire[7:0] l2cache__d_mem_in__write_mask_in[CPU_CORES];
    wire l2cache__d_mem_in__cache_disable_in[CPU_CORES];
    wire[L2_PORT_WIDTH-1:0] l2cache__d_mem_in__read_data_out[CPU_CORES];
    wire l2cache__d_mem_in__wait_out[CPU_CORES];
    wire[31:0] l2cache__memory_base_in;
    wire[31:0] l2cache__memory_size_in;
    wire[31:0] l2cache__mem_region_size_in[L2_PORT_COUNT];
    wire l2cache__mem_region_uncached_in[L2_PORT_COUNT];
    wire l2cache__axi_in__awvalid_in[L2_PORT_COUNT];
    wire l2cache__axi_in__awready_out[L2_PORT_COUNT];
    wire[L2_ADDRESS_BITS-1:0] l2cache__axi_in__awaddr_in[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_in__awid_in[L2_PORT_COUNT];
    wire l2cache__axi_in__wvalid_in[L2_PORT_COUNT];
    wire l2cache__axi_in__wready_out[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH-1:0] l2cache__axi_in__wdata_in[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH/'h8-1:0] l2cache__axi_in__wstrb_in[L2_PORT_COUNT];
    wire l2cache__axi_in__wlast_in[L2_PORT_COUNT];
    wire l2cache__axi_in__bvalid_out[L2_PORT_COUNT];
    wire l2cache__axi_in__bready_in[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_in__bid_out[L2_PORT_COUNT];
    wire l2cache__axi_in__arvalid_in[L2_PORT_COUNT];
    wire l2cache__axi_in__arready_out[L2_PORT_COUNT];
    wire[L2_ADDRESS_BITS-1:0] l2cache__axi_in__araddr_in[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_in__arid_in[L2_PORT_COUNT];
    wire l2cache__axi_in__rvalid_out[L2_PORT_COUNT];
    wire l2cache__axi_in__rready_in[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH-1:0] l2cache__axi_in__rdata_out[L2_PORT_COUNT];
    wire l2cache__axi_in__rlast_out[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_in__rid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__awvalid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__awready_in[L2_PORT_COUNT];
    wire[L2_RAM_ADDRESS_BITS-1:0] l2cache__axi_out__awaddr_out[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_out__awid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__wvalid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__wready_in[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH-1:0] l2cache__axi_out__wdata_out[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH/'h8-1:0] l2cache__axi_out__wstrb_out[L2_PORT_COUNT];
    wire l2cache__axi_out__wlast_out[L2_PORT_COUNT];
    wire l2cache__axi_out__bvalid_in[L2_PORT_COUNT];
    wire l2cache__axi_out__bready_out[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_out__bid_in[L2_PORT_COUNT];
    wire l2cache__axi_out__arvalid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__arready_in[L2_PORT_COUNT];
    wire[L2_RAM_ADDRESS_BITS-1:0] l2cache__axi_out__araddr_out[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_out__arid_out[L2_PORT_COUNT];
    wire l2cache__axi_out__rvalid_in[L2_PORT_COUNT];
    wire l2cache__axi_out__rready_out[L2_PORT_COUNT];
    wire[L2_PORT_WIDTH-1:0] l2cache__axi_out__rdata_in[L2_PORT_COUNT];
    wire l2cache__axi_out__rlast_in[L2_PORT_COUNT];
    wire[4-1:0] l2cache__axi_out__rid_in[L2_PORT_COUNT];
    wire l2cache__debugen_in;
    L2Cache #(
        L2_TOTAL_SIZE
,       L2_PORT_WIDTH
,       L2_LINE_SIZE
,       L2_WAYS
,       L2_ADDRESS_BITS
,       L2_RAM_ADDRESS_BITS
,       L2_PORT_COUNT
,       CPU_CORES
    ) l2cache (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .i_mem_in__read_in(l2cache__i_mem_in__read_in)
,       .i_mem_in__write_in(l2cache__i_mem_in__write_in)
,       .i_mem_in__addr_in(l2cache__i_mem_in__addr_in)
,       .i_mem_in__write_data_in(l2cache__i_mem_in__write_data_in)
,       .i_mem_in__write_mask_in(l2cache__i_mem_in__write_mask_in)
,       .i_mem_in__cache_disable_in(l2cache__i_mem_in__cache_disable_in)
,       .i_mem_in__read_data_out(l2cache__i_mem_in__read_data_out)
,       .i_mem_in__wait_out(l2cache__i_mem_in__wait_out)
,       .d_mem_in__read_in(l2cache__d_mem_in__read_in)
,       .d_mem_in__write_in(l2cache__d_mem_in__write_in)
,       .d_mem_in__addr_in(l2cache__d_mem_in__addr_in)
,       .d_mem_in__write_data_in(l2cache__d_mem_in__write_data_in)
,       .d_mem_in__write_mask_in(l2cache__d_mem_in__write_mask_in)
,       .d_mem_in__cache_disable_in(l2cache__d_mem_in__cache_disable_in)
,       .d_mem_in__read_data_out(l2cache__d_mem_in__read_data_out)
,       .d_mem_in__wait_out(l2cache__d_mem_in__wait_out)
,       .memory_base_in(l2cache__memory_base_in)
,       .memory_size_in(l2cache__memory_size_in)
,       .mem_region_size_in(l2cache__mem_region_size_in)
,       .mem_region_uncached_in(l2cache__mem_region_uncached_in)
,       .axi_in__awvalid_in(l2cache__axi_in__awvalid_in)
,       .axi_in__awready_out(l2cache__axi_in__awready_out)
,       .axi_in__awaddr_in(l2cache__axi_in__awaddr_in)
,       .axi_in__awid_in(l2cache__axi_in__awid_in)
,       .axi_in__wvalid_in(l2cache__axi_in__wvalid_in)
,       .axi_in__wready_out(l2cache__axi_in__wready_out)
,       .axi_in__wdata_in(l2cache__axi_in__wdata_in)
,       .axi_in__wstrb_in(l2cache__axi_in__wstrb_in)
,       .axi_in__wlast_in(l2cache__axi_in__wlast_in)
,       .axi_in__bvalid_out(l2cache__axi_in__bvalid_out)
,       .axi_in__bready_in(l2cache__axi_in__bready_in)
,       .axi_in__bid_out(l2cache__axi_in__bid_out)
,       .axi_in__arvalid_in(l2cache__axi_in__arvalid_in)
,       .axi_in__arready_out(l2cache__axi_in__arready_out)
,       .axi_in__araddr_in(l2cache__axi_in__araddr_in)
,       .axi_in__arid_in(l2cache__axi_in__arid_in)
,       .axi_in__rvalid_out(l2cache__axi_in__rvalid_out)
,       .axi_in__rready_in(l2cache__axi_in__rready_in)
,       .axi_in__rdata_out(l2cache__axi_in__rdata_out)
,       .axi_in__rlast_out(l2cache__axi_in__rlast_out)
,       .axi_in__rid_out(l2cache__axi_in__rid_out)
,       .axi_out__awvalid_out(l2cache__axi_out__awvalid_out)
,       .axi_out__awready_in(l2cache__axi_out__awready_in)
,       .axi_out__awaddr_out(l2cache__axi_out__awaddr_out)
,       .axi_out__awid_out(l2cache__axi_out__awid_out)
,       .axi_out__wvalid_out(l2cache__axi_out__wvalid_out)
,       .axi_out__wready_in(l2cache__axi_out__wready_in)
,       .axi_out__wdata_out(l2cache__axi_out__wdata_out)
,       .axi_out__wstrb_out(l2cache__axi_out__wstrb_out)
,       .axi_out__wlast_out(l2cache__axi_out__wlast_out)
,       .axi_out__bvalid_in(l2cache__axi_out__bvalid_in)
,       .axi_out__bready_out(l2cache__axi_out__bready_out)
,       .axi_out__bid_in(l2cache__axi_out__bid_in)
,       .axi_out__arvalid_out(l2cache__axi_out__arvalid_out)
,       .axi_out__arready_in(l2cache__axi_out__arready_in)
,       .axi_out__araddr_out(l2cache__axi_out__araddr_out)
,       .axi_out__arid_out(l2cache__axi_out__arid_out)
,       .axi_out__rvalid_in(l2cache__axi_out__rvalid_in)
,       .axi_out__rready_out(l2cache__axi_out__rready_out)
,       .axi_out__rdata_in(l2cache__axi_out__rdata_in)
,       .axi_out__rlast_in(l2cache__axi_out__rlast_in)
,       .axi_out__rid_in(l2cache__axi_out__rid_in)
,       .debugen_in(l2cache__debugen_in)
    );
    wire axi_in_cdc__fast_in__awvalid_in[4];
    wire axi_in_cdc__fast_in__awready_out[4];
    wire[32-1:0] axi_in_cdc__fast_in__awaddr_in[4];
    wire[4-1:0] axi_in_cdc__fast_in__awid_in[4];
    wire axi_in_cdc__fast_in__wvalid_in[4];
    wire axi_in_cdc__fast_in__wready_out[4];
    wire[256-1:0] axi_in_cdc__fast_in__wdata_in[4];
    wire[256/'h8-1:0] axi_in_cdc__fast_in__wstrb_in[4];
    wire axi_in_cdc__fast_in__wlast_in[4];
    wire axi_in_cdc__fast_in__bvalid_out[4];
    wire axi_in_cdc__fast_in__bready_in[4];
    wire[4-1:0] axi_in_cdc__fast_in__bid_out[4];
    wire axi_in_cdc__fast_in__arvalid_in[4];
    wire axi_in_cdc__fast_in__arready_out[4];
    wire[32-1:0] axi_in_cdc__fast_in__araddr_in[4];
    wire[4-1:0] axi_in_cdc__fast_in__arid_in[4];
    wire axi_in_cdc__fast_in__rvalid_out[4];
    wire axi_in_cdc__fast_in__rready_in[4];
    wire[256-1:0] axi_in_cdc__fast_in__rdata_out[4];
    wire axi_in_cdc__fast_in__rlast_out[4];
    wire[4-1:0] axi_in_cdc__fast_in__rid_out[4];
    wire axi_in_cdc__slow_out__awvalid_out[4];
    wire axi_in_cdc__slow_out__awready_in[4];
    wire[32-1:0] axi_in_cdc__slow_out__awaddr_out[4];
    wire[4-1:0] axi_in_cdc__slow_out__awid_out[4];
    wire axi_in_cdc__slow_out__wvalid_out[4];
    wire axi_in_cdc__slow_out__wready_in[4];
    wire[256-1:0] axi_in_cdc__slow_out__wdata_out[4];
    wire[256/'h8-1:0] axi_in_cdc__slow_out__wstrb_out[4];
    wire axi_in_cdc__slow_out__wlast_out[4];
    wire axi_in_cdc__slow_out__bvalid_in[4];
    wire axi_in_cdc__slow_out__bready_out[4];
    wire[4-1:0] axi_in_cdc__slow_out__bid_in[4];
    wire axi_in_cdc__slow_out__arvalid_out[4];
    wire axi_in_cdc__slow_out__arready_in[4];
    wire[32-1:0] axi_in_cdc__slow_out__araddr_out[4];
    wire[4-1:0] axi_in_cdc__slow_out__arid_out[4];
    wire axi_in_cdc__slow_out__rvalid_in[4];
    wire axi_in_cdc__slow_out__rready_out[4];
    wire[256-1:0] axi_in_cdc__slow_out__rdata_in[4];
    wire axi_in_cdc__slow_out__rlast_in[4];
    wire[4-1:0] axi_in_cdc__slow_out__rid_in[4];
    generate
    for (__i=0; __i < 4; __i = __i + 1) begin
        Axi4FastToSlowCdc #(
        32
,       4
,       256
        ) axi_in_cdc (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .fast_in__awvalid_in(axi_in_cdc__fast_in__awvalid_in[__i])
        ,           .fast_in__awready_out(axi_in_cdc__fast_in__awready_out[__i])
        ,           .fast_in__awaddr_in(axi_in_cdc__fast_in__awaddr_in[__i])
        ,           .fast_in__awid_in(axi_in_cdc__fast_in__awid_in[__i])
        ,           .fast_in__wvalid_in(axi_in_cdc__fast_in__wvalid_in[__i])
        ,           .fast_in__wready_out(axi_in_cdc__fast_in__wready_out[__i])
        ,           .fast_in__wdata_in(axi_in_cdc__fast_in__wdata_in[__i])
        ,           .fast_in__wstrb_in(axi_in_cdc__fast_in__wstrb_in[__i])
        ,           .fast_in__wlast_in(axi_in_cdc__fast_in__wlast_in[__i])
        ,           .fast_in__bvalid_out(axi_in_cdc__fast_in__bvalid_out[__i])
        ,           .fast_in__bready_in(axi_in_cdc__fast_in__bready_in[__i])
        ,           .fast_in__bid_out(axi_in_cdc__fast_in__bid_out[__i])
        ,           .fast_in__arvalid_in(axi_in_cdc__fast_in__arvalid_in[__i])
        ,           .fast_in__arready_out(axi_in_cdc__fast_in__arready_out[__i])
        ,           .fast_in__araddr_in(axi_in_cdc__fast_in__araddr_in[__i])
        ,           .fast_in__arid_in(axi_in_cdc__fast_in__arid_in[__i])
        ,           .fast_in__rvalid_out(axi_in_cdc__fast_in__rvalid_out[__i])
        ,           .fast_in__rready_in(axi_in_cdc__fast_in__rready_in[__i])
        ,           .fast_in__rdata_out(axi_in_cdc__fast_in__rdata_out[__i])
        ,           .fast_in__rlast_out(axi_in_cdc__fast_in__rlast_out[__i])
        ,           .fast_in__rid_out(axi_in_cdc__fast_in__rid_out[__i])
        ,           .slow_out__awvalid_out(axi_in_cdc__slow_out__awvalid_out[__i])
        ,           .slow_out__awready_in(axi_in_cdc__slow_out__awready_in[__i])
        ,           .slow_out__awaddr_out(axi_in_cdc__slow_out__awaddr_out[__i])
        ,           .slow_out__awid_out(axi_in_cdc__slow_out__awid_out[__i])
        ,           .slow_out__wvalid_out(axi_in_cdc__slow_out__wvalid_out[__i])
        ,           .slow_out__wready_in(axi_in_cdc__slow_out__wready_in[__i])
        ,           .slow_out__wdata_out(axi_in_cdc__slow_out__wdata_out[__i])
        ,           .slow_out__wstrb_out(axi_in_cdc__slow_out__wstrb_out[__i])
        ,           .slow_out__wlast_out(axi_in_cdc__slow_out__wlast_out[__i])
        ,           .slow_out__bvalid_in(axi_in_cdc__slow_out__bvalid_in[__i])
        ,           .slow_out__bready_out(axi_in_cdc__slow_out__bready_out[__i])
        ,           .slow_out__bid_in(axi_in_cdc__slow_out__bid_in[__i])
        ,           .slow_out__arvalid_out(axi_in_cdc__slow_out__arvalid_out[__i])
        ,           .slow_out__arready_in(axi_in_cdc__slow_out__arready_in[__i])
        ,           .slow_out__araddr_out(axi_in_cdc__slow_out__araddr_out[__i])
        ,           .slow_out__arid_out(axi_in_cdc__slow_out__arid_out[__i])
        ,           .slow_out__rvalid_in(axi_in_cdc__slow_out__rvalid_in[__i])
        ,           .slow_out__rready_out(axi_in_cdc__slow_out__rready_out[__i])
        ,           .slow_out__rdata_in(axi_in_cdc__slow_out__rdata_in[__i])
        ,           .slow_out__rlast_in(axi_in_cdc__slow_out__rlast_in[__i])
        ,           .slow_out__rid_in(axi_in_cdc__slow_out__rid_in[__i])
        );
    end
    endgenerate
    wire axi_out_cdc__slow_in__awvalid_in[4];
    wire axi_out_cdc__slow_in__awready_out[4];
    wire[31-1:0] axi_out_cdc__slow_in__awaddr_in[4];
    wire[4-1:0] axi_out_cdc__slow_in__awid_in[4];
    wire axi_out_cdc__slow_in__wvalid_in[4];
    wire axi_out_cdc__slow_in__wready_out[4];
    wire[256-1:0] axi_out_cdc__slow_in__wdata_in[4];
    wire[256/'h8-1:0] axi_out_cdc__slow_in__wstrb_in[4];
    wire axi_out_cdc__slow_in__wlast_in[4];
    wire axi_out_cdc__slow_in__bvalid_out[4];
    wire axi_out_cdc__slow_in__bready_in[4];
    wire[4-1:0] axi_out_cdc__slow_in__bid_out[4];
    wire axi_out_cdc__slow_in__arvalid_in[4];
    wire axi_out_cdc__slow_in__arready_out[4];
    wire[31-1:0] axi_out_cdc__slow_in__araddr_in[4];
    wire[4-1:0] axi_out_cdc__slow_in__arid_in[4];
    wire axi_out_cdc__slow_in__rvalid_out[4];
    wire axi_out_cdc__slow_in__rready_in[4];
    wire[256-1:0] axi_out_cdc__slow_in__rdata_out[4];
    wire axi_out_cdc__slow_in__rlast_out[4];
    wire[4-1:0] axi_out_cdc__slow_in__rid_out[4];
    wire axi_out_cdc__fast_out__awvalid_out[4];
    wire axi_out_cdc__fast_out__awready_in[4];
    wire[31-1:0] axi_out_cdc__fast_out__awaddr_out[4];
    wire[4-1:0] axi_out_cdc__fast_out__awid_out[4];
    wire axi_out_cdc__fast_out__wvalid_out[4];
    wire axi_out_cdc__fast_out__wready_in[4];
    wire[256-1:0] axi_out_cdc__fast_out__wdata_out[4];
    wire[256/'h8-1:0] axi_out_cdc__fast_out__wstrb_out[4];
    wire axi_out_cdc__fast_out__wlast_out[4];
    wire axi_out_cdc__fast_out__bvalid_in[4];
    wire axi_out_cdc__fast_out__bready_out[4];
    wire[4-1:0] axi_out_cdc__fast_out__bid_in[4];
    wire axi_out_cdc__fast_out__arvalid_out[4];
    wire axi_out_cdc__fast_out__arready_in[4];
    wire[31-1:0] axi_out_cdc__fast_out__araddr_out[4];
    wire[4-1:0] axi_out_cdc__fast_out__arid_out[4];
    wire axi_out_cdc__fast_out__rvalid_in[4];
    wire axi_out_cdc__fast_out__rready_out[4];
    wire[256-1:0] axi_out_cdc__fast_out__rdata_in[4];
    wire axi_out_cdc__fast_out__rlast_in[4];
    wire[4-1:0] axi_out_cdc__fast_out__rid_in[4];
    generate
    for (__i=0; __i < 4; __i = __i + 1) begin
        Axi4SlowToFastCdc #(
        31
,       4
,       256
        ) axi_out_cdc (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .slow_in__awvalid_in(axi_out_cdc__slow_in__awvalid_in[__i])
        ,           .slow_in__awready_out(axi_out_cdc__slow_in__awready_out[__i])
        ,           .slow_in__awaddr_in(axi_out_cdc__slow_in__awaddr_in[__i])
        ,           .slow_in__awid_in(axi_out_cdc__slow_in__awid_in[__i])
        ,           .slow_in__wvalid_in(axi_out_cdc__slow_in__wvalid_in[__i])
        ,           .slow_in__wready_out(axi_out_cdc__slow_in__wready_out[__i])
        ,           .slow_in__wdata_in(axi_out_cdc__slow_in__wdata_in[__i])
        ,           .slow_in__wstrb_in(axi_out_cdc__slow_in__wstrb_in[__i])
        ,           .slow_in__wlast_in(axi_out_cdc__slow_in__wlast_in[__i])
        ,           .slow_in__bvalid_out(axi_out_cdc__slow_in__bvalid_out[__i])
        ,           .slow_in__bready_in(axi_out_cdc__slow_in__bready_in[__i])
        ,           .slow_in__bid_out(axi_out_cdc__slow_in__bid_out[__i])
        ,           .slow_in__arvalid_in(axi_out_cdc__slow_in__arvalid_in[__i])
        ,           .slow_in__arready_out(axi_out_cdc__slow_in__arready_out[__i])
        ,           .slow_in__araddr_in(axi_out_cdc__slow_in__araddr_in[__i])
        ,           .slow_in__arid_in(axi_out_cdc__slow_in__arid_in[__i])
        ,           .slow_in__rvalid_out(axi_out_cdc__slow_in__rvalid_out[__i])
        ,           .slow_in__rready_in(axi_out_cdc__slow_in__rready_in[__i])
        ,           .slow_in__rdata_out(axi_out_cdc__slow_in__rdata_out[__i])
        ,           .slow_in__rlast_out(axi_out_cdc__slow_in__rlast_out[__i])
        ,           .slow_in__rid_out(axi_out_cdc__slow_in__rid_out[__i])
        ,           .fast_out__awvalid_out(axi_out_cdc__fast_out__awvalid_out[__i])
        ,           .fast_out__awready_in(axi_out_cdc__fast_out__awready_in[__i])
        ,           .fast_out__awaddr_out(axi_out_cdc__fast_out__awaddr_out[__i])
        ,           .fast_out__awid_out(axi_out_cdc__fast_out__awid_out[__i])
        ,           .fast_out__wvalid_out(axi_out_cdc__fast_out__wvalid_out[__i])
        ,           .fast_out__wready_in(axi_out_cdc__fast_out__wready_in[__i])
        ,           .fast_out__wdata_out(axi_out_cdc__fast_out__wdata_out[__i])
        ,           .fast_out__wstrb_out(axi_out_cdc__fast_out__wstrb_out[__i])
        ,           .fast_out__wlast_out(axi_out_cdc__fast_out__wlast_out[__i])
        ,           .fast_out__bvalid_in(axi_out_cdc__fast_out__bvalid_in[__i])
        ,           .fast_out__bready_out(axi_out_cdc__fast_out__bready_out[__i])
        ,           .fast_out__bid_in(axi_out_cdc__fast_out__bid_in[__i])
        ,           .fast_out__arvalid_out(axi_out_cdc__fast_out__arvalid_out[__i])
        ,           .fast_out__arready_in(axi_out_cdc__fast_out__arready_in[__i])
        ,           .fast_out__araddr_out(axi_out_cdc__fast_out__araddr_out[__i])
        ,           .fast_out__arid_out(axi_out_cdc__fast_out__arid_out[__i])
        ,           .fast_out__rvalid_in(axi_out_cdc__fast_out__rvalid_in[__i])
        ,           .fast_out__rready_out(axi_out_cdc__fast_out__rready_out[__i])
        ,           .fast_out__rdata_in(axi_out_cdc__fast_out__rdata_in[__i])
        ,           .fast_out__rlast_in(axi_out_cdc__fast_out__rlast_in[__i])
        ,           .fast_out__rid_in(axi_out_cdc__fast_out__rid_in[__i])
        );
    end
    endgenerate

    // tmp variables
    L1PeerStoreState peer_store_reg_tmp[CPU_CORES];
    logic atomic_owner_valid_reg_tmp;
    logic[ATOMIC_OWNER_BITS-1:0] atomic_owner_reg_tmp;
    logic[ATOMIC_OWNER_BITS-1:0] atomic_rr_reg_tmp;


    always_comb begin : peer_invalidate_comb_func  // peer_invalidate_comb_func
        logic[31:0] target;
        logic[31:0] source;
        for (target='h0;target < CPU_CORES;target=target+1) begin
            peer_invalidate_comb[target] = 0;
            for (source='h0;source < CPU_CORES;source=source+1) begin
                if ((target != source) && peer_store_reg[source].valid) begin
                    if (peer_invalidate_comb[target].valid) begin
                        peer_invalidate_comb[target].valid = unsigned'(1'(0));
                        peer_invalidate_comb[target].full = unsigned'(1'(1));
                    end
                    else begin
                        if (!peer_invalidate_comb[target].full) begin
                            peer_invalidate_comb[target].valid = unsigned'(1'(1));
                            peer_invalidate_comb[target].addr = unsigned'(32'(unsigned'(32'(peer_store_reg[source].addr))));
                        end
                    end
                end
            end
        end
    end

    function logic sbi_hart_selected (
        input logic[31:0] mask
,       input logic[31:0] base
,       input logic[31:0] target
    );
        if (base == 'hFFFFFFFF) begin
            return 1;
        end
        return (target>=base && ((target - base) < 'h20)) && (((((mask >>> ((target - base)))) & 'h1)) != 'h0);
    endfunction

    always_comb begin : sbi_ipi_targets_comb_func  // sbi_ipi_targets_comb_func
        logic[31:0] source;
        logic[31:0] target;
        sbi_ipi_targets_comb = 'h0;
        for (source='h0;source < CPU_CORES;source=source+1) begin
            for (target='h0;target < CPU_CORES;target=target+1) begin
                if (cores__sbi_send_ipi_out[source] && sbi_hart_selected(cores__sbi_hart_mask_out[source], cores__sbi_hart_base_out[source], target)) begin
                    sbi_ipi_targets_comb[target] = 'h1;
                end
            end
        end
    end

    always_comb begin : sbi_fence_i_targets_comb_func  // sbi_fence_i_targets_comb_func
        logic[31:0] source;
        logic[31:0] target;
        sbi_fence_i_targets_comb = 'h0;
        for (source='h0;source < CPU_CORES;source=source+1) begin
            for (target='h0;target < CPU_CORES;target=target+1) begin
                if (cores__sbi_remote_fence_i_out[source] && sbi_hart_selected(cores__sbi_hart_mask_out[source], cores__sbi_hart_base_out[source], target)) begin
                    sbi_fence_i_targets_comb[target] = 'h1;
                end
            end
        end
    end

    always_comb begin : sbi_sfence_targets_comb_func  // sbi_sfence_targets_comb_func
        logic[31:0] source;
        logic[31:0] target;
        sbi_sfence_targets_comb = 'h0;
        for (source='h0;source < CPU_CORES;source=source+1) begin
            for (target='h0;target < CPU_CORES;target=target+1) begin
                if (cores__sbi_remote_sfence_vma_out[source] && sbi_hart_selected(cores__sbi_hart_mask_out[source], cores__sbi_hart_base_out[source], target)) begin
                    sbi_sfence_targets_comb[target] = 'h1;
                end
            end
        end
    end

    always_comb begin : atomic_grant_comb_func  // atomic_grant_comb_func
        atomic_grant_comb = 'h0;
        if (atomic_owner_valid_reg) begin
            atomic_grant_comb[unsigned'(32'(atomic_owner_reg))] = 'h1;
        end
    end

    always_comb begin : atomic_data_access_comb_func  // atomic_data_access_comb_func
        logic[31:0] i;
        atomic_data_access_comb = 'h0;
        if (atomic_owner_valid_reg) begin
            atomic_data_access_comb[unsigned'(32'(atomic_owner_reg))] = 'h1;
        end
        else begin
            for (i='h0;i < CPU_CORES;i=i+1) begin
                atomic_data_access_comb[i] = 'h1;
            end
        end
    end

    generate  // _assign
        genvar gi;
        genvar gregion;
        assign l2cache__memory_base_in = memory_base_in;
        assign l2cache__memory_size_in = memory_size_in;
        for (gi='h0;gi < 'h4;gi=gi+1) begin
            assign l2cache__mem_region_size_in[gi] = mem_region_size_in[gi];
            assign axi_in_cdc__fast_in__awvalid_in[gi] = axi_in__awvalid_in[gi];
            assign axi_in_cdc__fast_in__awaddr_in[gi] = unsigned'(32'(axi_in__awaddr_in[gi]));
            assign axi_in_cdc__fast_in__awid_in[gi] = unsigned'(4'(axi_in__awid_in[gi]));
            assign axi_in_cdc__fast_in__wvalid_in[gi] = axi_in__wvalid_in[gi];
            assign axi_in_cdc__fast_in__wdata_in[gi] = axi_in__wdata_in[gi];
            assign axi_in_cdc__fast_in__wstrb_in[gi] = axi_in__wstrb_in[gi];
            assign axi_in_cdc__fast_in__wlast_in[gi] = axi_in__wlast_in[gi];
            assign axi_in_cdc__fast_in__bready_in[gi] = axi_in__bready_in[gi];
            assign axi_in_cdc__fast_in__arvalid_in[gi] = axi_in__arvalid_in[gi];
            assign axi_in_cdc__fast_in__araddr_in[gi] = unsigned'(32'(axi_in__araddr_in[gi]));
            assign axi_in_cdc__fast_in__arid_in[gi] = unsigned'(4'(axi_in__arid_in[gi]));
            assign axi_in_cdc__fast_in__rready_in[gi] = axi_in__rready_in[gi];
            assign axi_in__awready_out[gi] = axi_in_cdc__fast_in__awready_out[gi];
            assign axi_in__wready_out[gi] = axi_in_cdc__fast_in__wready_out[gi];
            assign axi_in__bvalid_out[gi] = axi_in_cdc__fast_in__bvalid_out[gi];
            assign axi_in__bid_out[gi] = unsigned'(4'(axi_in_cdc__fast_in__bid_out[gi]));
            assign axi_in__arready_out[gi] = axi_in_cdc__fast_in__arready_out[gi];
            assign axi_in__rvalid_out[gi] = axi_in_cdc__fast_in__rvalid_out[gi];
            assign axi_in__rdata_out[gi] = axi_in_cdc__fast_in__rdata_out[gi];
            assign axi_in__rlast_out[gi] = axi_in_cdc__fast_in__rlast_out[gi];
            assign axi_in__rid_out[gi] = unsigned'(4'(axi_in_cdc__fast_in__rid_out[gi]));
            assign l2cache__axi_in__awvalid_in[gi] = axi_in_cdc__slow_out__awvalid_out[gi];
            assign l2cache__axi_in__awaddr_in[gi] = unsigned'(32'(axi_in_cdc__slow_out__awaddr_out[gi]));
            assign l2cache__axi_in__awid_in[gi] = unsigned'(4'(axi_in_cdc__slow_out__awid_out[gi]));
            assign l2cache__axi_in__wvalid_in[gi] = axi_in_cdc__slow_out__wvalid_out[gi];
            assign l2cache__axi_in__wdata_in[gi] = axi_in_cdc__slow_out__wdata_out[gi];
            assign l2cache__axi_in__wstrb_in[gi] = axi_in_cdc__slow_out__wstrb_out[gi];
            assign l2cache__axi_in__wlast_in[gi] = axi_in_cdc__slow_out__wlast_out[gi];
            assign l2cache__axi_in__bready_in[gi] = axi_in_cdc__slow_out__bready_out[gi];
            assign l2cache__axi_in__arvalid_in[gi] = axi_in_cdc__slow_out__arvalid_out[gi];
            assign l2cache__axi_in__araddr_in[gi] = unsigned'(32'(axi_in_cdc__slow_out__araddr_out[gi]));
            assign l2cache__axi_in__arid_in[gi] = unsigned'(4'(axi_in_cdc__slow_out__arid_out[gi]));
            assign l2cache__axi_in__rready_in[gi] = axi_in_cdc__slow_out__rready_out[gi];
            assign axi_in_cdc__slow_out__awready_in[gi] = l2cache__axi_in__awready_out[gi];
            assign axi_in_cdc__slow_out__wready_in[gi] = l2cache__axi_in__wready_out[gi];
            assign axi_in_cdc__slow_out__bvalid_in[gi] = l2cache__axi_in__bvalid_out[gi];
            assign axi_in_cdc__slow_out__bid_in[gi] = unsigned'(4'(l2cache__axi_in__bid_out[gi]));
            assign axi_in_cdc__slow_out__arready_in[gi] = l2cache__axi_in__arready_out[gi];
            assign axi_in_cdc__slow_out__rvalid_in[gi] = l2cache__axi_in__rvalid_out[gi];
            assign axi_in_cdc__slow_out__rdata_in[gi] = l2cache__axi_in__rdata_out[gi];
            assign axi_in_cdc__slow_out__rlast_in[gi] = l2cache__axi_in__rlast_out[gi];
            assign axi_in_cdc__slow_out__rid_in[gi] = unsigned'(4'(l2cache__axi_in__rid_out[gi]));
            assign axi_out_cdc__slow_in__awvalid_in[gi] = l2cache__axi_out__awvalid_out[gi];
            assign axi_out_cdc__slow_in__awaddr_in[gi] = unsigned'(31'(l2cache__axi_out__awaddr_out[gi]));
            assign axi_out_cdc__slow_in__awid_in[gi] = unsigned'(4'(l2cache__axi_out__awid_out[gi]));
            assign axi_out_cdc__slow_in__wvalid_in[gi] = l2cache__axi_out__wvalid_out[gi];
            assign axi_out_cdc__slow_in__wdata_in[gi] = l2cache__axi_out__wdata_out[gi];
            assign axi_out_cdc__slow_in__wstrb_in[gi] = l2cache__axi_out__wstrb_out[gi];
            assign axi_out_cdc__slow_in__wlast_in[gi] = l2cache__axi_out__wlast_out[gi];
            assign axi_out_cdc__slow_in__bready_in[gi] = l2cache__axi_out__bready_out[gi];
            assign axi_out_cdc__slow_in__arvalid_in[gi] = l2cache__axi_out__arvalid_out[gi];
            assign axi_out_cdc__slow_in__araddr_in[gi] = unsigned'(31'(l2cache__axi_out__araddr_out[gi]));
            assign axi_out_cdc__slow_in__arid_in[gi] = unsigned'(4'(l2cache__axi_out__arid_out[gi]));
            assign axi_out_cdc__slow_in__rready_in[gi] = l2cache__axi_out__rready_out[gi];
            assign l2cache__axi_out__awready_in[gi] = axi_out_cdc__slow_in__awready_out[gi];
            assign l2cache__axi_out__wready_in[gi] = axi_out_cdc__slow_in__wready_out[gi];
            assign l2cache__axi_out__bvalid_in[gi] = axi_out_cdc__slow_in__bvalid_out[gi];
            assign l2cache__axi_out__bid_in[gi] = unsigned'(4'(axi_out_cdc__slow_in__bid_out[gi]));
            assign l2cache__axi_out__arready_in[gi] = axi_out_cdc__slow_in__arready_out[gi];
            assign l2cache__axi_out__rvalid_in[gi] = axi_out_cdc__slow_in__rvalid_out[gi];
            assign l2cache__axi_out__rdata_in[gi] = axi_out_cdc__slow_in__rdata_out[gi];
            assign l2cache__axi_out__rlast_in[gi] = axi_out_cdc__slow_in__rlast_out[gi];
            assign l2cache__axi_out__rid_in[gi] = unsigned'(4'(axi_out_cdc__slow_in__rid_out[gi]));
            assign axi_out__awvalid_out[gi] = axi_out_cdc__fast_out__awvalid_out[gi];
            assign axi_out__awaddr_out[gi] = unsigned'(31'(axi_out_cdc__fast_out__awaddr_out[gi]));
            assign axi_out__awid_out[gi] = unsigned'(4'(axi_out_cdc__fast_out__awid_out[gi]));
            assign axi_out__wvalid_out[gi] = axi_out_cdc__fast_out__wvalid_out[gi];
            assign axi_out__wdata_out[gi] = axi_out_cdc__fast_out__wdata_out[gi];
            assign axi_out__wstrb_out[gi] = axi_out_cdc__fast_out__wstrb_out[gi];
            assign axi_out__wlast_out[gi] = axi_out_cdc__fast_out__wlast_out[gi];
            assign axi_out__bready_out[gi] = axi_out_cdc__fast_out__bready_out[gi];
            assign axi_out__arvalid_out[gi] = axi_out_cdc__fast_out__arvalid_out[gi];
            assign axi_out__araddr_out[gi] = unsigned'(31'(axi_out_cdc__fast_out__araddr_out[gi]));
            assign axi_out__arid_out[gi] = unsigned'(4'(axi_out_cdc__fast_out__arid_out[gi]));
            assign axi_out__rready_out[gi] = axi_out_cdc__fast_out__rready_out[gi];
            assign axi_out_cdc__fast_out__awready_in[gi] = axi_out__awready_in[gi];
            assign axi_out_cdc__fast_out__wready_in[gi] = axi_out__wready_in[gi];
            assign axi_out_cdc__fast_out__bvalid_in[gi] = axi_out__bvalid_in[gi];
            assign axi_out_cdc__fast_out__bid_in[gi] = unsigned'(4'(axi_out__bid_in[gi]));
            assign axi_out_cdc__fast_out__arready_in[gi] = axi_out__arready_in[gi];
            assign axi_out_cdc__fast_out__rvalid_in[gi] = axi_out__rvalid_in[gi];
            assign axi_out_cdc__fast_out__rdata_in[gi] = axi_out__rdata_in[gi];
            assign axi_out_cdc__fast_out__rlast_in[gi] = axi_out__rlast_in[gi];
            assign axi_out_cdc__fast_out__rid_in[gi] = unsigned'(4'(axi_out__rid_in[gi]));
        end
        assign l2cache__mem_region_uncached_in['h0] = 0;
        assign l2cache__mem_region_uncached_in['h1] = 0;
        assign l2cache__mem_region_uncached_in['h2] = 0;
        assign l2cache__mem_region_uncached_in['h3] = 1;
        assign l2cache__debugen_in=debugen_in;
        for (gi='h0;gi < CPU_CORES;gi=gi+1) begin
            assign cores__debugen_in[gi]=debugen_in;
            assign cores__reset_pc_in[gi] = reset_pc_in;
            assign cores__boot_hartid_in[gi] = unsigned'(32'(boot_hartid_in)) + unsigned'(32'(gi));
            assign cores__boot_dtb_addr_in[gi] = boot_dtb_addr_in;
            assign cores__boot_priv_in[gi] = boot_priv_in;
            assign cores__external_cache_invalidate_in[gi] = external_cache_invalidate_in || peer_invalidate_comb[gi].full;
            assign cores__peer_cache_invalidate_in[gi] = unsigned'(1'(peer_invalidate_comb[gi].valid));
            assign cores__peer_cache_invalidate_addr_in[gi] = unsigned'(32'(peer_invalidate_comb[gi].addr));
            assign cores__memory_base_in[gi] = memory_base_in;
            assign cores__memory_size_in[gi] = memory_size_in;
            for (gregion='h0;gregion < 'h4;gregion=gregion+1) begin
                assign cores__mem_region_size_in[gi][gregion] = mem_region_size_in[gregion];
            end
            assign cores__clint_msip_in[gi] = clint_msip_per_core_in[gi];
            assign cores__clint_mtip_in[gi] = clint_mtip_per_core_in[gi];
            assign cores__external_irq_in[gi] = external_irq_per_core_in[gi];
            assign cores__sbi_ipi_in[gi] = sbi_ipi_targets_comb[gi];
            assign cores__remote_fence_i_in[gi] = sbi_fence_i_targets_comb[gi];
            assign cores__remote_sfence_vma_in[gi] = sbi_sfence_targets_comb[gi];
            assign sbi_set_timer_per_core_out[gi] = cores__sbi_set_timer_out[gi];
            assign sbi_timer_lo_per_core_out[gi] = cores__sbi_timer_lo_out[gi];
            assign sbi_timer_hi_per_core_out[gi] = cores__sbi_timer_hi_out[gi];
            assign cores__time_lo_in[gi] = time_lo_in;
            assign cores__time_hi_in[gi] = time_hi_in;
            assign cores__atomic_grant_in[gi] = atomic_grant_comb[gi];
            assign cores__i_mem_out__read_data_in[gi] = i_mem_cdc__fast_in__read_data_out[gi];
            assign cores__i_mem_out__wait_in[gi] = i_mem_cdc__fast_in__wait_out[gi];
            assign cores__d_mem_out__read_data_in[gi] = d_mem_cdc__fast_in__read_data_out[gi];
            assign cores__d_mem_out__wait_in[gi] = !atomic_data_access_comb[gi] || d_mem_cdc__fast_in__wait_out[gi];
            assign i_mem_cdc__fast_in__read_in[gi] = cores__i_mem_out__read_out[gi];
            assign i_mem_cdc__fast_in__write_in[gi] = cores__i_mem_out__write_out[gi];
            assign i_mem_cdc__fast_in__addr_in[gi] = cores__i_mem_out__addr_out[gi];
            assign i_mem_cdc__fast_in__write_data_in[gi] = cores__i_mem_out__write_data_out[gi];
            assign i_mem_cdc__fast_in__write_mask_in[gi] = cores__i_mem_out__write_mask_out[gi];
            assign i_mem_cdc__fast_in__cache_disable_in[gi] = cores__i_mem_out__cache_disable_out[gi];
            assign d_mem_cdc__fast_in__read_in[gi] = atomic_data_access_comb[gi] && cores__d_mem_out__read_out[gi];
            assign d_mem_cdc__fast_in__write_in[gi] = atomic_data_access_comb[gi] && cores__d_mem_out__write_out[gi];
            assign d_mem_cdc__fast_in__addr_in[gi] = cores__d_mem_out__addr_out[gi];
            assign d_mem_cdc__fast_in__write_data_in[gi] = cores__d_mem_out__write_data_out[gi];
            assign d_mem_cdc__fast_in__write_mask_in[gi] = cores__d_mem_out__write_mask_out[gi];
            assign d_mem_cdc__fast_in__cache_disable_in[gi] = cores__d_mem_out__cache_disable_out[gi];
            assign l2cache__i_mem_in__read_in[gi] = i_mem_cdc__slow_out__read_out[gi];
            assign l2cache__i_mem_in__write_in[gi] = i_mem_cdc__slow_out__write_out[gi];
            assign l2cache__i_mem_in__addr_in[gi] = i_mem_cdc__slow_out__addr_out[gi];
            assign l2cache__i_mem_in__write_data_in[gi] = i_mem_cdc__slow_out__write_data_out[gi];
            assign l2cache__i_mem_in__write_mask_in[gi] = i_mem_cdc__slow_out__write_mask_out[gi];
            assign l2cache__i_mem_in__cache_disable_in[gi] = i_mem_cdc__slow_out__cache_disable_out[gi];
            assign i_mem_cdc__slow_out__read_data_in[gi] = l2cache__i_mem_in__read_data_out[gi];
            assign i_mem_cdc__slow_out__wait_in[gi] = l2cache__i_mem_in__wait_out[gi];
            assign l2cache__d_mem_in__read_in[gi] = d_mem_cdc__slow_out__read_out[gi];
            assign l2cache__d_mem_in__write_in[gi] = d_mem_cdc__slow_out__write_out[gi];
            assign l2cache__d_mem_in__addr_in[gi] = d_mem_cdc__slow_out__addr_out[gi];
            assign l2cache__d_mem_in__write_data_in[gi] = d_mem_cdc__slow_out__write_data_out[gi];
            assign l2cache__d_mem_in__write_mask_in[gi] = d_mem_cdc__slow_out__write_mask_out[gi];
            assign l2cache__d_mem_in__cache_disable_in[gi] = d_mem_cdc__slow_out__cache_disable_out[gi];
            assign d_mem_cdc__slow_out__read_data_in[gi] = l2cache__d_mem_in__read_data_out[gi];
            assign d_mem_cdc__slow_out__wait_in[gi] = l2cache__d_mem_in__wait_out[gi];
        end
    endgenerate

    task work_clk_func (input logic reset);
    begin: work_clk_func
        logic[31:0] i;
        logic atomic_selected;
        logic ordinary_data_pending;
        logic[31:0] atomic_candidate;
        logic[31:0] atomic_offset;
        for (i='h0;i < CPU_CORES;i=i+1) begin
            peer_store_reg_tmp[i].valid = unsigned'(1'(0));
            if ((cores__dmem_write_out[i] && atomic_data_access_comb[i]) && !d_mem_cdc__fast_in__wait_out[i]) begin
                peer_store_reg_tmp[i].valid = unsigned'(1'(1));
                peer_store_reg_tmp[i].addr = unsigned'(32'(cores__dmem_addr_out[i]));
            end
        end
        atomic_selected=0;
        ordinary_data_pending=0;
        for (i='h0;i < CPU_CORES;i=i+1) begin
            if (((cores__dmem_read_out[i] || cores__dmem_write_out[i])) && !cores__atomic_data_request_out[i]) begin
                ordinary_data_pending=1;
            end
        end
        if (atomic_owner_valid_reg) begin
            if (cores__atomic_complete_out[unsigned'(32'(atomic_owner_reg))] || !cores__atomic_request_out[unsigned'(32'(atomic_owner_reg))]) begin
                atomic_owner_valid_reg_tmp = unsigned'(1'(0));
                atomic_rr_reg_tmp = (unsigned'(32'(atomic_owner_reg)) == (CPU_CORES - 'h1)) ? (unsigned'(32'('h0))) : (unsigned'(32'(atomic_owner_reg)) + 'h1);
            end
        end
        else begin
            if (!ordinary_data_pending) begin
                for (atomic_offset='h0;atomic_offset < CPU_CORES;atomic_offset=atomic_offset+1) begin
                    atomic_candidate=unsigned'(32'(atomic_rr_reg)) + atomic_offset;
                    if (atomic_candidate>=CPU_CORES) begin
                        atomic_candidate-=CPU_CORES;
                    end
                    if (!atomic_selected && cores__atomic_request_out[atomic_candidate]) begin
                        atomic_owner_valid_reg_tmp = unsigned'(1'(1));
                        atomic_owner_reg_tmp = atomic_candidate;
                        atomic_selected=1;
                    end
                end
            end
        end
        if (reset) begin
            for (i='h0;i < CPU_CORES;i=i+1) begin
                peer_store_reg_tmp[i].valid = unsigned'(1'(0));
                peer_store_reg_tmp[i].addr = unsigned'(32'h0);
            end
            atomic_owner_valid_reg_tmp = '0;
            atomic_owner_reg_tmp = '0;
            atomic_rr_reg_tmp = '0;
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
        work_clk_func(reset);
    end
    endtask

    task _work_clk (input logic reset);
    begin: _work_clk
        work_clk_func(reset);
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        peer_store_reg_tmp = peer_store_reg;
        atomic_owner_valid_reg_tmp = atomic_owner_valid_reg;
        atomic_owner_reg_tmp = atomic_owner_reg;
        atomic_rr_reg_tmp = atomic_rr_reg;

        _work_clk(reset);

        peer_store_reg <= peer_store_reg_tmp;
        atomic_owner_valid_reg <= atomic_owner_valid_reg_tmp;
        atomic_owner_reg <= atomic_owner_reg_tmp;
        atomic_rr_reg <= atomic_rr_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end

    assign dmem_write_out = cores__dmem_write_out['h0];

    assign dmem_write_data_out = cores__dmem_write_data_out['h0];

    assign dmem_write_mask_out = cores__dmem_write_mask_out['h0];

    assign dmem_read_out = cores__dmem_read_out['h0];

    assign dmem_addr_out = cores__dmem_addr_out['h0];

    assign imem_read_addr_out = cores__imem_read_addr_out['h0];

    assign debug_core_out = cores__debug_core_out['h0];

    assign debug_mmu_out = cores__debug_mmu_out['h0];

    assign debug_cache_out = cores__debug_cache_out['h0];

    assign debug_wb_out = cores__debug_wb_out['h0];

    assign debug_csr_out = cores__debug_csr_out['h0];

    assign debug_irq_out = cores__debug_irq_out['h0];

    assign debug_regs_out = cores__debug_regs_out['h0];

    assign debug_branch_out = cores__debug_branch_out['h0];

    assign debug_decode_out = cores__debug_decode_out['h0];

    assign sbi_set_timer_out = cores__sbi_set_timer_out['h0];

    assign sbi_timer_lo_out = cores__sbi_timer_lo_out['h0];

    assign sbi_timer_hi_out = cores__sbi_timer_hi_out['h0];

    assign debug_sbi_out = cores__debug_sbi_out['h0];

    assign perf_out = cores__perf_out['h0];


endmodule
