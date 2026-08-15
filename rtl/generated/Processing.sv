`default_nettype none

import Predef_pkg::*;
import Zicsr_pkg::*;
import Rv32im_pkg::*;
import Rv32ic_pkg::*;
import Rv32i_pkg::*;
import Mem_pkg::*;
import Alu_pkg::*;
import Wb_pkg::*;
import Br_pkg::*;
import Sys_pkg::*;
import Trap_pkg::*;
import Csr_pkg::*;
import State_pkg::*;
import Amo_pkg::*;
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
import TribeSbiDebug_pkg::*;
import TribePerf_pkg::*;
import L1PeerStoreState_pkg::*;
import L1PeerInvalidateComb_pkg::*;
import DescriptorFetcher_Register_pkg::*;
import PacketDMA_Command_pkg::*;
import PacketDMA_Register_pkg::*;
import PacketDmaState_pkg::*;
import PacketDmaError_pkg::*;
import PacketDmaOperation_pkg::*;
import CPU_pkg::*;


module Processing #(
    parameter CPU_COUNT = 'h1
,   parameter HANDLE_BITS = 'h10
,   parameter FRAME_LENGTH_BITS = 'hE
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire descriptor_valid_in
,   input wire[256-1:0] descriptor_data_in
,   input wire[3-1:0] descriptor_word_in
,   input wire descriptor_sop_in
,   input wire descriptor_eop_in
,   output wire descriptor_ready_out
,   output wire[CPU_COUNT-1:0] rx_read_valid_out
,   output wire[CPU_COUNT*HANDLE_BITS-1:0] rx_read_handle_out
,   output wire[CPU_COUNT*FRAME_LENGTH_BITS-1:0] rx_read_length_out
,   input wire[CPU_COUNT-1:0] rx_read_ready_in
,   input wire[CPU_COUNT-1:0] rx_valid_in
,   input wire[CPU_COUNT*'h100-1:0] rx_data_in
,   input wire[CPU_COUNT*'h20-1:0] rx_keep_in
,   input wire[CPU_COUNT-1:0] rx_sop_in
,   input wire[CPU_COUNT-1:0] rx_eop_in
,   output wire[CPU_COUNT-1:0] rx_ready_out
,   output wire[CPU_COUNT-1:0] to_system_valid_out
,   output wire[CPU_COUNT*'h100-1:0] to_system_data_out
,   output wire[CPU_COUNT*'h20-1:0] to_system_keep_out
,   output wire[CPU_COUNT-1:0] to_system_sop_out
,   output wire[CPU_COUNT-1:0] to_system_eop_out
,   input wire[CPU_COUNT-1:0] to_system_ready_in
,   input wire[CPU_COUNT-1:0] from_system_valid_in
,   input wire[CPU_COUNT*'h100-1:0] from_system_data_in
,   input wire[CPU_COUNT*'h20-1:0] from_system_keep_in
,   input wire[CPU_COUNT-1:0] from_system_sop_in
,   input wire[CPU_COUNT-1:0] from_system_eop_in
,   output wire[CPU_COUNT-1:0] from_system_ready_out
,   output wire[CPU_COUNT-1:0] to_network_valid_out
,   output wire[CPU_COUNT*'h100-1:0] to_network_data_out
,   output wire[CPU_COUNT*'h20-1:0] to_network_keep_out
,   output wire[CPU_COUNT-1:0] to_network_sop_out
,   output wire[CPU_COUNT-1:0] to_network_eop_out
,   input wire[CPU_COUNT-1:0] to_network_ready_in
,   output wire ddr__awvalid_out[CPU_COUNT]
,   input wire ddr__awready_in[CPU_COUNT]
,   output wire[31-1:0] ddr__awaddr_out[CPU_COUNT]
,   output wire[4-1:0] ddr__awid_out[CPU_COUNT]
,   output wire ddr__wvalid_out[CPU_COUNT]
,   input wire ddr__wready_in[CPU_COUNT]
,   output wire[256-1:0] ddr__wdata_out[CPU_COUNT]
,   output wire[256/'h8-1:0] ddr__wstrb_out[CPU_COUNT]
,   output wire ddr__wlast_out[CPU_COUNT]
,   input wire ddr__bvalid_in[CPU_COUNT]
,   output wire ddr__bready_out[CPU_COUNT]
,   input wire[4-1:0] ddr__bid_in[CPU_COUNT]
,   output wire ddr__arvalid_out[CPU_COUNT]
,   input wire ddr__arready_in[CPU_COUNT]
,   output wire[31-1:0] ddr__araddr_out[CPU_COUNT]
,   output wire[4-1:0] ddr__arid_out[CPU_COUNT]
,   input wire ddr__rvalid_in[CPU_COUNT]
,   output wire ddr__rready_out[CPU_COUNT]
,   input wire[256-1:0] ddr__rdata_in[CPU_COUNT]
,   input wire ddr__rlast_in[CPU_COUNT]
,   input wire[4-1:0] ddr__rid_in[CPU_COUNT]
,   input wire software_irq_in[CPU_COUNT*CPU_pkg::CORES]
,   input wire timer_irq_in[CPU_COUNT*CPU_pkg::CORES]
,   input wire external_irq_in[CPU_COUNT*CPU_pkg::CORES]
,   input wire cache_invalidate_in[CPU_COUNT]
);
    parameter  READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    parameter  RX_STREAM_BITS = 64'h122;
    parameter  TARGET_BITS = (CPU_COUNT<='h1) ? ('h1) : ($clog2(CPU_COUNT));
    parameter  FETCHER_BASE = 'h0;
    parameter  FETCHER_SIZE = 'h1000;
    parameter  DMA_BASE = 'h1000;
    parameter  DMA_SIZE = 'h1000;


    // regs and combs
    logic[CPU_COUNT-1:0] rx_read_valid_comb;
    logic[CPU_COUNT*HANDLE_BITS-1:0] rx_read_handle_comb;
    logic[CPU_COUNT*FRAME_LENGTH_BITS-1:0] rx_read_length_comb;
    logic[CPU_COUNT-1:0] rx_ready_comb;
    logic[290-1:0] rx_stream_pack_comb[CPU_COUNT];
    logic[290-1:0] from_system_pack_comb[CPU_COUNT];
    logic[CPU_COUNT-1:0] to_system_valid_comb;
    logic[CPU_COUNT*'h100-1:0] to_system_data_comb;
    logic[CPU_COUNT*'h20-1:0] to_system_keep_comb;
    logic[CPU_COUNT-1:0] to_system_sop_comb;
    logic[CPU_COUNT-1:0] to_system_eop_comb;
    logic[CPU_COUNT-1:0] from_system_ready_comb;
    logic[CPU_COUNT-1:0] to_network_valid_comb;
    logic[CPU_COUNT*'h100-1:0] to_network_data_comb;
    logic[CPU_COUNT*'h20-1:0] to_network_keep_comb;
    logic[CPU_COUNT-1:0] to_network_sop_comb;
    logic[CPU_COUNT-1:0] to_network_eop_comb;

    // members
    genvar __i;
    wire cpu__dma_in__awvalid_in[CPU_COUNT];
    wire cpu__dma_in__awready_out[CPU_COUNT];
    wire[32-1:0] cpu__dma_in__awaddr_in[CPU_COUNT];
    wire[4-1:0] cpu__dma_in__awid_in[CPU_COUNT];
    wire cpu__dma_in__wvalid_in[CPU_COUNT];
    wire cpu__dma_in__wready_out[CPU_COUNT];
    wire[256-1:0] cpu__dma_in__wdata_in[CPU_COUNT];
    wire[256/'h8-1:0] cpu__dma_in__wstrb_in[CPU_COUNT];
    wire cpu__dma_in__wlast_in[CPU_COUNT];
    wire cpu__dma_in__bvalid_out[CPU_COUNT];
    wire cpu__dma_in__bready_in[CPU_COUNT];
    wire[4-1:0] cpu__dma_in__bid_out[CPU_COUNT];
    wire cpu__dma_in__arvalid_in[CPU_COUNT];
    wire cpu__dma_in__arready_out[CPU_COUNT];
    wire[32-1:0] cpu__dma_in__araddr_in[CPU_COUNT];
    wire[4-1:0] cpu__dma_in__arid_in[CPU_COUNT];
    wire cpu__dma_in__rvalid_out[CPU_COUNT];
    wire cpu__dma_in__rready_in[CPU_COUNT];
    wire[256-1:0] cpu__dma_in__rdata_out[CPU_COUNT];
    wire cpu__dma_in__rlast_out[CPU_COUNT];
    wire[4-1:0] cpu__dma_in__rid_out[CPU_COUNT];
    wire cpu__memory__awvalid_out[CPU_COUNT];
    wire cpu__memory__awready_in[CPU_COUNT];
    wire[31-1:0] cpu__memory__awaddr_out[CPU_COUNT];
    wire[4-1:0] cpu__memory__awid_out[CPU_COUNT];
    wire cpu__memory__wvalid_out[CPU_COUNT];
    wire cpu__memory__wready_in[CPU_COUNT];
    wire[256-1:0] cpu__memory__wdata_out[CPU_COUNT];
    wire[256/'h8-1:0] cpu__memory__wstrb_out[CPU_COUNT];
    wire cpu__memory__wlast_out[CPU_COUNT];
    wire cpu__memory__bvalid_in[CPU_COUNT];
    wire cpu__memory__bready_out[CPU_COUNT];
    wire[4-1:0] cpu__memory__bid_in[CPU_COUNT];
    wire cpu__memory__arvalid_out[CPU_COUNT];
    wire cpu__memory__arready_in[CPU_COUNT];
    wire[31-1:0] cpu__memory__araddr_out[CPU_COUNT];
    wire[4-1:0] cpu__memory__arid_out[CPU_COUNT];
    wire cpu__memory__rvalid_in[CPU_COUNT];
    wire cpu__memory__rready_out[CPU_COUNT];
    wire[256-1:0] cpu__memory__rdata_in[CPU_COUNT];
    wire cpu__memory__rlast_in[CPU_COUNT];
    wire[4-1:0] cpu__memory__rid_in[CPU_COUNT];
    wire cpu__iomem__awvalid_out[CPU_COUNT];
    wire cpu__iomem__awready_in[CPU_COUNT];
    wire[32-1:0] cpu__iomem__awaddr_out[CPU_COUNT];
    wire[4-1:0] cpu__iomem__awid_out[CPU_COUNT];
    wire cpu__iomem__wvalid_out[CPU_COUNT];
    wire cpu__iomem__wready_in[CPU_COUNT];
    wire[256-1:0] cpu__iomem__wdata_out[CPU_COUNT];
    wire[256/'h8-1:0] cpu__iomem__wstrb_out[CPU_COUNT];
    wire cpu__iomem__wlast_out[CPU_COUNT];
    wire cpu__iomem__bvalid_in[CPU_COUNT];
    wire cpu__iomem__bready_out[CPU_COUNT];
    wire[4-1:0] cpu__iomem__bid_in[CPU_COUNT];
    wire cpu__iomem__arvalid_out[CPU_COUNT];
    wire cpu__iomem__arready_in[CPU_COUNT];
    wire[32-1:0] cpu__iomem__araddr_out[CPU_COUNT];
    wire[4-1:0] cpu__iomem__arid_out[CPU_COUNT];
    wire cpu__iomem__rvalid_in[CPU_COUNT];
    wire cpu__iomem__rready_out[CPU_COUNT];
    wire[256-1:0] cpu__iomem__rdata_in[CPU_COUNT];
    wire cpu__iomem__rlast_in[CPU_COUNT];
    wire[4-1:0] cpu__iomem__rid_in[CPU_COUNT];
    wire[32-1:0] cpu__reset_pc_in[CPU_COUNT];
    wire[32-1:0] cpu__boot_hartid_in[CPU_COUNT];
    wire[32-1:0] cpu__boot_dtb_addr_in[CPU_COUNT];
    wire[2-1:0] cpu__boot_priv_in[CPU_COUNT];
    wire cpu__cache_invalidate_in[CPU_COUNT];
    wire cpu__software_irq_in[CPU_COUNT][4];
    wire cpu__timer_irq_in[CPU_COUNT][4];
    wire cpu__external_irq_in[CPU_COUNT][4];
    generate
    for (__i=0; __i < CPU_COUNT; __i = __i + 1) begin
        CPU          cpu (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .dma_in__awvalid_in(cpu__dma_in__awvalid_in[__i])
        ,           .dma_in__awready_out(cpu__dma_in__awready_out[__i])
        ,           .dma_in__awaddr_in(cpu__dma_in__awaddr_in[__i])
        ,           .dma_in__awid_in(cpu__dma_in__awid_in[__i])
        ,           .dma_in__wvalid_in(cpu__dma_in__wvalid_in[__i])
        ,           .dma_in__wready_out(cpu__dma_in__wready_out[__i])
        ,           .dma_in__wdata_in(cpu__dma_in__wdata_in[__i])
        ,           .dma_in__wstrb_in(cpu__dma_in__wstrb_in[__i])
        ,           .dma_in__wlast_in(cpu__dma_in__wlast_in[__i])
        ,           .dma_in__bvalid_out(cpu__dma_in__bvalid_out[__i])
        ,           .dma_in__bready_in(cpu__dma_in__bready_in[__i])
        ,           .dma_in__bid_out(cpu__dma_in__bid_out[__i])
        ,           .dma_in__arvalid_in(cpu__dma_in__arvalid_in[__i])
        ,           .dma_in__arready_out(cpu__dma_in__arready_out[__i])
        ,           .dma_in__araddr_in(cpu__dma_in__araddr_in[__i])
        ,           .dma_in__arid_in(cpu__dma_in__arid_in[__i])
        ,           .dma_in__rvalid_out(cpu__dma_in__rvalid_out[__i])
        ,           .dma_in__rready_in(cpu__dma_in__rready_in[__i])
        ,           .dma_in__rdata_out(cpu__dma_in__rdata_out[__i])
        ,           .dma_in__rlast_out(cpu__dma_in__rlast_out[__i])
        ,           .dma_in__rid_out(cpu__dma_in__rid_out[__i])
        ,           .memory__awvalid_out(cpu__memory__awvalid_out[__i])
        ,           .memory__awready_in(cpu__memory__awready_in[__i])
        ,           .memory__awaddr_out(cpu__memory__awaddr_out[__i])
        ,           .memory__awid_out(cpu__memory__awid_out[__i])
        ,           .memory__wvalid_out(cpu__memory__wvalid_out[__i])
        ,           .memory__wready_in(cpu__memory__wready_in[__i])
        ,           .memory__wdata_out(cpu__memory__wdata_out[__i])
        ,           .memory__wstrb_out(cpu__memory__wstrb_out[__i])
        ,           .memory__wlast_out(cpu__memory__wlast_out[__i])
        ,           .memory__bvalid_in(cpu__memory__bvalid_in[__i])
        ,           .memory__bready_out(cpu__memory__bready_out[__i])
        ,           .memory__bid_in(cpu__memory__bid_in[__i])
        ,           .memory__arvalid_out(cpu__memory__arvalid_out[__i])
        ,           .memory__arready_in(cpu__memory__arready_in[__i])
        ,           .memory__araddr_out(cpu__memory__araddr_out[__i])
        ,           .memory__arid_out(cpu__memory__arid_out[__i])
        ,           .memory__rvalid_in(cpu__memory__rvalid_in[__i])
        ,           .memory__rready_out(cpu__memory__rready_out[__i])
        ,           .memory__rdata_in(cpu__memory__rdata_in[__i])
        ,           .memory__rlast_in(cpu__memory__rlast_in[__i])
        ,           .memory__rid_in(cpu__memory__rid_in[__i])
        ,           .iomem__awvalid_out(cpu__iomem__awvalid_out[__i])
        ,           .iomem__awready_in(cpu__iomem__awready_in[__i])
        ,           .iomem__awaddr_out(cpu__iomem__awaddr_out[__i])
        ,           .iomem__awid_out(cpu__iomem__awid_out[__i])
        ,           .iomem__wvalid_out(cpu__iomem__wvalid_out[__i])
        ,           .iomem__wready_in(cpu__iomem__wready_in[__i])
        ,           .iomem__wdata_out(cpu__iomem__wdata_out[__i])
        ,           .iomem__wstrb_out(cpu__iomem__wstrb_out[__i])
        ,           .iomem__wlast_out(cpu__iomem__wlast_out[__i])
        ,           .iomem__bvalid_in(cpu__iomem__bvalid_in[__i])
        ,           .iomem__bready_out(cpu__iomem__bready_out[__i])
        ,           .iomem__bid_in(cpu__iomem__bid_in[__i])
        ,           .iomem__arvalid_out(cpu__iomem__arvalid_out[__i])
        ,           .iomem__arready_in(cpu__iomem__arready_in[__i])
        ,           .iomem__araddr_out(cpu__iomem__araddr_out[__i])
        ,           .iomem__arid_out(cpu__iomem__arid_out[__i])
        ,           .iomem__rvalid_in(cpu__iomem__rvalid_in[__i])
        ,           .iomem__rready_out(cpu__iomem__rready_out[__i])
        ,           .iomem__rdata_in(cpu__iomem__rdata_in[__i])
        ,           .iomem__rlast_in(cpu__iomem__rlast_in[__i])
        ,           .iomem__rid_in(cpu__iomem__rid_in[__i])
        ,           .reset_pc_in(cpu__reset_pc_in[__i])
        ,           .boot_hartid_in(cpu__boot_hartid_in[__i])
        ,           .boot_dtb_addr_in(cpu__boot_dtb_addr_in[__i])
        ,           .boot_priv_in(cpu__boot_priv_in[__i])
        ,           .cache_invalidate_in(cpu__cache_invalidate_in[__i])
        ,           .software_irq_in(cpu__software_irq_in[__i])
        ,           .timer_irq_in(cpu__timer_irq_in[__i])
        ,           .external_irq_in(cpu__external_irq_in[__i])
        );
    end
    endgenerate
    wire descriptor_fetcher__descriptor_valid_in[CPU_COUNT];
    wire[256-1:0] descriptor_fetcher__descriptor_data_in[CPU_COUNT];
    wire[3-1:0] descriptor_fetcher__descriptor_word_in[CPU_COUNT];
    wire descriptor_fetcher__descriptor_sop_in[CPU_COUNT];
    wire descriptor_fetcher__descriptor_eop_in[CPU_COUNT];
    wire descriptor_fetcher__descriptor_ready_out[CPU_COUNT];
    wire descriptor_fetcher__packet_command_ready_in[CPU_COUNT];
    wire descriptor_fetcher__packet_command_valid_out[CPU_COUNT];
    wire[HANDLE_BITS-1:0] descriptor_fetcher__packet_command_handle_out[CPU_COUNT];
    wire[14-1:0] descriptor_fetcher__packet_command_length_out[CPU_COUNT];
    wire descriptor_fetcher__packet_command_system_out[CPU_COUNT];
    wire descriptor_fetcher__mmio__awvalid_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__awready_out[CPU_COUNT];
    wire[32-1:0] descriptor_fetcher__mmio__awaddr_in[CPU_COUNT];
    wire[4-1:0] descriptor_fetcher__mmio__awid_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__wvalid_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__wready_out[CPU_COUNT];
    wire[256-1:0] descriptor_fetcher__mmio__wdata_in[CPU_COUNT];
    wire[256/'h8-1:0] descriptor_fetcher__mmio__wstrb_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__wlast_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__bvalid_out[CPU_COUNT];
    wire descriptor_fetcher__mmio__bready_in[CPU_COUNT];
    wire[4-1:0] descriptor_fetcher__mmio__bid_out[CPU_COUNT];
    wire descriptor_fetcher__mmio__arvalid_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__arready_out[CPU_COUNT];
    wire[32-1:0] descriptor_fetcher__mmio__araddr_in[CPU_COUNT];
    wire[4-1:0] descriptor_fetcher__mmio__arid_in[CPU_COUNT];
    wire descriptor_fetcher__mmio__rvalid_out[CPU_COUNT];
    wire descriptor_fetcher__mmio__rready_in[CPU_COUNT];
    wire[256-1:0] descriptor_fetcher__mmio__rdata_out[CPU_COUNT];
    wire descriptor_fetcher__mmio__rlast_out[CPU_COUNT];
    wire[4-1:0] descriptor_fetcher__mmio__rid_out[CPU_COUNT];
    wire descriptor_fetcher__descriptor_available_out[CPU_COUNT];
    wire[$clog2('h4 + 'h1)-1:0] descriptor_fetcher__descriptor_count_out[CPU_COUNT];
    wire descriptor_fetcher__prefetch_enabled_out[CPU_COUNT];
    wire descriptor_fetcher__protocol_error_out[CPU_COUNT];
    generate
    for (__i=0; __i < CPU_COUNT; __i = __i + 1) begin
        DescriptorFetcher #(
        'h4
,       'h20
,       'h4
,       'h100
,       HANDLE_BITS
        ) descriptor_fetcher (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .descriptor_valid_in(descriptor_fetcher__descriptor_valid_in[__i])
        ,           .descriptor_data_in(descriptor_fetcher__descriptor_data_in[__i])
        ,           .descriptor_word_in(descriptor_fetcher__descriptor_word_in[__i])
        ,           .descriptor_sop_in(descriptor_fetcher__descriptor_sop_in[__i])
        ,           .descriptor_eop_in(descriptor_fetcher__descriptor_eop_in[__i])
        ,           .descriptor_ready_out(descriptor_fetcher__descriptor_ready_out[__i])
        ,           .packet_command_ready_in(descriptor_fetcher__packet_command_ready_in[__i])
        ,           .packet_command_valid_out(descriptor_fetcher__packet_command_valid_out[__i])
        ,           .packet_command_handle_out(descriptor_fetcher__packet_command_handle_out[__i])
        ,           .packet_command_length_out(descriptor_fetcher__packet_command_length_out[__i])
        ,           .packet_command_system_out(descriptor_fetcher__packet_command_system_out[__i])
        ,           .mmio__awvalid_in(descriptor_fetcher__mmio__awvalid_in[__i])
        ,           .mmio__awready_out(descriptor_fetcher__mmio__awready_out[__i])
        ,           .mmio__awaddr_in(descriptor_fetcher__mmio__awaddr_in[__i])
        ,           .mmio__awid_in(descriptor_fetcher__mmio__awid_in[__i])
        ,           .mmio__wvalid_in(descriptor_fetcher__mmio__wvalid_in[__i])
        ,           .mmio__wready_out(descriptor_fetcher__mmio__wready_out[__i])
        ,           .mmio__wdata_in(descriptor_fetcher__mmio__wdata_in[__i])
        ,           .mmio__wstrb_in(descriptor_fetcher__mmio__wstrb_in[__i])
        ,           .mmio__wlast_in(descriptor_fetcher__mmio__wlast_in[__i])
        ,           .mmio__bvalid_out(descriptor_fetcher__mmio__bvalid_out[__i])
        ,           .mmio__bready_in(descriptor_fetcher__mmio__bready_in[__i])
        ,           .mmio__bid_out(descriptor_fetcher__mmio__bid_out[__i])
        ,           .mmio__arvalid_in(descriptor_fetcher__mmio__arvalid_in[__i])
        ,           .mmio__arready_out(descriptor_fetcher__mmio__arready_out[__i])
        ,           .mmio__araddr_in(descriptor_fetcher__mmio__araddr_in[__i])
        ,           .mmio__arid_in(descriptor_fetcher__mmio__arid_in[__i])
        ,           .mmio__rvalid_out(descriptor_fetcher__mmio__rvalid_out[__i])
        ,           .mmio__rready_in(descriptor_fetcher__mmio__rready_in[__i])
        ,           .mmio__rdata_out(descriptor_fetcher__mmio__rdata_out[__i])
        ,           .mmio__rlast_out(descriptor_fetcher__mmio__rlast_out[__i])
        ,           .mmio__rid_out(descriptor_fetcher__mmio__rid_out[__i])
        ,           .descriptor_available_out(descriptor_fetcher__descriptor_available_out[__i])
        ,           .descriptor_count_out(descriptor_fetcher__descriptor_count_out[__i])
        ,           .prefetch_enabled_out(descriptor_fetcher__prefetch_enabled_out[__i])
        ,           .protocol_error_out(descriptor_fetcher__protocol_error_out[__i])
        );
    end
    endgenerate
    wire packet_dma__mmio__awvalid_in[CPU_COUNT];
    wire packet_dma__mmio__awready_out[CPU_COUNT];
    wire[32-1:0] packet_dma__mmio__awaddr_in[CPU_COUNT];
    wire[4-1:0] packet_dma__mmio__awid_in[CPU_COUNT];
    wire packet_dma__mmio__wvalid_in[CPU_COUNT];
    wire packet_dma__mmio__wready_out[CPU_COUNT];
    wire[256-1:0] packet_dma__mmio__wdata_in[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__mmio__wstrb_in[CPU_COUNT];
    wire packet_dma__mmio__wlast_in[CPU_COUNT];
    wire packet_dma__mmio__bvalid_out[CPU_COUNT];
    wire packet_dma__mmio__bready_in[CPU_COUNT];
    wire[4-1:0] packet_dma__mmio__bid_out[CPU_COUNT];
    wire packet_dma__mmio__arvalid_in[CPU_COUNT];
    wire packet_dma__mmio__arready_out[CPU_COUNT];
    wire[32-1:0] packet_dma__mmio__araddr_in[CPU_COUNT];
    wire[4-1:0] packet_dma__mmio__arid_in[CPU_COUNT];
    wire packet_dma__mmio__rvalid_out[CPU_COUNT];
    wire packet_dma__mmio__rready_in[CPU_COUNT];
    wire[256-1:0] packet_dma__mmio__rdata_out[CPU_COUNT];
    wire packet_dma__mmio__rlast_out[CPU_COUNT];
    wire[4-1:0] packet_dma__mmio__rid_out[CPU_COUNT];
    wire packet_dma__l2_dma__awvalid_out[CPU_COUNT];
    wire packet_dma__l2_dma__awready_in[CPU_COUNT];
    wire[32-1:0] packet_dma__l2_dma__awaddr_out[CPU_COUNT];
    wire[4-1:0] packet_dma__l2_dma__awid_out[CPU_COUNT];
    wire packet_dma__l2_dma__wvalid_out[CPU_COUNT];
    wire packet_dma__l2_dma__wready_in[CPU_COUNT];
    wire[256-1:0] packet_dma__l2_dma__wdata_out[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__l2_dma__wstrb_out[CPU_COUNT];
    wire packet_dma__l2_dma__wlast_out[CPU_COUNT];
    wire packet_dma__l2_dma__bvalid_in[CPU_COUNT];
    wire packet_dma__l2_dma__bready_out[CPU_COUNT];
    wire[4-1:0] packet_dma__l2_dma__bid_in[CPU_COUNT];
    wire packet_dma__l2_dma__arvalid_out[CPU_COUNT];
    wire packet_dma__l2_dma__arready_in[CPU_COUNT];
    wire[32-1:0] packet_dma__l2_dma__araddr_out[CPU_COUNT];
    wire[4-1:0] packet_dma__l2_dma__arid_out[CPU_COUNT];
    wire packet_dma__l2_dma__rvalid_in[CPU_COUNT];
    wire packet_dma__l2_dma__rready_out[CPU_COUNT];
    wire[256-1:0] packet_dma__l2_dma__rdata_in[CPU_COUNT];
    wire packet_dma__l2_dma__rlast_in[CPU_COUNT];
    wire[4-1:0] packet_dma__l2_dma__rid_in[CPU_COUNT];
    wire packet_dma__rx_read_valid_out[CPU_COUNT];
    wire[HANDLE_BITS-1:0] packet_dma__rx_read_handle_out[CPU_COUNT];
    wire[FRAME_LENGTH_BITS-1:0] packet_dma__rx_read_length_out[CPU_COUNT];
    wire packet_dma__rx_read_ready_in[CPU_COUNT];
    wire packet_dma__rx_valid_in[CPU_COUNT];
    wire[256-1:0] packet_dma__rx_data_in[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__rx_keep_in[CPU_COUNT];
    wire packet_dma__rx_sop_in[CPU_COUNT];
    wire packet_dma__rx_eop_in[CPU_COUNT];
    wire packet_dma__rx_ready_out[CPU_COUNT];
    wire packet_dma__system_rx_valid_in[CPU_COUNT];
    wire[256-1:0] packet_dma__system_rx_data_in[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__system_rx_keep_in[CPU_COUNT];
    wire packet_dma__system_rx_sop_in[CPU_COUNT];
    wire packet_dma__system_rx_eop_in[CPU_COUNT];
    wire packet_dma__system_rx_ready_out[CPU_COUNT];
    wire packet_dma__system_tx_valid_out[CPU_COUNT];
    wire[256-1:0] packet_dma__system_tx_data_out[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__system_tx_keep_out[CPU_COUNT];
    wire packet_dma__system_tx_sop_out[CPU_COUNT];
    wire packet_dma__system_tx_eop_out[CPU_COUNT];
    wire packet_dma__system_tx_ready_in[CPU_COUNT];
    wire packet_dma__network_tx_valid_out[CPU_COUNT];
    wire[256-1:0] packet_dma__network_tx_data_out[CPU_COUNT];
    wire[256/'h8-1:0] packet_dma__network_tx_keep_out[CPU_COUNT];
    wire packet_dma__network_tx_sop_out[CPU_COUNT];
    wire packet_dma__network_tx_eop_out[CPU_COUNT];
    wire packet_dma__network_tx_ready_in[CPU_COUNT];
    wire packet_dma__busy_out[CPU_COUNT];
    wire packet_dma__command_ready_out[CPU_COUNT];
    wire packet_dma__descriptor_command_valid_in[CPU_COUNT];
    wire[HANDLE_BITS-1:0] packet_dma__descriptor_command_handle_in[CPU_COUNT];
    wire[FRAME_LENGTH_BITS-1:0] packet_dma__descriptor_command_length_in[CPU_COUNT];
    wire packet_dma__descriptor_command_system_in[CPU_COUNT];
    wire[32-1:0] packet_dma__completed_count_out[CPU_COUNT];
    wire[2-1:0] packet_dma__last_operation_out[CPU_COUNT];
    wire packet_dma__protocol_error_out[CPU_COUNT];
    wire[4-1:0] packet_dma__protocol_error_reason_out[CPU_COUNT];
    generate
    for (__i=0; __i < CPU_COUNT; __i = __i + 1) begin
        PacketDMA #(
        HANDLE_BITS
,       FRAME_LENGTH_BITS
,       8
,       32
,       4
,       256
        ) packet_dma (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .mmio__awvalid_in(packet_dma__mmio__awvalid_in[__i])
        ,           .mmio__awready_out(packet_dma__mmio__awready_out[__i])
        ,           .mmio__awaddr_in(packet_dma__mmio__awaddr_in[__i])
        ,           .mmio__awid_in(packet_dma__mmio__awid_in[__i])
        ,           .mmio__wvalid_in(packet_dma__mmio__wvalid_in[__i])
        ,           .mmio__wready_out(packet_dma__mmio__wready_out[__i])
        ,           .mmio__wdata_in(packet_dma__mmio__wdata_in[__i])
        ,           .mmio__wstrb_in(packet_dma__mmio__wstrb_in[__i])
        ,           .mmio__wlast_in(packet_dma__mmio__wlast_in[__i])
        ,           .mmio__bvalid_out(packet_dma__mmio__bvalid_out[__i])
        ,           .mmio__bready_in(packet_dma__mmio__bready_in[__i])
        ,           .mmio__bid_out(packet_dma__mmio__bid_out[__i])
        ,           .mmio__arvalid_in(packet_dma__mmio__arvalid_in[__i])
        ,           .mmio__arready_out(packet_dma__mmio__arready_out[__i])
        ,           .mmio__araddr_in(packet_dma__mmio__araddr_in[__i])
        ,           .mmio__arid_in(packet_dma__mmio__arid_in[__i])
        ,           .mmio__rvalid_out(packet_dma__mmio__rvalid_out[__i])
        ,           .mmio__rready_in(packet_dma__mmio__rready_in[__i])
        ,           .mmio__rdata_out(packet_dma__mmio__rdata_out[__i])
        ,           .mmio__rlast_out(packet_dma__mmio__rlast_out[__i])
        ,           .mmio__rid_out(packet_dma__mmio__rid_out[__i])
        ,           .l2_dma__awvalid_out(packet_dma__l2_dma__awvalid_out[__i])
        ,           .l2_dma__awready_in(packet_dma__l2_dma__awready_in[__i])
        ,           .l2_dma__awaddr_out(packet_dma__l2_dma__awaddr_out[__i])
        ,           .l2_dma__awid_out(packet_dma__l2_dma__awid_out[__i])
        ,           .l2_dma__wvalid_out(packet_dma__l2_dma__wvalid_out[__i])
        ,           .l2_dma__wready_in(packet_dma__l2_dma__wready_in[__i])
        ,           .l2_dma__wdata_out(packet_dma__l2_dma__wdata_out[__i])
        ,           .l2_dma__wstrb_out(packet_dma__l2_dma__wstrb_out[__i])
        ,           .l2_dma__wlast_out(packet_dma__l2_dma__wlast_out[__i])
        ,           .l2_dma__bvalid_in(packet_dma__l2_dma__bvalid_in[__i])
        ,           .l2_dma__bready_out(packet_dma__l2_dma__bready_out[__i])
        ,           .l2_dma__bid_in(packet_dma__l2_dma__bid_in[__i])
        ,           .l2_dma__arvalid_out(packet_dma__l2_dma__arvalid_out[__i])
        ,           .l2_dma__arready_in(packet_dma__l2_dma__arready_in[__i])
        ,           .l2_dma__araddr_out(packet_dma__l2_dma__araddr_out[__i])
        ,           .l2_dma__arid_out(packet_dma__l2_dma__arid_out[__i])
        ,           .l2_dma__rvalid_in(packet_dma__l2_dma__rvalid_in[__i])
        ,           .l2_dma__rready_out(packet_dma__l2_dma__rready_out[__i])
        ,           .l2_dma__rdata_in(packet_dma__l2_dma__rdata_in[__i])
        ,           .l2_dma__rlast_in(packet_dma__l2_dma__rlast_in[__i])
        ,           .l2_dma__rid_in(packet_dma__l2_dma__rid_in[__i])
        ,           .rx_read_valid_out(packet_dma__rx_read_valid_out[__i])
        ,           .rx_read_handle_out(packet_dma__rx_read_handle_out[__i])
        ,           .rx_read_length_out(packet_dma__rx_read_length_out[__i])
        ,           .rx_read_ready_in(packet_dma__rx_read_ready_in[__i])
        ,           .rx_valid_in(packet_dma__rx_valid_in[__i])
        ,           .rx_data_in(packet_dma__rx_data_in[__i])
        ,           .rx_keep_in(packet_dma__rx_keep_in[__i])
        ,           .rx_sop_in(packet_dma__rx_sop_in[__i])
        ,           .rx_eop_in(packet_dma__rx_eop_in[__i])
        ,           .rx_ready_out(packet_dma__rx_ready_out[__i])
        ,           .system_rx_valid_in(packet_dma__system_rx_valid_in[__i])
        ,           .system_rx_data_in(packet_dma__system_rx_data_in[__i])
        ,           .system_rx_keep_in(packet_dma__system_rx_keep_in[__i])
        ,           .system_rx_sop_in(packet_dma__system_rx_sop_in[__i])
        ,           .system_rx_eop_in(packet_dma__system_rx_eop_in[__i])
        ,           .system_rx_ready_out(packet_dma__system_rx_ready_out[__i])
        ,           .system_tx_valid_out(packet_dma__system_tx_valid_out[__i])
        ,           .system_tx_data_out(packet_dma__system_tx_data_out[__i])
        ,           .system_tx_keep_out(packet_dma__system_tx_keep_out[__i])
        ,           .system_tx_sop_out(packet_dma__system_tx_sop_out[__i])
        ,           .system_tx_eop_out(packet_dma__system_tx_eop_out[__i])
        ,           .system_tx_ready_in(packet_dma__system_tx_ready_in[__i])
        ,           .network_tx_valid_out(packet_dma__network_tx_valid_out[__i])
        ,           .network_tx_data_out(packet_dma__network_tx_data_out[__i])
        ,           .network_tx_keep_out(packet_dma__network_tx_keep_out[__i])
        ,           .network_tx_sop_out(packet_dma__network_tx_sop_out[__i])
        ,           .network_tx_eop_out(packet_dma__network_tx_eop_out[__i])
        ,           .network_tx_ready_in(packet_dma__network_tx_ready_in[__i])
        ,           .busy_out(packet_dma__busy_out[__i])
        ,           .command_ready_out(packet_dma__command_ready_out[__i])
        ,           .descriptor_command_valid_in(packet_dma__descriptor_command_valid_in[__i])
        ,           .descriptor_command_handle_in(packet_dma__descriptor_command_handle_in[__i])
        ,           .descriptor_command_length_in(packet_dma__descriptor_command_length_in[__i])
        ,           .descriptor_command_system_in(packet_dma__descriptor_command_system_in[__i])
        ,           .completed_count_out(packet_dma__completed_count_out[__i])
        ,           .last_operation_out(packet_dma__last_operation_out[__i])
        ,           .protocol_error_out(packet_dma__protocol_error_out[__i])
        ,           .protocol_error_reason_out(packet_dma__protocol_error_reason_out[__i])
        );
    end
    endgenerate
    wire iomem_mux__slave_in__awvalid_in[CPU_COUNT];
    wire iomem_mux__slave_in__awready_out[CPU_COUNT];
    wire[32-1:0] iomem_mux__slave_in__awaddr_in[CPU_COUNT];
    wire[4-1:0] iomem_mux__slave_in__awid_in[CPU_COUNT];
    wire iomem_mux__slave_in__wvalid_in[CPU_COUNT];
    wire iomem_mux__slave_in__wready_out[CPU_COUNT];
    wire[256-1:0] iomem_mux__slave_in__wdata_in[CPU_COUNT];
    wire[256/'h8-1:0] iomem_mux__slave_in__wstrb_in[CPU_COUNT];
    wire iomem_mux__slave_in__wlast_in[CPU_COUNT];
    wire iomem_mux__slave_in__bvalid_out[CPU_COUNT];
    wire iomem_mux__slave_in__bready_in[CPU_COUNT];
    wire[4-1:0] iomem_mux__slave_in__bid_out[CPU_COUNT];
    wire iomem_mux__slave_in__arvalid_in[CPU_COUNT];
    wire iomem_mux__slave_in__arready_out[CPU_COUNT];
    wire[32-1:0] iomem_mux__slave_in__araddr_in[CPU_COUNT];
    wire[4-1:0] iomem_mux__slave_in__arid_in[CPU_COUNT];
    wire iomem_mux__slave_in__rvalid_out[CPU_COUNT];
    wire iomem_mux__slave_in__rready_in[CPU_COUNT];
    wire[256-1:0] iomem_mux__slave_in__rdata_out[CPU_COUNT];
    wire iomem_mux__slave_in__rlast_out[CPU_COUNT];
    wire[4-1:0] iomem_mux__slave_in__rid_out[CPU_COUNT];
    wire iomem_mux__masters_out__awvalid_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__awready_in[CPU_COUNT][2];
    wire[32-1:0] iomem_mux__masters_out__awaddr_out[CPU_COUNT][2];
    wire[4-1:0] iomem_mux__masters_out__awid_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__wvalid_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__wready_in[CPU_COUNT][2];
    wire[256-1:0] iomem_mux__masters_out__wdata_out[CPU_COUNT][2];
    wire[256/'h8-1:0] iomem_mux__masters_out__wstrb_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__wlast_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__bvalid_in[CPU_COUNT][2];
    wire iomem_mux__masters_out__bready_out[CPU_COUNT][2];
    wire[4-1:0] iomem_mux__masters_out__bid_in[CPU_COUNT][2];
    wire iomem_mux__masters_out__arvalid_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__arready_in[CPU_COUNT][2];
    wire[32-1:0] iomem_mux__masters_out__araddr_out[CPU_COUNT][2];
    wire[4-1:0] iomem_mux__masters_out__arid_out[CPU_COUNT][2];
    wire iomem_mux__masters_out__rvalid_in[CPU_COUNT][2];
    wire iomem_mux__masters_out__rready_out[CPU_COUNT][2];
    wire[256-1:0] iomem_mux__masters_out__rdata_in[CPU_COUNT][2];
    wire iomem_mux__masters_out__rlast_in[CPU_COUNT][2];
    wire[4-1:0] iomem_mux__masters_out__rid_in[CPU_COUNT][2];
    wire[31:0] iomem_mux__region_base_in[CPU_COUNT][2];
    wire[31:0] iomem_mux__region_size_in[CPU_COUNT][2];
    generate
    for (__i=0; __i < CPU_COUNT; __i = __i + 1) begin
        Axi4RegionMux #(
        2
,       32
,       4
,       256
        ) iomem_mux (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .slave_in__awvalid_in(iomem_mux__slave_in__awvalid_in[__i])
        ,           .slave_in__awready_out(iomem_mux__slave_in__awready_out[__i])
        ,           .slave_in__awaddr_in(iomem_mux__slave_in__awaddr_in[__i])
        ,           .slave_in__awid_in(iomem_mux__slave_in__awid_in[__i])
        ,           .slave_in__wvalid_in(iomem_mux__slave_in__wvalid_in[__i])
        ,           .slave_in__wready_out(iomem_mux__slave_in__wready_out[__i])
        ,           .slave_in__wdata_in(iomem_mux__slave_in__wdata_in[__i])
        ,           .slave_in__wstrb_in(iomem_mux__slave_in__wstrb_in[__i])
        ,           .slave_in__wlast_in(iomem_mux__slave_in__wlast_in[__i])
        ,           .slave_in__bvalid_out(iomem_mux__slave_in__bvalid_out[__i])
        ,           .slave_in__bready_in(iomem_mux__slave_in__bready_in[__i])
        ,           .slave_in__bid_out(iomem_mux__slave_in__bid_out[__i])
        ,           .slave_in__arvalid_in(iomem_mux__slave_in__arvalid_in[__i])
        ,           .slave_in__arready_out(iomem_mux__slave_in__arready_out[__i])
        ,           .slave_in__araddr_in(iomem_mux__slave_in__araddr_in[__i])
        ,           .slave_in__arid_in(iomem_mux__slave_in__arid_in[__i])
        ,           .slave_in__rvalid_out(iomem_mux__slave_in__rvalid_out[__i])
        ,           .slave_in__rready_in(iomem_mux__slave_in__rready_in[__i])
        ,           .slave_in__rdata_out(iomem_mux__slave_in__rdata_out[__i])
        ,           .slave_in__rlast_out(iomem_mux__slave_in__rlast_out[__i])
        ,           .slave_in__rid_out(iomem_mux__slave_in__rid_out[__i])
        ,           .masters_out__awvalid_out(iomem_mux__masters_out__awvalid_out[__i])
        ,           .masters_out__awready_in(iomem_mux__masters_out__awready_in[__i])
        ,           .masters_out__awaddr_out(iomem_mux__masters_out__awaddr_out[__i])
        ,           .masters_out__awid_out(iomem_mux__masters_out__awid_out[__i])
        ,           .masters_out__wvalid_out(iomem_mux__masters_out__wvalid_out[__i])
        ,           .masters_out__wready_in(iomem_mux__masters_out__wready_in[__i])
        ,           .masters_out__wdata_out(iomem_mux__masters_out__wdata_out[__i])
        ,           .masters_out__wstrb_out(iomem_mux__masters_out__wstrb_out[__i])
        ,           .masters_out__wlast_out(iomem_mux__masters_out__wlast_out[__i])
        ,           .masters_out__bvalid_in(iomem_mux__masters_out__bvalid_in[__i])
        ,           .masters_out__bready_out(iomem_mux__masters_out__bready_out[__i])
        ,           .masters_out__bid_in(iomem_mux__masters_out__bid_in[__i])
        ,           .masters_out__arvalid_out(iomem_mux__masters_out__arvalid_out[__i])
        ,           .masters_out__arready_in(iomem_mux__masters_out__arready_in[__i])
        ,           .masters_out__araddr_out(iomem_mux__masters_out__araddr_out[__i])
        ,           .masters_out__arid_out(iomem_mux__masters_out__arid_out[__i])
        ,           .masters_out__rvalid_in(iomem_mux__masters_out__rvalid_in[__i])
        ,           .masters_out__rready_out(iomem_mux__masters_out__rready_out[__i])
        ,           .masters_out__rdata_in(iomem_mux__masters_out__rdata_in[__i])
        ,           .masters_out__rlast_in(iomem_mux__masters_out__rlast_in[__i])
        ,           .masters_out__rid_in(iomem_mux__masters_out__rid_in[__i])
        ,           .region_base_in(iomem_mux__region_base_in[__i])
        ,           .region_size_in(iomem_mux__region_size_in[__i])
        );
    end
    endgenerate

    // tmp variables


    always_comb begin : rx_read_valid_comb_func  // rx_read_valid_comb_func
        logic[31:0] index;
        rx_read_valid_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            rx_read_valid_comb[index] = packet_dma__rx_read_valid_out[index];
        end
    end

    always_comb begin : rx_read_handle_comb_func  // rx_read_handle_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        logic[30-1:0] command;
        rx_read_handle_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            command = {packet_dma__rx_read_length_out[index], packet_dma__rx_read_handle_out[index]};
            for (_bit='h0;_bit < HANDLE_BITS;_bit=_bit+1) begin
                rx_read_handle_comb[(index*HANDLE_BITS) + _bit] = command[_bit];
            end
        end
    end

    always_comb begin : rx_read_length_comb_func  // rx_read_length_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        logic[30-1:0] command;
        rx_read_length_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            command = {packet_dma__rx_read_length_out[index], packet_dma__rx_read_handle_out[index]};
            for (_bit='h0;_bit < FRAME_LENGTH_BITS;_bit=_bit+1) begin
                rx_read_length_comb[(index*FRAME_LENGTH_BITS) + _bit] = command[HANDLE_BITS + _bit];
            end
        end
    end

    always_comb begin : rx_ready_comb_func  // rx_ready_comb_func
        logic[31:0] index;
        rx_ready_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            rx_ready_comb[index] = packet_dma__rx_ready_out[index];
        end
    end

    always_comb begin : rx_stream_pack_comb_func  // rx_stream_pack_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            rx_stream_pack_comb[index] = 'h0;
            for (_bit='h0;_bit < 'h100;_bit=_bit+1) begin
                rx_stream_pack_comb[index][_bit] = rx_data_in[(index*'h100) + _bit];
            end
            for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
                rx_stream_pack_comb[index]['h100 + _bit] = rx_keep_in[(index*'h20) + _bit];
            end
            rx_stream_pack_comb[index]['h120] = rx_sop_in[index];
            rx_stream_pack_comb[index]['h121] = rx_eop_in[index];
        end
    end

    always_comb begin : from_system_pack_comb_func  // from_system_pack_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            from_system_pack_comb[index] = 'h0;
            for (_bit='h0;_bit < 'h100;_bit=_bit+1) begin
                from_system_pack_comb[index][_bit] = from_system_data_in[(index*'h100) + _bit];
            end
            for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
                from_system_pack_comb[index]['h100 + _bit] = from_system_keep_in[(index*'h20) + _bit];
            end
            from_system_pack_comb[index]['h120] = from_system_sop_in[index];
            from_system_pack_comb[index]['h121] = from_system_eop_in[index];
        end
    end

    always_comb begin : to_system_valid_comb_func  // to_system_valid_comb_func
        logic[31:0] index;
        to_system_valid_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_system_valid_comb[index] = packet_dma__system_tx_valid_out[index];
        end
    end

    always_comb begin : to_system_data_comb_func  // to_system_data_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        to_system_data_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            for (_bit='h0;_bit < 'h100;_bit=_bit+1) begin
                to_system_data_comb[(index*'h100) + _bit] = packet_dma__system_tx_data_out[index][_bit];
            end
        end
    end

    always_comb begin : to_system_keep_comb_func  // to_system_keep_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        to_system_keep_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
                to_system_keep_comb[(index*'h20) + _bit] = packet_dma__system_tx_keep_out[index][_bit];
            end
        end
    end

    always_comb begin : to_system_sop_comb_func  // to_system_sop_comb_func
        logic[31:0] index;
        to_system_sop_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_system_sop_comb[index] = packet_dma__system_tx_sop_out[index];
        end
    end

    always_comb begin : to_system_eop_comb_func  // to_system_eop_comb_func
        logic[31:0] index;
        to_system_eop_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_system_eop_comb[index] = packet_dma__system_tx_eop_out[index];
        end
    end

    always_comb begin : to_network_valid_comb_func  // to_network_valid_comb_func
        logic[31:0] index;
        to_network_valid_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_network_valid_comb[index] = packet_dma__network_tx_valid_out[index];
        end
    end

    always_comb begin : to_network_data_comb_func  // to_network_data_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        to_network_data_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            for (_bit='h0;_bit < 'h100;_bit=_bit+1) begin
                to_network_data_comb[(index*'h100) + _bit] = packet_dma__network_tx_data_out[index][_bit];
            end
        end
    end

    always_comb begin : to_network_keep_comb_func  // to_network_keep_comb_func
        logic[31:0] index;
        logic[31:0] _bit;
        to_network_keep_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
                to_network_keep_comb[(index*'h20) + _bit] = packet_dma__network_tx_keep_out[index][_bit];
            end
        end
    end

    always_comb begin : to_network_sop_comb_func  // to_network_sop_comb_func
        logic[31:0] index;
        to_network_sop_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_network_sop_comb[index] = packet_dma__network_tx_sop_out[index];
        end
    end

    always_comb begin : to_network_eop_comb_func  // to_network_eop_comb_func
        logic[31:0] index;
        to_network_eop_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            to_network_eop_comb[index] = packet_dma__network_tx_eop_out[index];
        end
    end

    always_comb begin : from_system_ready_comb_func  // from_system_ready_comb_func
        logic[31:0] index;
        from_system_ready_comb = 'h0;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
            from_system_ready_comb[index] = packet_dma__system_rx_ready_out[index];
        end
    end

    generate  // _assign
        genvar gindex;
        genvar gcore;
        assign descriptor_ready_out = descriptor_fetcher__descriptor_ready_out['h0];
        assign rx_read_valid_out = rx_read_valid_comb;
        assign rx_read_handle_out = rx_read_handle_comb;
        assign rx_read_length_out = rx_read_length_comb;
        assign rx_ready_out = rx_ready_comb;
        assign to_system_valid_out = to_system_valid_comb;
        assign to_system_data_out = to_system_data_comb;
        assign to_system_keep_out = to_system_keep_comb;
        assign to_system_sop_out = to_system_sop_comb;
        assign to_system_eop_out = to_system_eop_comb;
        assign from_system_ready_out = from_system_ready_comb;
        assign to_network_valid_out = to_network_valid_comb;
        assign to_network_data_out = to_network_data_comb;
        assign to_network_keep_out = to_network_keep_comb;
        assign to_network_sop_out = to_network_sop_comb;
        assign to_network_eop_out = to_network_eop_comb;
        for (gindex='h0;gindex < CPU_COUNT;gindex=gindex+1) begin
            assign descriptor_fetcher__descriptor_valid_in[gindex] = descriptor_valid_in;
            assign descriptor_fetcher__descriptor_data_in[gindex] = descriptor_data_in;
            assign descriptor_fetcher__descriptor_word_in[gindex] = descriptor_word_in;
            assign descriptor_fetcher__descriptor_sop_in[gindex] = descriptor_sop_in;
            assign descriptor_fetcher__descriptor_eop_in[gindex] = descriptor_eop_in;
            assign descriptor_fetcher__packet_command_ready_in[gindex] = packet_dma__command_ready_out[gindex];
            assign packet_dma__descriptor_command_valid_in[gindex] = descriptor_fetcher__packet_command_valid_out[gindex];
            assign packet_dma__descriptor_command_handle_in[gindex] = descriptor_fetcher__packet_command_handle_out[gindex];
            assign packet_dma__descriptor_command_length_in[gindex] = descriptor_fetcher__packet_command_length_out[gindex];
            assign packet_dma__descriptor_command_system_in[gindex] = descriptor_fetcher__packet_command_system_out[gindex];
            assign iomem_mux__slave_in__awvalid_in[gindex] = cpu__iomem__awvalid_out[gindex];
            assign iomem_mux__slave_in__awaddr_in[gindex] = cpu__iomem__awaddr_out[gindex];
            assign iomem_mux__slave_in__awid_in[gindex] = cpu__iomem__awid_out[gindex];
            assign iomem_mux__slave_in__wvalid_in[gindex] = cpu__iomem__wvalid_out[gindex];
            assign iomem_mux__slave_in__wdata_in[gindex] = cpu__iomem__wdata_out[gindex];
            assign iomem_mux__slave_in__wstrb_in[gindex] = cpu__iomem__wstrb_out[gindex];
            assign iomem_mux__slave_in__wlast_in[gindex] = cpu__iomem__wlast_out[gindex];
            assign iomem_mux__slave_in__bready_in[gindex] = cpu__iomem__bready_out[gindex];
            assign iomem_mux__slave_in__arvalid_in[gindex] = cpu__iomem__arvalid_out[gindex];
            assign iomem_mux__slave_in__araddr_in[gindex] = cpu__iomem__araddr_out[gindex];
            assign iomem_mux__slave_in__arid_in[gindex] = cpu__iomem__arid_out[gindex];
            assign iomem_mux__slave_in__rready_in[gindex] = cpu__iomem__rready_out[gindex];
            assign cpu__iomem__awready_in[gindex] = iomem_mux__slave_in__awready_out[gindex];
            assign cpu__iomem__wready_in[gindex] = iomem_mux__slave_in__wready_out[gindex];
            assign cpu__iomem__bvalid_in[gindex] = iomem_mux__slave_in__bvalid_out[gindex];
            assign cpu__iomem__bid_in[gindex] = iomem_mux__slave_in__bid_out[gindex];
            assign cpu__iomem__arready_in[gindex] = iomem_mux__slave_in__arready_out[gindex];
            assign cpu__iomem__rvalid_in[gindex] = iomem_mux__slave_in__rvalid_out[gindex];
            assign cpu__iomem__rdata_in[gindex] = iomem_mux__slave_in__rdata_out[gindex];
            assign cpu__iomem__rlast_in[gindex] = iomem_mux__slave_in__rlast_out[gindex];
            assign cpu__iomem__rid_in[gindex] = iomem_mux__slave_in__rid_out[gindex];
            assign iomem_mux__region_base_in[gindex]['h0] = FETCHER_BASE;
            assign iomem_mux__region_size_in[gindex]['h0] = FETCHER_SIZE;
            assign iomem_mux__region_base_in[gindex]['h1] = DMA_BASE;
            assign iomem_mux__region_size_in[gindex]['h1] = DMA_SIZE;
            assign descriptor_fetcher__mmio__awvalid_in[gindex] = iomem_mux__masters_out__awvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__awaddr_in[gindex] = iomem_mux__masters_out__awaddr_out[gindex]['h0];
            assign descriptor_fetcher__mmio__awid_in[gindex] = iomem_mux__masters_out__awid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wvalid_in[gindex] = iomem_mux__masters_out__wvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wdata_in[gindex] = iomem_mux__masters_out__wdata_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wstrb_in[gindex] = iomem_mux__masters_out__wstrb_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wlast_in[gindex] = iomem_mux__masters_out__wlast_out[gindex]['h0];
            assign descriptor_fetcher__mmio__bready_in[gindex] = iomem_mux__masters_out__bready_out[gindex]['h0];
            assign descriptor_fetcher__mmio__arvalid_in[gindex] = iomem_mux__masters_out__arvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__araddr_in[gindex] = iomem_mux__masters_out__araddr_out[gindex]['h0];
            assign descriptor_fetcher__mmio__arid_in[gindex] = iomem_mux__masters_out__arid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__rready_in[gindex] = iomem_mux__masters_out__rready_out[gindex]['h0];
            assign iomem_mux__masters_out__awready_in[gindex]['h0] = descriptor_fetcher__mmio__awready_out[gindex];
            assign iomem_mux__masters_out__wready_in[gindex]['h0] = descriptor_fetcher__mmio__wready_out[gindex];
            assign iomem_mux__masters_out__bvalid_in[gindex]['h0] = descriptor_fetcher__mmio__bvalid_out[gindex];
            assign iomem_mux__masters_out__bid_in[gindex]['h0] = descriptor_fetcher__mmio__bid_out[gindex];
            assign iomem_mux__masters_out__arready_in[gindex]['h0] = descriptor_fetcher__mmio__arready_out[gindex];
            assign iomem_mux__masters_out__rvalid_in[gindex]['h0] = descriptor_fetcher__mmio__rvalid_out[gindex];
            assign iomem_mux__masters_out__rdata_in[gindex]['h0] = descriptor_fetcher__mmio__rdata_out[gindex];
            assign iomem_mux__masters_out__rlast_in[gindex]['h0] = descriptor_fetcher__mmio__rlast_out[gindex];
            assign iomem_mux__masters_out__rid_in[gindex]['h0] = descriptor_fetcher__mmio__rid_out[gindex];
            assign packet_dma__mmio__awvalid_in[gindex] = iomem_mux__masters_out__awvalid_out[gindex]['h1];
            assign packet_dma__mmio__awaddr_in[gindex] = iomem_mux__masters_out__awaddr_out[gindex]['h1];
            assign packet_dma__mmio__awid_in[gindex] = iomem_mux__masters_out__awid_out[gindex]['h1];
            assign packet_dma__mmio__wvalid_in[gindex] = iomem_mux__masters_out__wvalid_out[gindex]['h1];
            assign packet_dma__mmio__wdata_in[gindex] = iomem_mux__masters_out__wdata_out[gindex]['h1];
            assign packet_dma__mmio__wstrb_in[gindex] = iomem_mux__masters_out__wstrb_out[gindex]['h1];
            assign packet_dma__mmio__wlast_in[gindex] = iomem_mux__masters_out__wlast_out[gindex]['h1];
            assign packet_dma__mmio__bready_in[gindex] = iomem_mux__masters_out__bready_out[gindex]['h1];
            assign packet_dma__mmio__arvalid_in[gindex] = iomem_mux__masters_out__arvalid_out[gindex]['h1];
            assign packet_dma__mmio__araddr_in[gindex] = iomem_mux__masters_out__araddr_out[gindex]['h1];
            assign packet_dma__mmio__arid_in[gindex] = iomem_mux__masters_out__arid_out[gindex]['h1];
            assign packet_dma__mmio__rready_in[gindex] = iomem_mux__masters_out__rready_out[gindex]['h1];
            assign iomem_mux__masters_out__awready_in[gindex]['h1] = packet_dma__mmio__awready_out[gindex];
            assign iomem_mux__masters_out__wready_in[gindex]['h1] = packet_dma__mmio__wready_out[gindex];
            assign iomem_mux__masters_out__bvalid_in[gindex]['h1] = packet_dma__mmio__bvalid_out[gindex];
            assign iomem_mux__masters_out__bid_in[gindex]['h1] = packet_dma__mmio__bid_out[gindex];
            assign iomem_mux__masters_out__arready_in[gindex]['h1] = packet_dma__mmio__arready_out[gindex];
            assign iomem_mux__masters_out__rvalid_in[gindex]['h1] = packet_dma__mmio__rvalid_out[gindex];
            assign iomem_mux__masters_out__rdata_in[gindex]['h1] = packet_dma__mmio__rdata_out[gindex];
            assign iomem_mux__masters_out__rlast_in[gindex]['h1] = packet_dma__mmio__rlast_out[gindex];
            assign iomem_mux__masters_out__rid_in[gindex]['h1] = packet_dma__mmio__rid_out[gindex];
            assign cpu__dma_in__awvalid_in[gindex] = packet_dma__l2_dma__awvalid_out[gindex];
            assign cpu__dma_in__awaddr_in[gindex] = packet_dma__l2_dma__awaddr_out[gindex];
            assign cpu__dma_in__awid_in[gindex] = packet_dma__l2_dma__awid_out[gindex];
            assign cpu__dma_in__wvalid_in[gindex] = packet_dma__l2_dma__wvalid_out[gindex];
            assign cpu__dma_in__wdata_in[gindex] = packet_dma__l2_dma__wdata_out[gindex];
            assign cpu__dma_in__wstrb_in[gindex] = packet_dma__l2_dma__wstrb_out[gindex];
            assign cpu__dma_in__wlast_in[gindex] = packet_dma__l2_dma__wlast_out[gindex];
            assign cpu__dma_in__bready_in[gindex] = packet_dma__l2_dma__bready_out[gindex];
            assign cpu__dma_in__arvalid_in[gindex] = packet_dma__l2_dma__arvalid_out[gindex];
            assign cpu__dma_in__araddr_in[gindex] = packet_dma__l2_dma__araddr_out[gindex];
            assign cpu__dma_in__arid_in[gindex] = packet_dma__l2_dma__arid_out[gindex];
            assign cpu__dma_in__rready_in[gindex] = packet_dma__l2_dma__rready_out[gindex];
            assign packet_dma__l2_dma__awready_in[gindex] = cpu__dma_in__awready_out[gindex];
            assign packet_dma__l2_dma__wready_in[gindex] = cpu__dma_in__wready_out[gindex];
            assign packet_dma__l2_dma__bvalid_in[gindex] = cpu__dma_in__bvalid_out[gindex];
            assign packet_dma__l2_dma__bid_in[gindex] = cpu__dma_in__bid_out[gindex];
            assign packet_dma__l2_dma__arready_in[gindex] = cpu__dma_in__arready_out[gindex];
            assign packet_dma__l2_dma__rvalid_in[gindex] = cpu__dma_in__rvalid_out[gindex];
            assign packet_dma__l2_dma__rdata_in[gindex] = cpu__dma_in__rdata_out[gindex];
            assign packet_dma__l2_dma__rlast_in[gindex] = cpu__dma_in__rlast_out[gindex];
            assign packet_dma__l2_dma__rid_in[gindex] = cpu__dma_in__rid_out[gindex];
            assign packet_dma__rx_read_ready_in[gindex] = rx_read_ready_in[gindex];
            assign packet_dma__rx_valid_in[gindex] = rx_valid_in[gindex];
            assign packet_dma__rx_data_in[gindex] = rx_data_in[gindex*'h100 +:256];
            assign packet_dma__rx_keep_in[gindex] = rx_keep_in[gindex*'h20 +:32];
            assign packet_dma__rx_sop_in[gindex] = rx_sop_in[gindex];
            assign packet_dma__rx_eop_in[gindex] = rx_eop_in[gindex];
            assign packet_dma__system_tx_ready_in[gindex] = to_system_ready_in[gindex];
            assign packet_dma__system_rx_valid_in[gindex] = from_system_valid_in[gindex];
            assign packet_dma__system_rx_data_in[gindex] = from_system_data_in[gindex*'h100 +:256];
            assign packet_dma__system_rx_keep_in[gindex] = from_system_keep_in[gindex*'h20 +:32];
            assign packet_dma__system_rx_sop_in[gindex] = from_system_sop_in[gindex];
            assign packet_dma__system_rx_eop_in[gindex] = from_system_eop_in[gindex];
            assign packet_dma__network_tx_ready_in[gindex] = to_network_ready_in[gindex];
            assign ddr__awvalid_out[gindex] = cpu__memory__awvalid_out[gindex];
            assign ddr__awaddr_out[gindex] = cpu__memory__awaddr_out[gindex];
            assign ddr__awid_out[gindex] = cpu__memory__awid_out[gindex];
            assign ddr__wvalid_out[gindex] = cpu__memory__wvalid_out[gindex];
            assign ddr__wdata_out[gindex] = cpu__memory__wdata_out[gindex];
            assign ddr__wstrb_out[gindex] = cpu__memory__wstrb_out[gindex];
            assign ddr__wlast_out[gindex] = cpu__memory__wlast_out[gindex];
            assign ddr__bready_out[gindex] = cpu__memory__bready_out[gindex];
            assign ddr__arvalid_out[gindex] = cpu__memory__arvalid_out[gindex];
            assign ddr__araddr_out[gindex] = cpu__memory__araddr_out[gindex];
            assign ddr__arid_out[gindex] = cpu__memory__arid_out[gindex];
            assign ddr__rready_out[gindex] = cpu__memory__rready_out[gindex];
            assign cpu__memory__awready_in[gindex] = ddr__awready_in[gindex];
            assign cpu__memory__wready_in[gindex] = ddr__wready_in[gindex];
            assign cpu__memory__bvalid_in[gindex] = ddr__bvalid_in[gindex];
            assign cpu__memory__bid_in[gindex] = ddr__bid_in[gindex];
            assign cpu__memory__arready_in[gindex] = ddr__arready_in[gindex];
            assign cpu__memory__rvalid_in[gindex] = ddr__rvalid_in[gindex];
            assign cpu__memory__rdata_in[gindex] = ddr__rdata_in[gindex];
            assign cpu__memory__rlast_in[gindex] = ddr__rlast_in[gindex];
            assign cpu__memory__rid_in[gindex] = ddr__rid_in[gindex];
            assign cpu__reset_pc_in[gindex] = unsigned'(32'(unsigned'(32'h0)));
            assign cpu__boot_hartid_in[gindex] = unsigned'(32'(unsigned'(32'((gindex*CPU_pkg::CORES)))));
            assign cpu__boot_dtb_addr_in[gindex] = unsigned'(32'(unsigned'(32'h0)));
            assign cpu__boot_priv_in[gindex] = unsigned'(2'(unsigned'(2'h3)));
            assign cpu__cache_invalidate_in[gindex] = cache_invalidate_in[gindex];
            for (gcore='h0;gcore < CPU_pkg::CORES;gcore=gcore+1) begin
                assign cpu__software_irq_in[gindex][gcore] = software_irq_in[(gindex*CPU_pkg::CORES) + gcore];
                assign cpu__timer_irq_in[gindex][gcore] = timer_irq_in[(gindex*CPU_pkg::CORES) + gcore];
                assign cpu__external_irq_in[gindex][gcore] = external_irq_in[(gindex*CPU_pkg::CORES) + gcore];
            end
            assign iomem_mux__slave_in__awvalid_in[gindex] = cpu__iomem__awvalid_out[gindex];
            assign iomem_mux__slave_in__awaddr_in[gindex] = cpu__iomem__awaddr_out[gindex];
            assign iomem_mux__slave_in__awid_in[gindex] = cpu__iomem__awid_out[gindex];
            assign iomem_mux__slave_in__wvalid_in[gindex] = cpu__iomem__wvalid_out[gindex];
            assign iomem_mux__slave_in__wdata_in[gindex] = cpu__iomem__wdata_out[gindex];
            assign iomem_mux__slave_in__wstrb_in[gindex] = cpu__iomem__wstrb_out[gindex];
            assign iomem_mux__slave_in__wlast_in[gindex] = cpu__iomem__wlast_out[gindex];
            assign iomem_mux__slave_in__bready_in[gindex] = cpu__iomem__bready_out[gindex];
            assign iomem_mux__slave_in__arvalid_in[gindex] = cpu__iomem__arvalid_out[gindex];
            assign iomem_mux__slave_in__araddr_in[gindex] = cpu__iomem__araddr_out[gindex];
            assign iomem_mux__slave_in__arid_in[gindex] = cpu__iomem__arid_out[gindex];
            assign iomem_mux__slave_in__rready_in[gindex] = cpu__iomem__rready_out[gindex];
            assign cpu__iomem__awready_in[gindex] = iomem_mux__slave_in__awready_out[gindex];
            assign cpu__iomem__wready_in[gindex] = iomem_mux__slave_in__wready_out[gindex];
            assign cpu__iomem__bvalid_in[gindex] = iomem_mux__slave_in__bvalid_out[gindex];
            assign cpu__iomem__bid_in[gindex] = iomem_mux__slave_in__bid_out[gindex];
            assign cpu__iomem__arready_in[gindex] = iomem_mux__slave_in__arready_out[gindex];
            assign cpu__iomem__rvalid_in[gindex] = iomem_mux__slave_in__rvalid_out[gindex];
            assign cpu__iomem__rdata_in[gindex] = iomem_mux__slave_in__rdata_out[gindex];
            assign cpu__iomem__rlast_in[gindex] = iomem_mux__slave_in__rlast_out[gindex];
            assign cpu__iomem__rid_in[gindex] = iomem_mux__slave_in__rid_out[gindex];
            assign descriptor_fetcher__mmio__awvalid_in[gindex] = iomem_mux__masters_out__awvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__awaddr_in[gindex] = iomem_mux__masters_out__awaddr_out[gindex]['h0];
            assign descriptor_fetcher__mmio__awid_in[gindex] = iomem_mux__masters_out__awid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wvalid_in[gindex] = iomem_mux__masters_out__wvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wdata_in[gindex] = iomem_mux__masters_out__wdata_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wstrb_in[gindex] = iomem_mux__masters_out__wstrb_out[gindex]['h0];
            assign descriptor_fetcher__mmio__wlast_in[gindex] = iomem_mux__masters_out__wlast_out[gindex]['h0];
            assign descriptor_fetcher__mmio__bready_in[gindex] = iomem_mux__masters_out__bready_out[gindex]['h0];
            assign descriptor_fetcher__mmio__arvalid_in[gindex] = iomem_mux__masters_out__arvalid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__araddr_in[gindex] = iomem_mux__masters_out__araddr_out[gindex]['h0];
            assign descriptor_fetcher__mmio__arid_in[gindex] = iomem_mux__masters_out__arid_out[gindex]['h0];
            assign descriptor_fetcher__mmio__rready_in[gindex] = iomem_mux__masters_out__rready_out[gindex]['h0];
            assign iomem_mux__masters_out__awready_in[gindex]['h0] = descriptor_fetcher__mmio__awready_out[gindex];
            assign iomem_mux__masters_out__wready_in[gindex]['h0] = descriptor_fetcher__mmio__wready_out[gindex];
            assign iomem_mux__masters_out__bvalid_in[gindex]['h0] = descriptor_fetcher__mmio__bvalid_out[gindex];
            assign iomem_mux__masters_out__bid_in[gindex]['h0] = descriptor_fetcher__mmio__bid_out[gindex];
            assign iomem_mux__masters_out__arready_in[gindex]['h0] = descriptor_fetcher__mmio__arready_out[gindex];
            assign iomem_mux__masters_out__rvalid_in[gindex]['h0] = descriptor_fetcher__mmio__rvalid_out[gindex];
            assign iomem_mux__masters_out__rdata_in[gindex]['h0] = descriptor_fetcher__mmio__rdata_out[gindex];
            assign iomem_mux__masters_out__rlast_in[gindex]['h0] = descriptor_fetcher__mmio__rlast_out[gindex];
            assign iomem_mux__masters_out__rid_in[gindex]['h0] = descriptor_fetcher__mmio__rid_out[gindex];
            assign packet_dma__mmio__awvalid_in[gindex] = iomem_mux__masters_out__awvalid_out[gindex]['h1];
            assign packet_dma__mmio__awaddr_in[gindex] = iomem_mux__masters_out__awaddr_out[gindex]['h1];
            assign packet_dma__mmio__awid_in[gindex] = iomem_mux__masters_out__awid_out[gindex]['h1];
            assign packet_dma__mmio__wvalid_in[gindex] = iomem_mux__masters_out__wvalid_out[gindex]['h1];
            assign packet_dma__mmio__wdata_in[gindex] = iomem_mux__masters_out__wdata_out[gindex]['h1];
            assign packet_dma__mmio__wstrb_in[gindex] = iomem_mux__masters_out__wstrb_out[gindex]['h1];
            assign packet_dma__mmio__wlast_in[gindex] = iomem_mux__masters_out__wlast_out[gindex]['h1];
            assign packet_dma__mmio__bready_in[gindex] = iomem_mux__masters_out__bready_out[gindex]['h1];
            assign packet_dma__mmio__arvalid_in[gindex] = iomem_mux__masters_out__arvalid_out[gindex]['h1];
            assign packet_dma__mmio__araddr_in[gindex] = iomem_mux__masters_out__araddr_out[gindex]['h1];
            assign packet_dma__mmio__arid_in[gindex] = iomem_mux__masters_out__arid_out[gindex]['h1];
            assign packet_dma__mmio__rready_in[gindex] = iomem_mux__masters_out__rready_out[gindex]['h1];
            assign iomem_mux__masters_out__awready_in[gindex]['h1] = packet_dma__mmio__awready_out[gindex];
            assign iomem_mux__masters_out__wready_in[gindex]['h1] = packet_dma__mmio__wready_out[gindex];
            assign iomem_mux__masters_out__bvalid_in[gindex]['h1] = packet_dma__mmio__bvalid_out[gindex];
            assign iomem_mux__masters_out__bid_in[gindex]['h1] = packet_dma__mmio__bid_out[gindex];
            assign iomem_mux__masters_out__arready_in[gindex]['h1] = packet_dma__mmio__arready_out[gindex];
            assign iomem_mux__masters_out__rvalid_in[gindex]['h1] = packet_dma__mmio__rvalid_out[gindex];
            assign iomem_mux__masters_out__rdata_in[gindex]['h1] = packet_dma__mmio__rdata_out[gindex];
            assign iomem_mux__masters_out__rlast_in[gindex]['h1] = packet_dma__mmio__rlast_out[gindex];
            assign iomem_mux__masters_out__rid_in[gindex]['h1] = packet_dma__mmio__rid_out[gindex];
            assign cpu__dma_in__awvalid_in[gindex] = packet_dma__l2_dma__awvalid_out[gindex];
            assign cpu__dma_in__awaddr_in[gindex] = packet_dma__l2_dma__awaddr_out[gindex];
            assign cpu__dma_in__awid_in[gindex] = packet_dma__l2_dma__awid_out[gindex];
            assign cpu__dma_in__wvalid_in[gindex] = packet_dma__l2_dma__wvalid_out[gindex];
            assign cpu__dma_in__wdata_in[gindex] = packet_dma__l2_dma__wdata_out[gindex];
            assign cpu__dma_in__wstrb_in[gindex] = packet_dma__l2_dma__wstrb_out[gindex];
            assign cpu__dma_in__wlast_in[gindex] = packet_dma__l2_dma__wlast_out[gindex];
            assign cpu__dma_in__bready_in[gindex] = packet_dma__l2_dma__bready_out[gindex];
            assign cpu__dma_in__arvalid_in[gindex] = packet_dma__l2_dma__arvalid_out[gindex];
            assign cpu__dma_in__araddr_in[gindex] = packet_dma__l2_dma__araddr_out[gindex];
            assign cpu__dma_in__arid_in[gindex] = packet_dma__l2_dma__arid_out[gindex];
            assign cpu__dma_in__rready_in[gindex] = packet_dma__l2_dma__rready_out[gindex];
            assign packet_dma__l2_dma__awready_in[gindex] = cpu__dma_in__awready_out[gindex];
            assign packet_dma__l2_dma__wready_in[gindex] = cpu__dma_in__wready_out[gindex];
            assign packet_dma__l2_dma__bvalid_in[gindex] = cpu__dma_in__bvalid_out[gindex];
            assign packet_dma__l2_dma__bid_in[gindex] = cpu__dma_in__bid_out[gindex];
            assign packet_dma__l2_dma__arready_in[gindex] = cpu__dma_in__arready_out[gindex];
            assign packet_dma__l2_dma__rvalid_in[gindex] = cpu__dma_in__rvalid_out[gindex];
            assign packet_dma__l2_dma__rdata_in[gindex] = cpu__dma_in__rdata_out[gindex];
            assign packet_dma__l2_dma__rlast_in[gindex] = cpu__dma_in__rlast_out[gindex];
            assign packet_dma__l2_dma__rid_in[gindex] = cpu__dma_in__rid_out[gindex];
            assign ddr__awvalid_out[gindex] = cpu__memory__awvalid_out[gindex];
            assign ddr__awaddr_out[gindex] = cpu__memory__awaddr_out[gindex];
            assign ddr__awid_out[gindex] = cpu__memory__awid_out[gindex];
            assign ddr__wvalid_out[gindex] = cpu__memory__wvalid_out[gindex];
            assign ddr__wdata_out[gindex] = cpu__memory__wdata_out[gindex];
            assign ddr__wstrb_out[gindex] = cpu__memory__wstrb_out[gindex];
            assign ddr__wlast_out[gindex] = cpu__memory__wlast_out[gindex];
            assign ddr__bready_out[gindex] = cpu__memory__bready_out[gindex];
            assign ddr__arvalid_out[gindex] = cpu__memory__arvalid_out[gindex];
            assign ddr__araddr_out[gindex] = cpu__memory__araddr_out[gindex];
            assign ddr__arid_out[gindex] = cpu__memory__arid_out[gindex];
            assign ddr__rready_out[gindex] = cpu__memory__rready_out[gindex];
            assign cpu__memory__awready_in[gindex] = ddr__awready_in[gindex];
            assign cpu__memory__wready_in[gindex] = ddr__wready_in[gindex];
            assign cpu__memory__bvalid_in[gindex] = ddr__bvalid_in[gindex];
            assign cpu__memory__bid_in[gindex] = ddr__bid_in[gindex];
            assign cpu__memory__arready_in[gindex] = ddr__arready_in[gindex];
            assign cpu__memory__rvalid_in[gindex] = ddr__rvalid_in[gindex];
            assign cpu__memory__rdata_in[gindex] = ddr__rdata_in[gindex];
            assign cpu__memory__rlast_in[gindex] = ddr__rlast_in[gindex];
            assign cpu__memory__rid_in[gindex] = ddr__rid_in[gindex];
            assign descriptor_fetcher__packet_command_ready_in[gindex] = packet_dma__command_ready_out[gindex];
            assign packet_dma__descriptor_command_valid_in[gindex] = descriptor_fetcher__packet_command_valid_out[gindex];
            assign packet_dma__descriptor_command_handle_in[gindex] = descriptor_fetcher__packet_command_handle_out[gindex];
            assign packet_dma__descriptor_command_length_in[gindex] = descriptor_fetcher__packet_command_length_out[gindex];
            assign packet_dma__descriptor_command_system_in[gindex] = descriptor_fetcher__packet_command_system_out[gindex];
        end
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] index;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
        end
    end
    endtask

    task _work_neg (input logic reset);
    begin: _work_neg
        logic[31:0] index;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
        logic[31:0] index;
        for (index='h0;index < CPU_COUNT;index=index+1) begin
        end
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
