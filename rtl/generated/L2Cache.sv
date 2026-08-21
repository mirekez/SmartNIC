`default_nettype none

import Predef_pkg::*;
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
import L2CacheFsmState_pkg::*;
import L2HitLookupComb_pkg::*;
import L2RequestGeometryComb_pkg::*;
import L2WordPairComb_pkg::*;
import CacheRequest_pkg::*;
import L2ActiveRequestComb_pkg::*;
import L2EvictCandidateComb_pkg::*;
import L2CpuWaitComb_pkg::*;
import L2IoWritePayloadComb_pkg::*;
import L2AxiRouteComb_pkg::*;
import L2AxiRequestNoveltyComb_pkg::*;
import CacheResponse_pkg::*;
import L2AxiAddressState_pkg::*;


module L2Cache #(
    parameter CACHE_SIZE = 'h4000
,   parameter PORT_BITWIDTH = 'h100
,   parameter CACHE_LINE_SIZE = 'h20
,   parameter WAYS = 'h4
,   parameter ADDR_BITS = 'h20
,   parameter MEM_ADDR_BITS = ADDR_BITS
,   parameter MEM_PORTS = 'h1
,   parameter CPU_PORTS = 'h1
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire i_mem_in__read_in[CPU_PORTS]
,   input wire i_mem_in__write_in[CPU_PORTS]
,   input wire[31:0] i_mem_in__addr_in[CPU_PORTS]
,   input wire[31:0] i_mem_in__write_data_in[CPU_PORTS]
,   input wire[7:0] i_mem_in__write_mask_in[CPU_PORTS]
,   input wire i_mem_in__cache_disable_in[CPU_PORTS]
,   output wire[PORT_BITWIDTH-1:0] i_mem_in__read_data_out[CPU_PORTS]
,   output wire i_mem_in__wait_out[CPU_PORTS]
,   input wire d_mem_in__read_in[CPU_PORTS]
,   input wire d_mem_in__write_in[CPU_PORTS]
,   input wire[31:0] d_mem_in__addr_in[CPU_PORTS]
,   input wire[31:0] d_mem_in__write_data_in[CPU_PORTS]
,   input wire[7:0] d_mem_in__write_mask_in[CPU_PORTS]
,   input wire d_mem_in__cache_disable_in[CPU_PORTS]
,   output wire[PORT_BITWIDTH-1:0] d_mem_in__read_data_out[CPU_PORTS]
,   output wire d_mem_in__wait_out[CPU_PORTS]
,   input wire[31:0] memory_base_in
,   input wire[31:0] memory_size_in
,   input wire[31:0] mem_region_size_in[MEM_PORTS]
,   input wire mem_region_uncached_in[MEM_PORTS]
,   input wire axi_in__awvalid_in[MEM_PORTS]
,   output wire axi_in__awready_out[MEM_PORTS]
,   input wire[ADDR_BITS-1:0] axi_in__awaddr_in[MEM_PORTS]
,   input wire[4-1:0] axi_in__awid_in[MEM_PORTS]
,   input wire axi_in__wvalid_in[MEM_PORTS]
,   output wire axi_in__wready_out[MEM_PORTS]
,   input wire[PORT_BITWIDTH-1:0] axi_in__wdata_in[MEM_PORTS]
,   input wire[PORT_BITWIDTH/'h8-1:0] axi_in__wstrb_in[MEM_PORTS]
,   input wire axi_in__wlast_in[MEM_PORTS]
,   output wire axi_in__bvalid_out[MEM_PORTS]
,   input wire axi_in__bready_in[MEM_PORTS]
,   output wire[4-1:0] axi_in__bid_out[MEM_PORTS]
,   input wire axi_in__arvalid_in[MEM_PORTS]
,   output wire axi_in__arready_out[MEM_PORTS]
,   input wire[ADDR_BITS-1:0] axi_in__araddr_in[MEM_PORTS]
,   input wire[4-1:0] axi_in__arid_in[MEM_PORTS]
,   output wire axi_in__rvalid_out[MEM_PORTS]
,   input wire axi_in__rready_in[MEM_PORTS]
,   output wire[PORT_BITWIDTH-1:0] axi_in__rdata_out[MEM_PORTS]
,   output wire axi_in__rlast_out[MEM_PORTS]
,   output wire[4-1:0] axi_in__rid_out[MEM_PORTS]
,   output wire axi_out__awvalid_out[MEM_PORTS]
,   input wire axi_out__awready_in[MEM_PORTS]
,   output wire[MEM_ADDR_BITS-1:0] axi_out__awaddr_out[MEM_PORTS]
,   output wire[4-1:0] axi_out__awid_out[MEM_PORTS]
,   output wire axi_out__wvalid_out[MEM_PORTS]
,   input wire axi_out__wready_in[MEM_PORTS]
,   output wire[PORT_BITWIDTH-1:0] axi_out__wdata_out[MEM_PORTS]
,   output wire[PORT_BITWIDTH/'h8-1:0] axi_out__wstrb_out[MEM_PORTS]
,   output wire axi_out__wlast_out[MEM_PORTS]
,   input wire axi_out__bvalid_in[MEM_PORTS]
,   output wire axi_out__bready_out[MEM_PORTS]
,   input wire[4-1:0] axi_out__bid_in[MEM_PORTS]
,   output wire axi_out__arvalid_out[MEM_PORTS]
,   input wire axi_out__arready_in[MEM_PORTS]
,   output wire[MEM_ADDR_BITS-1:0] axi_out__araddr_out[MEM_PORTS]
,   output wire[4-1:0] axi_out__arid_out[MEM_PORTS]
,   input wire axi_out__rvalid_in[MEM_PORTS]
,   output wire axi_out__rready_out[MEM_PORTS]
,   input wire[PORT_BITWIDTH-1:0] axi_out__rdata_in[MEM_PORTS]
,   input wire axi_out__rlast_in[MEM_PORTS]
,   input wire[4-1:0] axi_out__rid_in[MEM_PORTS]
,   input wire dma_line_valid_in
,   input wire[ADDR_BITS-1:0] dma_line_addr_in
,   input wire[CACHE_LINE_SIZE*'h8-1:0] dma_line_data_in
,   input wire[CACHE_LINE_SIZE-1:0] dma_line_keep_in
,   output wire dma_line_ready_out
,   input wire debugen_in
);
    localparam  LOCAL_DATA_BANKS = WAYS*((CACHE_LINE_SIZE/'h4));
    localparam  LOCAL_SET_BITS = $clog2((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS);
    localparam  LOCAL_TAG_RAM_BITS = (((((((ADDR_BITS - LOCAL_SET_BITS) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8;
    localparam  LINE_WORDS = CACHE_LINE_SIZE/'h4;
    localparam  PORT_BYTES = PORT_BITWIDTH/'h8;
    localparam  PORT_WORDS = PORT_BITWIDTH/'h20;
    localparam  LINE_BEATS = CACHE_LINE_SIZE/PORT_BYTES;
    localparam  SETS = (CACHE_SIZE/CACHE_LINE_SIZE)/WAYS;
    localparam  SET_BITS = $clog2(SETS);
    localparam  LINE_BITS = $clog2(CACHE_LINE_SIZE);
    localparam  TAG_BITS = (ADDR_BITS - SET_BITS) - LINE_BITS;
    localparam  DATA_BANKS = WAYS*LINE_WORDS;
    localparam  CPU_RESPONSE_BASE = 'h8;
    localparam  RESPONSE_SLOTS = 'h10;
    localparam  MEM_ADDR_MASK64 = ((MEM_ADDR_BITS>='h40)) ? (~64'h0) : ((((64'h1 <<< MEM_ADDR_BITS)) - 64'h1));
    localparam  LINE_BEAT_BITS = (LINE_BEATS<='h1) ? ('h1) : ($clog2(LINE_BEATS));
    localparam  WORD_BITS = $clog2(LINE_WORDS);
    localparam  WAY_BITS = (WAYS<='h1) ? ('h1) : ($clog2(WAYS));
    localparam  TAG_RAM_BITS = (((((TAG_BITS + 'h2) + 'h7))/'h8))*'h8;
    localparam  MEM_PORT_BITS = $clog2(MEM_PORTS);


    // regs and combs
    Axi4Responder4_256 axi_in_comb[MEM_PORTS];
    Axi4Driver32_4_256 axi_out_comb[MEM_PORTS];
    logic[31:0] data_bank_data_comb[LOCAL_DATA_BANKS];
    logic[LOCAL_DATA_BANKS-1:0] data_bank_write_comb;
    logic[WAYS-1:0] tag_bank_write_comb;
    logic[LOCAL_TAG_RAM_BITS-1:0] tag_bank_data_comb;
    logic[LOCAL_SET_BITS-1:0] l2_bank_addr_comb;
;
    logic[LOCAL_SET_BITS-1:0] tag_bank_addr_comb;
;
    logic l2_bank_read_comb;
;
    L2CpuWaitComb L2CacheWait___cpu_wait_comb[CPU_PORTS];
    L2HitLookupComb L2CacheTagData___hit_lookup_comb;
;
    L2WordPairComb L2CacheTagData___hit_write_pair_comb;
;
    L2WordPairComb L2CacheTagData___fill_write_pair_comb;
;
    logic[PORT_BITWIDTH-1:0] L2CacheTagData___cross_read_data_comb;
;
    logic[((((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8)-1:0] L2CacheTagData___tag_write_data_comb;
;
    logic[PORT_BITWIDTH-1:0] L2CacheTagData___read_data_comb[CPU_PORTS];
    L2IoWritePayloadComb L2CacheMemory___io_write_payload_comb;
;
    L2AxiRouteComb L2CacheMemory___axi_route_comb;
;
    Axi4Driver32_4_256 L2CacheMemory___axi_out_driver_comb;
;
    Axi4Responder4_256 L2CacheMemory___axi_out_selected_resp_comb;
;
    L2EvictCandidateComb L2CacheMemory___evict_candidate_comb;
;
    logic[PORT_BITWIDTH-1:0] L2CacheMemory___evict_line_comb;
;
    logic L2CacheMemory___req_uncached_region_comb;
;
    L2AxiRequestNoveltyComb L2CacheRequest___slave_request_novelty_comb;
;
    L2ActiveRequestComb L2CacheRequest___active_request_comb;
;
    L2RequestGeometryComb L2CacheRequest___request_geometry_comb;
;
    reg[DATA_BANKS-1:0][32-1:0] L2CacheState___lookup_data_reg;
    reg[WAYS-1:0][(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___lookup_tag_reg;
    L2HitLookupComb L2CacheState___lookup_hit_reg;
    L2EvictCandidateComb L2CacheState___lookup_evict_reg;
    reg[5-1:0] L2CacheState___state_reg;
    CacheRequest L2CacheState___req_reg;
    reg[3-1:0] L2CacheState___cpu_rr_reg;
    reg[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___victim_reg;
    reg[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___fill_way_reg;
    reg[$clog2((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)-1:0] L2CacheState___init_set_reg;
    CacheResponse[16-1:0] L2CacheState___response_reg;
    reg[PORT_BITWIDTH-1:0] L2CacheState___cross_low_reg;
    reg[PORT_BITWIDTH-1:0] L2CacheState___cross_high_reg;
    reg[PORT_BITWIDTH-1:0] L2CacheState___refill_data_reg;
    reg[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___fill_beat_reg;
    reg[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___evict_beat_reg;
    reg[(ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)-1:0] L2CacheState___evict_tag_reg;
    reg[CACHE_LINE_SIZE*'h8-1:0] L2CacheState___evict_line_reg;
    L2AxiAddressState[8-1:0] L2CacheState___slave_aw_reg;
    L2AxiAddressState[8-1:0] L2CacheState___slave_aw_seen_reg;
    L2AxiAddressState[8-1:0] L2CacheState___slave_ar_seen_reg;
    reg[8-1:0] L2CacheState___slave_aw_novelty_reg;
    reg[8-1:0] L2CacheState___slave_ar_novelty_reg;

    // members
    genvar __i;
    wire[$clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))-1:0] L2CacheState___data_ram__addr_in[32];
    wire L2CacheState___data_ram__wr_in[32];
    wire L2CacheState___data_ram__rd_in[32];
    wire['h20-1:0] L2CacheState___data_ram__data_in[32];
    wire['h20-1:0] L2CacheState___data_ram__data_out[32];
    generate
    for (__i=0; __i < 32; __i = __i + 1) begin
        L2CacheRamBank #(
        'h20
,       ((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)
        ) L2CacheState___data_ram (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .addr_in(L2CacheState___data_ram__addr_in[__i])
        ,           .wr_in(L2CacheState___data_ram__wr_in[__i])
        ,           .rd_in(L2CacheState___data_ram__rd_in[__i])
        ,           .data_in(L2CacheState___data_ram__data_in[__i])
        ,           .data_out(L2CacheState___data_ram__data_out[__i])
        );
    end
    endgenerate
    wire[$clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))-1:0] L2CacheState___tag_ram__addr_in[4];
    wire L2CacheState___tag_ram__wr_in[4];
    wire L2CacheState___tag_ram__rd_in[4];
    wire[(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___tag_ram__data_in[4];
    wire[(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___tag_ram__data_out[4];
    generate
    for (__i=0; __i < 4; __i = __i + 1) begin
        L2CacheRamBank #(
        (((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8
,       ((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)
        ) L2CacheState___tag_ram (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .addr_in(L2CacheState___tag_ram__addr_in[__i])
        ,           .wr_in(L2CacheState___tag_ram__wr_in[__i])
        ,           .rd_in(L2CacheState___tag_ram__rd_in[__i])
        ,           .data_in(L2CacheState___tag_ram__data_in[__i])
        ,           .data_out(L2CacheState___tag_ram__data_out[__i])
        );
    end
    endgenerate

    // tmp variables
    logic[DATA_BANKS-1:0][32-1:0] L2CacheState___lookup_data_reg_tmp;
    logic[WAYS-1:0][(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___lookup_tag_reg_tmp;
    L2HitLookupComb L2CacheState___lookup_hit_reg_tmp;
    L2EvictCandidateComb L2CacheState___lookup_evict_reg_tmp;
    logic[5-1:0] L2CacheState___state_reg_tmp;
    CacheRequest L2CacheState___req_reg_tmp;
    logic[3-1:0] L2CacheState___cpu_rr_reg_tmp;
    logic[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___victim_reg_tmp;
    logic[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___fill_way_reg_tmp;
    logic[$clog2((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)-1:0] L2CacheState___init_set_reg_tmp;
    logic[PORT_BITWIDTH-1:0] L2CacheState___cross_low_reg_tmp;
    logic[PORT_BITWIDTH-1:0] L2CacheState___cross_high_reg_tmp;
    logic[PORT_BITWIDTH-1:0] L2CacheState___refill_data_reg_tmp;
    logic[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___fill_beat_reg_tmp;
    logic[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___evict_beat_reg_tmp;
    logic[(ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)-1:0] L2CacheState___evict_tag_reg_tmp;
    logic[CACHE_LINE_SIZE*'h8-1:0] L2CacheState___evict_line_reg_tmp;
    logic[8-1:0] L2CacheState___slave_aw_novelty_reg_tmp;
    logic[8-1:0] L2CacheState___slave_ar_novelty_reg_tmp;


    always_comb begin : L2CacheRequest___slave_request_novelty_comb_func  // L2CacheRequest___slave_request_novelty_comb_func
        logic[31:0] index;
        L2CacheRequest___slave_request_novelty_comb = 0;
        for (index='h0;index < MEM_PORTS;index=index+1) begin
            L2CacheRequest___slave_request_novelty_comb.aw[index] = L2CacheState___slave_aw_novelty_reg[index];
            L2CacheRequest___slave_request_novelty_comb.ar[index] = L2CacheState___slave_ar_novelty_reg[index];
        end
    end

    always_comb begin : L2CacheRequest___active_request_comb_func  // L2CacheRequest___active_request_comb_func
        logic[31:0] port_index;
        logic[31:0] cpu_index;
        logic[63:0] byte_index;
        logic[63:0] word_index;
        logic[31:0] selected_slave;
        logic[31:0] selected_cpu;
        logic[31:0] candidate_cpu;
        logic[31:0] slave_addr;
        logic[31:0] lane;
        logic[31:0] _byte;
        logic[31:0] word;
        logic slave_write_pending;
        logic slave_read_pending;
        logic cpu_request_pending;
        L2CacheRequest___active_request_comb = 0;
        selected_slave='h0;
        selected_cpu='h0;
        candidate_cpu='h0;
        slave_addr='h0;
        lane='h0;
        _byte='h0;
        word='h0;
        slave_write_pending=0;
        slave_read_pending=0;
        cpu_request_pending=0;
        for (port_index='h0;port_index < MEM_PORTS;port_index=port_index+1) begin
            if (((((L2CacheState___slave_aw_reg[port_index].valid && axi_in__wvalid_in[port_index])) || (((axi_in__awvalid_in[port_index] && L2CacheRequest___slave_request_novelty_comb.aw[port_index]) && axi_in__wvalid_in[port_index])))) && ((!L2CacheState___response_reg[port_index].b.valid || axi_in__bready_in[port_index]))) begin
                slave_write_pending=1;
            end
            if ((axi_in__arvalid_in[port_index] && L2CacheRequest___slave_request_novelty_comb.ar[port_index]) && ((!L2CacheState___response_reg[port_index].r.valid || axi_in__rready_in[port_index]))) begin
                slave_read_pending=1;
            end
        end
        for (port_index='h0;port_index < MEM_PORTS;port_index=port_index+1) begin
            if (((!slave_write_pending && axi_in__arvalid_in[port_index]) && L2CacheRequest___slave_request_novelty_comb.ar[port_index]) && ((!L2CacheState___response_reg[port_index].r.valid || axi_in__rready_in[port_index]))) begin
                selected_slave=port_index;
            end
            if (((((L2CacheState___slave_aw_reg[port_index].valid && axi_in__wvalid_in[port_index])) || (((axi_in__awvalid_in[port_index] && L2CacheRequest___slave_request_novelty_comb.aw[port_index]) && axi_in__wvalid_in[port_index])))) && ((!L2CacheState___response_reg[port_index].b.valid || axi_in__bready_in[port_index]))) begin
                selected_slave=port_index;
            end
        end
        for (cpu_index='h0;cpu_index < CPU_PORTS;cpu_index=cpu_index+1) begin
            candidate_cpu=((unsigned'(32'(L2CacheState___cpu_rr_reg)) + cpu_index)) % CPU_PORTS;
            if (!cpu_request_pending && ((((d_mem_in__write_in[candidate_cpu] || d_mem_in__read_in[candidate_cpu]) || i_mem_in__write_in[candidate_cpu]) || i_mem_in__read_in[candidate_cpu]))) begin
                selected_cpu=candidate_cpu;
                cpu_request_pending=1;
            end
        end
        L2CacheRequest___active_request_comb.request.from_slave = unsigned'(1'(slave_write_pending || slave_read_pending));
        L2CacheRequest___active_request_comb.request.cpu_index = unsigned'(3'(unsigned'(3'(selected_cpu))));
        L2CacheRequest___active_request_comb.request.port = unsigned'(1'((!L2CacheRequest___active_request_comb.request.from_slave && cpu_request_pending) && ((d_mem_in__write_in[selected_cpu] || d_mem_in__read_in[selected_cpu]))));
        L2CacheRequest___active_request_comb.request.read = unsigned'(1'((((L2CacheRequest___active_request_comb.request.from_slave && !slave_write_pending)) || (((!L2CacheRequest___active_request_comb.request.from_slave && cpu_request_pending) && d_mem_in__read_in[selected_cpu]))) || (((((!L2CacheRequest___active_request_comb.request.from_slave && cpu_request_pending) && !d_mem_in__write_in[selected_cpu]) && !d_mem_in__read_in[selected_cpu]) && i_mem_in__read_in[selected_cpu]))));
        L2CacheRequest___active_request_comb.request.write = unsigned'(1'((((L2CacheRequest___active_request_comb.request.from_slave && slave_write_pending)) || (((!L2CacheRequest___active_request_comb.request.from_slave && cpu_request_pending) && d_mem_in__write_in[selected_cpu]))) || (((((!L2CacheRequest___active_request_comb.request.from_slave && cpu_request_pending) && !d_mem_in__read_in[selected_cpu]) && !d_mem_in__write_in[selected_cpu]) && i_mem_in__write_in[selected_cpu]))));
        L2CacheRequest___active_request_comb.request.addr = unsigned'(32'((L2CacheRequest___active_request_comb.request.port) ? (d_mem_in__addr_in[selected_cpu]) : (i_mem_in__addr_in[selected_cpu])));
        L2CacheRequest___active_request_comb.request.write_data = unsigned'(32'((L2CacheRequest___active_request_comb.request.port) ? (d_mem_in__write_data_in[selected_cpu]) : (i_mem_in__write_data_in[selected_cpu])));
        L2CacheRequest___active_request_comb.request.write_mask = unsigned'(8'((L2CacheRequest___active_request_comb.request.from_slave) ? (unsigned'(8'('hF))) : (((L2CacheRequest___active_request_comb.request.port) ? (d_mem_in__write_mask_in[selected_cpu]) : (i_mem_in__write_mask_in[selected_cpu])))));
        L2CacheRequest___active_request_comb.request.cache_disable = unsigned'(1'(!L2CacheRequest___active_request_comb.request.from_slave && ((L2CacheRequest___active_request_comb.request.port) ? (d_mem_in__cache_disable_in[selected_cpu]) : (i_mem_in__cache_disable_in[selected_cpu]))));
        L2CacheRequest___active_request_comb.request.slave_index = unsigned'(8'(selected_slave));
        for (port_index='h0;port_index < MEM_PORTS;port_index=port_index+1) begin
            if (L2CacheRequest___active_request_comb.request.from_slave && (selected_slave == port_index)) begin
                slave_addr=(slave_write_pending) ? (((L2CacheState___slave_aw_reg[port_index].valid) ? (unsigned'(32'(L2CacheState___slave_aw_reg[port_index].addr))) : (unsigned'(32'(axi_in__awaddr_in[port_index]))))) : (unsigned'(32'(axi_in__araddr_in[port_index])));
                L2CacheRequest___active_request_comb.request.addr = unsigned'(32'((slave_addr < memory_base_in) ? (slave_addr + memory_base_in) : (slave_addr)));
                L2CacheRequest___active_request_comb.request.slave_id = (slave_write_pending) ? (((L2CacheState___slave_aw_reg[port_index].valid) ? (L2CacheState___slave_aw_reg[port_index].id) : (axi_in__awid_in[port_index]))) : (axi_in__arid_in[port_index]);
                if (slave_write_pending) begin
                    lane=((((L2CacheState___slave_aw_reg[port_index].valid) ? (unsigned'(32'(L2CacheState___slave_aw_reg[port_index].addr))) : (unsigned'(32'(axi_in__awaddr_in[port_index])))) % PORT_BYTES))/'h4;
                    L2CacheRequest___active_request_comb.request.write_data = unsigned'(32'(unsigned'(32'((axi_in__wdata_in[port_index] >> (lane*'h20))))));
                    L2CacheRequest___active_request_comb.request.write_beat = axi_in__wdata_in[port_index];
                    L2CacheRequest___active_request_comb.request.write_strobe = axi_in__wstrb_in[port_index];
                end
            end
        end
        if (!L2CacheRequest___active_request_comb.request.from_slave) begin
            _byte=unsigned'(32'(L2CacheRequest___active_request_comb.request.addr)) % 'h4;
            word=((unsigned'(32'(L2CacheRequest___active_request_comb.request.addr)) % PORT_BYTES))/'h4;
            for (byte_index='h0;byte_index < 'h4;byte_index=byte_index+1) begin
                if ((((L2CacheRequest___active_request_comb.request.write_mask & (('h1 <<< byte_index)))) != 'h0) && ((((word*'h4) + _byte) + byte_index) < PORT_BYTES)) begin
                    L2CacheRequest___active_request_comb.request.write_strobe[((word*'h4) + _byte) + byte_index] = 'h1;
                end
            end
        end
        for (word_index='h0;word_index < PORT_WORDS;word_index=word_index+1) begin
            for (byte_index='h0;byte_index < 'h4;byte_index=byte_index+1) begin
                if (L2CacheRequest___active_request_comb.request.write_strobe[(word_index*'h4) + byte_index]) begin
                    L2CacheRequest___active_request_comb.request.write_word_mask[word_index] = 'h1;
                end
            end
        end
        L2CacheRequest___active_request_comb.set = unsigned'(32'(((unsigned'(32'(L2CacheRequest___active_request_comb.request.addr)) >>> LINE_BITS)) & ((SETS - 'h1))));
        _byte=unsigned'(32'(L2CacheRequest___active_request_comb.request.addr)) & 'h3;
        word=((unsigned'(32'(L2CacheRequest___active_request_comb.request.addr)) >>> 'h2)) & ((LINE_WORDS - 'h1));
        L2CacheRequest___active_request_comb.valid = unsigned'(1'(L2CacheRequest___active_request_comb.request.read || L2CacheRequest___active_request_comb.request.write));
        L2CacheRequest___active_request_comb.cross_line_read = unsigned'(1'((((L2CacheRequest___active_request_comb.request.read && !L2CacheRequest___active_request_comb.request.from_slave) && !L2CacheRequest___active_request_comb.request.port) && (_byte != 'h0)) && (word == (LINE_WORDS - 'h1))));
    end

    always_comb begin : L2CacheRequest___request_geometry_comb_func  // L2CacheRequest___request_geometry_comb_func
        logic[31:0] _byte;
        logic[31:0] word;
        logic[31:0] _local;
        logic[31:0] size;
        logic[31:0] i;
        L2CacheRequest___request_geometry_comb = 0;
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        word=((unsigned'(32'(L2CacheState___req_reg.addr)) >>> 'h2)) & ((LINE_WORDS - 'h1));
        _local=unsigned'(32'(L2CacheState___req_reg.addr)) - memory_base_in;
        size=memory_size_in;
        L2CacheRequest___request_geometry_comb.set = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) >>> LINE_BITS)) & ((SETS - 'h1))));
        L2CacheRequest___request_geometry_comb.word = unsigned'(32'(word));
        L2CacheRequest___request_geometry_comb.beat = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ((CACHE_LINE_SIZE - 'h1))))/PORT_BYTES));
        L2CacheRequest___request_geometry_comb.tag = unsigned'(32'(unsigned'(32'(L2CacheState___req_reg.addr)) >>> ((LINE_BITS + SET_BITS))));
        L2CacheRequest___request_geometry_comb.cross_beat_read = unsigned'(1'(((L2CacheState___req_reg.read && !L2CacheState___req_reg.from_slave) && (_byte != 'h0)) && (((((unsigned'(32'(L2CacheState___req_reg.addr)) % PORT_BYTES))/'h4)) + 'h1)>=PORT_WORDS));
        L2CacheRequest___request_geometry_comb.cross_write_data = unsigned'(32'((_byte == 'h0) ? (unsigned'(32'('h0))) : (unsigned'(32'(L2CacheState___req_reg.write_data)) >>> (('h20 - (_byte*'h8))))));
        for (i='h0;i < 'h4;i=i+1) begin
            if (((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) && (i + _byte)>='h4) begin
                L2CacheRequest___request_geometry_comb.cross_write_mask |= 'h1 <<< (((i + _byte) - 'h4));
                if ((L2CacheState___req_reg.write && (_byte != 'h0)) && (word == (LINE_WORDS - 'h1))) begin
                    L2CacheRequest___request_geometry_comb.cross_line_write = unsigned'(1'(1));
                end
            end
        end
        L2CacheRequest___request_geometry_comb.addr_in_memory = unsigned'(1'((L2CacheState___req_reg.addr>=memory_base_in && (size != 'h0)) && (_local < size)));
    end

    always_comb begin : l2_bank_addr_comb_func  // l2_bank_addr_comb_func
        logic[31:0] address;
        logic[31:0] dma_set;
        logic dma_line_fire;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        dma_set=((unsigned'(32'(dma_line_addr_in)) >>> LINE_BITS)) & ((SETS - 'h1));
        address=(dma_line_fire) ? (dma_set) : ((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE)) ? (unsigned'(32'(L2CacheRequest___active_request_comb.set))) : (unsigned'(32'(L2CacheRequest___request_geometry_comb.set)))));
        l2_bank_addr_comb = unsigned'(LOCAL_SET_BITS'(unsigned'(LOCAL_SET_BITS'(address))));
    end

    always_comb begin : tag_bank_addr_comb_func  // tag_bank_addr_comb_func
        tag_bank_addr_comb = ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_INIT)) ? (unsigned'(LOCAL_SET_BITS'(unsigned'(LOCAL_SET_BITS'(L2CacheState___init_set_reg))))) : (unsigned'(LOCAL_SET_BITS'(l2_bank_addr_comb)));
    end

    always_comb begin : l2_bank_read_comb_func  // l2_bank_read_comb_func
        logic dma_line_fire;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        l2_bank_read_comb=(((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_READ) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_READ))) && !dma_line_fire;
    end

    always_comb begin : L2CacheTagData___hit_lookup_comb_func  // L2CacheTagData___hit_lookup_comb_func
        logic[31:0] i;
        logic[31:0] way;
        logic[63:0] word_index;
        logic[63:0] beat_word;
        logic[31:0] _byte;
        logic[31:0] word_data;
        L2CacheTagData___hit_lookup_comb = 0;
        way='h0;
        word_index='h0;
        beat_word='h0;
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        word_data='h0;
        for (i='h0;i < WAYS;i=i+1) begin
            if (L2CacheState___lookup_tag_reg[i][(TAG_BITS + 'h1)] && (L2CacheState___lookup_tag_reg[i]['h0 +:(TAG_BITS - 'h1) - 'h0 + 1] == L2CacheRequest___request_geometry_comb.tag)) begin
                L2CacheTagData___hit_lookup_comb.hit = unsigned'(1'(1));
                L2CacheTagData___hit_lookup_comb.way = unsigned'(32'(i));
            end
        end
        for (i='h0;i < DATA_BANKS;i=i+1) begin
            way=i/LINE_WORDS;
            word_index=i % LINE_WORDS;
            if (L2CacheTagData___hit_lookup_comb.hit && (unsigned'(32'(L2CacheTagData___hit_lookup_comb.way)) == way)) begin
                word_data=unsigned'(32'(L2CacheState___lookup_data_reg[i]));
                if (L2CacheRequest___request_geometry_comb.word == word_index) begin
                    L2CacheTagData___hit_lookup_comb.aligned_word = unsigned'(32'(word_data));
                    L2CacheTagData___hit_lookup_comb.read_word |= word_data >>> ((_byte*'h8));
                end
                if ((unsigned'(32'(L2CacheRequest___request_geometry_comb.word)) + 'h1) == word_index) begin
                    L2CacheTagData___hit_lookup_comb.aligned_next_word = unsigned'(32'(word_data));
                    if (_byte != 'h0) begin
                        L2CacheTagData___hit_lookup_comb.read_word |= word_data <<< (('h20 - (_byte*'h8)));
                    end
                end
                if (word_index>=(unsigned'(32'(L2CacheRequest___request_geometry_comb.beat))*PORT_WORDS) && (word_index < (((unsigned'(32'(L2CacheRequest___request_geometry_comb.beat)) + 'h1))*PORT_WORDS))) begin
                    beat_word=word_index - (unsigned'(32'(L2CacheRequest___request_geometry_comb.beat))*PORT_WORDS);
                    L2CacheTagData___hit_lookup_comb.beat[beat_word*'h20 +:32] = L2CacheState___lookup_data_reg[i];
                end
            end
        end
    end

    always_comb begin : data_bank_write_comb_func  // data_bank_write_comb_func
        logic[31:0] bank;
        logic[31:0] dma_tag;
        logic[31:0] dma_way;
        logic dma_line_fire;
        L2HitLookupComb hit_lookup;
        L2RequestGeometryComb request_geometry;
        data_bank_write_comb = 'h0;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        dma_tag=unsigned'(32'(dma_line_addr_in)) >>> ((LINE_BITS + SET_BITS));
        dma_way=(WAYS<='h1) ? ('h0) : (dma_tag % WAYS);
        hit_lookup = L2CacheTagData___hit_lookup_comb;
        request_geometry = L2CacheRequest___request_geometry_comb;
        for (bank='h0;bank < DATA_BANKS;bank=bank+1) begin
            data_bank_write_comb[bank] = ((((dma_line_fire && (dma_way == ((bank/LINE_WORDS))))) || (((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_R_WRITE) && (L2CacheState___fill_way_reg == ((bank/LINE_WORDS)))) && (bank % LINE_WORDS)>=(unsigned'(32'(L2CacheState___fill_beat_reg))*PORT_WORDS)) && (((bank % LINE_WORDS)) < (((unsigned'(32'(L2CacheState___fill_beat_reg)) + 'h1))*PORT_WORDS))))) || (((((((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP) && L2CacheState___req_reg.from_slave) && L2CacheState___req_reg.write) && hit_lookup.hit) && (hit_lookup.way == ((bank/LINE_WORDS)))) && (bank % LINE_WORDS)>=(unsigned'(32'(request_geometry.beat))*PORT_WORDS)) && (((bank % LINE_WORDS)) < (((unsigned'(32'(request_geometry.beat)) + 'h1))*PORT_WORDS))) && L2CacheState___req_reg.write_word_mask[(((bank % LINE_WORDS)) % PORT_WORDS)]))) || (((((((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_LOOKUP))) && L2CacheState___req_reg.write) && hit_lookup.hit) && !L2CacheState___req_reg.from_slave) && (hit_lookup.way == ((bank/LINE_WORDS)))) && (((request_geometry.word == ((bank % LINE_WORDS))) || (((((unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3)) != 'h0) && ((unsigned'(32'(request_geometry.word)) + 'h1) == ((bank % LINE_WORDS)))))))));
        end
    end

    always_comb begin : L2CacheTagData___hit_write_pair_comb_func  // L2CacheTagData___hit_write_pair_comb_func
        logic[31:0] i;
        logic[31:0] _byte;
        logic[31:0] word_mask;
        logic[31:0] next_word_mask;
        logic[31:0] word_data;
        logic[31:0] next_word_data;
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        word_mask='h0;
        next_word_mask='h0;
        word_data=unsigned'(32'(L2CacheState___req_reg.write_data)) <<< ((_byte*'h8));
        next_word_data=(_byte == 'h0) ? ('h0) : (unsigned'(32'(L2CacheState___req_reg.write_data)) >>> (('h20 - (_byte*'h8))));
        for (i='h0;i < 'h4;i=i+1) begin
            if (((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) && ((i + _byte) < 'h4)) begin
                word_mask|='hFF <<< ((((i + _byte))*'h8));
            end
            if (((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) && (i + _byte)>='h4) begin
                next_word_mask|='hFF <<< (((((i + _byte) - 'h4))*'h8));
            end
        end
        L2CacheTagData___hit_write_pair_comb.word = unsigned'(32'(((unsigned'(32'(L2CacheTagData___hit_lookup_comb.aligned_word)) & ~word_mask)) | ((word_data & word_mask))));
        L2CacheTagData___hit_write_pair_comb.next_word = unsigned'(32'(((unsigned'(32'(L2CacheTagData___hit_lookup_comb.aligned_next_word)) & ~next_word_mask)) | ((next_word_data & next_word_mask))));
    end

    always_comb begin : L2CacheTagData___fill_write_pair_comb_func  // L2CacheTagData___fill_write_pair_comb_func
        logic[31:0] i;
        logic[31:0] _byte;
        logic[31:0] word;
        logic[31:0] next_word;
        logic[31:0] old_word;
        logic[31:0] old_next_word;
        logic[31:0] word_mask;
        logic[31:0] next_word_mask;
        logic[31:0] word_data;
        logic[31:0] next_word_data;
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        word=unsigned'(32'(L2CacheRequest___request_geometry_comb.word)) % PORT_WORDS;
        next_word=((unsigned'(32'(L2CacheRequest___request_geometry_comb.word)) + 'h1)) % PORT_WORDS;
        old_word=unsigned'(32'((L2CacheState___refill_data_reg >> (word*'h20))));
        old_next_word='h0;
        if ((unsigned'(32'(L2CacheRequest___request_geometry_comb.word)) + 'h1) < LINE_WORDS) begin
            old_next_word=unsigned'(32'((L2CacheState___refill_data_reg >> (next_word*'h20))));
        end
        word_mask='h0;
        next_word_mask='h0;
        word_data=unsigned'(32'(L2CacheState___req_reg.write_data)) <<< ((_byte*'h8));
        next_word_data=(_byte == 'h0) ? ('h0) : (unsigned'(32'(L2CacheState___req_reg.write_data)) >>> (('h20 - (_byte*'h8))));
        if (L2CacheState___req_reg.write) begin
            for (i='h0;i < 'h4;i=i+1) begin
                if (((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) && ((i + _byte) < 'h4)) begin
                    word_mask|='hFF <<< ((((i + _byte))*'h8));
                end
                if (((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) && (i + _byte)>='h4) begin
                    next_word_mask|='hFF <<< (((((i + _byte) - 'h4))*'h8));
                end
            end
        end
        L2CacheTagData___fill_write_pair_comb.word = unsigned'(32'(((old_word & ~word_mask)) | ((word_data & word_mask))));
        L2CacheTagData___fill_write_pair_comb.next_word = unsigned'(32'(((old_next_word & ~next_word_mask)) | ((next_word_data & next_word_mask))));
    end

    always_comb begin : data_bank_data_comb_func  // data_bank_data_comb_func
        logic[31:0] bank;
        logic[31:0] dma_byte;
        logic[31:0] dma_word;
        logic dma_line_fire;
        L2RequestGeometryComb request_geometry;
        L2WordPairComb hit_write_pair;
        L2WordPairComb fill_write_pair;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        request_geometry = L2CacheRequest___request_geometry_comb;
        hit_write_pair = L2CacheTagData___hit_write_pair_comb;
        fill_write_pair = L2CacheTagData___fill_write_pair_comb;
        for (bank='h0;bank < DATA_BANKS;bank=bank+1) begin
            if (dma_line_fire) begin
                dma_word=unsigned'(32'((dma_line_data_in >> (((bank % LINE_WORDS))*'h20))));
                for (dma_byte='h0;dma_byte < 'h4;dma_byte=dma_byte+1) begin
                    if (!dma_line_keep_in[(((bank % LINE_WORDS))*'h4) + dma_byte]) begin
                        dma_word&=~('hFF <<< ((dma_byte*'h8)));
                    end
                end
                data_bank_data_comb[bank]=dma_word;
            end
            else begin
                data_bank_data_comb[bank]=(((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_LOOKUP))) ? (((L2CacheState___req_reg.from_slave) ? (unsigned'(32'((L2CacheState___req_reg.write_beat >> (((bank % PORT_WORDS))*'h20))))) : (((((((unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3)) != 'h0) && ((unsigned'(32'(request_geometry.word)) + 'h1) == ((bank % LINE_WORDS))))) ? (unsigned'(32'(hit_write_pair.next_word))) : (unsigned'(32'(hit_write_pair.word))))))) : (((((((L2CacheState___req_reg.from_slave && L2CacheState___req_reg.write) && (request_geometry.beat == L2CacheState___fill_beat_reg)) && (bank % LINE_WORDS)>=(unsigned'(32'(L2CacheState___fill_beat_reg))*PORT_WORDS)) && (((bank % LINE_WORDS)) < (((unsigned'(32'(L2CacheState___fill_beat_reg)) + 'h1))*PORT_WORDS)))) ? (((L2CacheState___req_reg.write_word_mask[((bank % LINE_WORDS)) % PORT_WORDS]) ? (unsigned'(32'((L2CacheState___req_reg.write_beat >> (((bank % PORT_WORDS))*'h20))))) : (unsigned'(32'((L2CacheState___refill_data_reg >> (((((bank % LINE_WORDS)) % PORT_WORDS))*'h20))))))) : (((L2CacheState___req_reg.write && (request_geometry.word == ((bank % LINE_WORDS))))) ? (unsigned'(32'(fill_write_pair.word))) : ((((L2CacheState___req_reg.write && (((unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3)) != 'h0)) && ((unsigned'(32'(request_geometry.word)) + 'h1) == ((bank % LINE_WORDS))))) ? (unsigned'(32'(fill_write_pair.next_word))) : (unsigned'(32'((L2CacheState___refill_data_reg >> (((((bank % LINE_WORDS)) % PORT_WORDS))*'h20)))))))));
            end
        end
    end

    always_comb begin : tag_bank_write_comb_func  // tag_bank_write_comb_func
        logic[31:0] way;
        logic[31:0] dma_tag;
        logic[31:0] dma_way;
        logic dma_line_fire;
        L2HitLookupComb hit_lookup;
        tag_bank_write_comb = 'h0;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        dma_tag=unsigned'(32'(dma_line_addr_in)) >>> ((LINE_BITS + SET_BITS));
        dma_way=(WAYS<='h1) ? ('h0) : (dma_tag % WAYS);
        hit_lookup = L2CacheTagData___hit_lookup_comb;
        for (way='h0;way < WAYS;way=way+1) begin
            tag_bank_write_comb[way] = ((((dma_line_fire && (dma_way == way))) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_INIT)) || ((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_R_WRITE) && (L2CacheState___fill_beat_reg == (LINE_BEATS - 'h1))) && (L2CacheState___fill_way_reg == way)))) || (((((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_LOOKUP))) && L2CacheState___req_reg.write) && hit_lookup.hit) && (hit_lookup.way == way)));
        end
    end

    always_comb begin : L2CacheTagData___tag_write_data_comb_func  // L2CacheTagData___tag_write_data_comb_func
        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_INIT) begin
            L2CacheTagData___tag_write_data_comb = 'h0;
        end
        else begin
            L2CacheTagData___tag_write_data_comb = (((unsigned'(64'('h1)) <<< ((TAG_BITS + 'h1)))) | ((unsigned'(64'(L2CacheState___req_reg.write)) <<< TAG_BITS))) | unsigned'(64'(L2CacheRequest___request_geometry_comb.tag));
        end
    end

    always_comb begin : tag_bank_data_comb_func  // tag_bank_data_comb_func
        logic[31:0] dma_tag;
        logic dma_line_fire;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        dma_tag=unsigned'(32'(dma_line_addr_in)) >>> ((LINE_BITS + SET_BITS));
        tag_bank_data_comb = L2CacheTagData___tag_write_data_comb;
        if (dma_line_fire) begin
            tag_bank_data_comb = (((unsigned'(64'('h1)) <<< ((TAG_BITS + 'h1)))) | ((unsigned'(64'('h1)) <<< TAG_BITS))) | dma_tag;
        end
    end

    always_comb begin : axi_in_comb_func  // axi_in_comb_func
        logic[31:0] index;
        L2ActiveRequestComb active_request;
        active_request = L2CacheRequest___active_request_comb;
        for (index='h0;index < MEM_PORTS;index=index+1) begin
            axi_in_comb[index].aw.ready=((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) && !L2CacheState___slave_aw_reg[index].valid) && L2CacheRequest___slave_request_novelty_comb.aw[index]) && ((!L2CacheState___response_reg[index].b.valid || axi_in__bready_in[index]))) && axi_in__awvalid_in[index];
            axi_in_comb[index].w.ready=(((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) && active_request.request.from_slave) && active_request.request.write) && (active_request.request.slave_index == index);
            axi_in_comb[index].b = L2CacheState___response_reg[index].b;
            axi_in_comb[index].ar.ready=((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) && L2CacheRequest___slave_request_novelty_comb.ar[index]) && active_request.request.from_slave) && active_request.request.read) && (active_request.request.slave_index == index);
            axi_in_comb[index].r = L2CacheState___response_reg[index].r;
        end
    end

    always_comb begin : L2CacheMemory___axi_route_comb_func  // L2CacheMemory___axi_route_comb_func
        logic[31:0] i;
        logic[63:0] base;
        logic[31:0] ar_total_local;
        logic[31:0] ar_region_base;
        logic[31:0] aw_total_local;
        logic[31:0] aw_region_base;
        L2CacheMemory___axi_route_comb.ar_full_addr = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) + ((unsigned'(32'(L2CacheState___fill_beat_reg))*PORT_BYTES))));
        if ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AR) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_R)) begin
            L2CacheMemory___axi_route_comb.ar_full_addr = L2CacheState___req_reg.addr;
        end
        if ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR0) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R0)) begin
            L2CacheMemory___axi_route_comb.ar_full_addr = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) + ((unsigned'(32'(L2CacheRequest___request_geometry_comb.beat))*PORT_BYTES))));
        end
        if ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR1) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R1)) begin
            L2CacheMemory___axi_route_comb.ar_full_addr = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((PORT_BYTES - 'h1)))))) + PORT_BYTES));
        end
        ar_total_local=unsigned'(32'(L2CacheMemory___axi_route_comb.ar_full_addr)) - memory_base_in;
        base='h0;
        ar_region_base='h0;
        L2CacheMemory___axi_route_comb.ar_sel = unsigned'(8'(MEM_PORTS - 'h1));
        for (i='h0;i < MEM_PORTS;i=i+1) begin
            if (ar_total_local>=base && (unsigned'(64'(ar_total_local)) < (base + mem_region_size_in[i]))) begin
                L2CacheMemory___axi_route_comb.ar_sel = unsigned'(8'(i));
                ar_region_base=unsigned'(32'(base));
            end
            base+=mem_region_size_in[i];
        end
        L2CacheMemory___axi_route_comb.ar_local_addr = unsigned'(32'(unsigned'(32'(((unsigned'(64'(((ar_total_local - ar_region_base))))) & MEM_ADDR_MASK64)))));
        L2CacheMemory___axi_route_comb.aw_full_addr = unsigned'(32'(((((unsigned'(32'(L2CacheState___evict_tag_reg)) <<< ((SET_BITS + LINE_BITS)))) | ((unsigned'(32'(L2CacheRequest___request_geometry_comb.set)) <<< LINE_BITS)))) + ((unsigned'(32'(L2CacheState___evict_beat_reg))*PORT_BYTES))));
        if (((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AW) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_W)) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_B)) begin
            L2CacheMemory___axi_route_comb.aw_full_addr = L2CacheState___req_reg.addr;
        end
        aw_total_local=unsigned'(32'(L2CacheMemory___axi_route_comb.aw_full_addr)) - memory_base_in;
        base='h0;
        aw_region_base='h0;
        L2CacheMemory___axi_route_comb.aw_sel = unsigned'(8'(MEM_PORTS - 'h1));
        for (i='h0;i < MEM_PORTS;i=i+1) begin
            if (aw_total_local>=base && (unsigned'(64'(aw_total_local)) < (base + mem_region_size_in[i]))) begin
                L2CacheMemory___axi_route_comb.aw_sel = unsigned'(8'(i));
                aw_region_base=unsigned'(32'(base));
            end
            base+=mem_region_size_in[i];
        end
        L2CacheMemory___axi_route_comb.aw_local_addr = unsigned'(32'(unsigned'(32'(((unsigned'(64'(((aw_total_local - aw_region_base))))) & MEM_ADDR_MASK64)))));
    end

    always_comb begin : L2CacheMemory___io_write_payload_comb_func  // L2CacheMemory___io_write_payload_comb_func
        logic[31:0] _byte;
        logic[31:0] word;
        logic[31:0] i;
        L2CacheMemory___io_write_payload_comb = 0;
        if (L2CacheState___req_reg.from_slave) begin
            L2CacheMemory___io_write_payload_comb.data = L2CacheState___req_reg.write_beat;
            L2CacheMemory___io_write_payload_comb.strobe = L2CacheState___req_reg.write_strobe;
            disable L2CacheMemory___io_write_payload_comb_func;
        end
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        word=((unsigned'(32'(L2CacheState___req_reg.addr)) % PORT_BYTES))/'h4;
        L2CacheMemory___io_write_payload_comb.data[word*'h20 +:32] = unsigned'(32'(L2CacheState___req_reg.write_data)) <<< ((_byte*'h8));
        for (i='h0;i < 'h4;i=i+1) begin
            if ((((L2CacheState___req_reg.write_mask & (('h1 <<< i)))) != 'h0) && ((((word*'h4) + _byte) + i) < PORT_BYTES)) begin
                L2CacheMemory___io_write_payload_comb.strobe[((word*'h4) + _byte) + i] = 'h1;
            end
        end
    end

    always_comb begin : L2CacheMemory___evict_line_comb_func  // L2CacheMemory___evict_line_comb_func
        logic[31:0] word;
        logic[63:0] beat_word;
        word='h0;
        beat_word='h0;
        L2CacheMemory___evict_line_comb = 'h0;
        for (beat_word='h0;beat_word < PORT_WORDS;beat_word=beat_word+1) begin
            word=(unsigned'(32'(L2CacheState___evict_beat_reg))*PORT_WORDS) + beat_word;
            if (word < LINE_WORDS) begin
                L2CacheMemory___evict_line_comb[beat_word*'h20 +:32] = L2CacheState___evict_line_reg[word*'h20 +:32];
            end
        end
    end

    always_comb begin : L2CacheMemory___axi_out_driver_comb_func  // L2CacheMemory___axi_out_driver_comb_func
        L2CacheMemory___axi_out_driver_comb.aw.valid=L2CacheRequest___request_geometry_comb.addr_in_memory && (((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_EVICT_AW) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AW)));
        L2CacheMemory___axi_out_driver_comb.aw.addr = unsigned'(32'(unsigned'(32'(unsigned'(32'(L2CacheMemory___axi_route_comb.aw_local_addr))))));
        L2CacheMemory___axi_out_driver_comb.aw.id = unsigned'(4'(unsigned'(4'h0)));
        L2CacheMemory___axi_out_driver_comb.w.valid=L2CacheRequest___request_geometry_comb.addr_in_memory && (((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_EVICT_W) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_W)));
        L2CacheMemory___axi_out_driver_comb.w.data = (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_W) ? (L2CacheMemory___io_write_payload_comb.data) : (L2CacheMemory___evict_line_comb);
        L2CacheMemory___axi_out_driver_comb.w.strb = (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_W) ? (L2CacheMemory___io_write_payload_comb.strobe) : (~('h0));
        L2CacheMemory___axi_out_driver_comb.w.last=L2CacheMemory___axi_out_driver_comb.w.valid;
        L2CacheMemory___axi_out_driver_comb.b.ready=L2CacheMemory___axi_route_comb.aw_sel < MEM_PORTS;
        L2CacheMemory___axi_out_driver_comb.ar.valid=L2CacheRequest___request_geometry_comb.addr_in_memory && (((((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_AR) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR0)) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR1)) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AR)));
        L2CacheMemory___axi_out_driver_comb.ar.addr = unsigned'(32'(unsigned'(32'(unsigned'(32'(L2CacheMemory___axi_route_comb.ar_local_addr))))));
        L2CacheMemory___axi_out_driver_comb.ar.id = unsigned'(4'(unsigned'(4'h0)));
        L2CacheMemory___axi_out_driver_comb.r.ready=(((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_R) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R0)) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R1)) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_R);
    end

    always_comb begin : axi_out_comb_func  // axi_out_comb_func
        logic[31:0] index;
        for (index='h0;index < MEM_PORTS;index=index+1) begin
            axi_out_comb[index].aw.valid=L2CacheMemory___axi_out_driver_comb.aw.valid && (unsigned'(32'(L2CacheMemory___axi_route_comb.aw_sel)) == index);
            axi_out_comb[index].aw.addr = L2CacheMemory___axi_out_driver_comb.aw.addr;
            axi_out_comb[index].aw.id = L2CacheMemory___axi_out_driver_comb.aw.id;
            axi_out_comb[index].w.valid=L2CacheMemory___axi_out_driver_comb.w.valid && (unsigned'(32'(L2CacheMemory___axi_route_comb.aw_sel)) == index);
            axi_out_comb[index].w.data = L2CacheMemory___axi_out_driver_comb.w.data;
            axi_out_comb[index].w.strb = L2CacheMemory___axi_out_driver_comb.w.strb;
            axi_out_comb[index].w.last=L2CacheMemory___axi_out_driver_comb.w.last && (unsigned'(32'(L2CacheMemory___axi_route_comb.aw_sel)) == index);
            axi_out_comb[index].b.ready=L2CacheMemory___axi_out_driver_comb.b.ready && (unsigned'(32'(L2CacheMemory___axi_route_comb.aw_sel)) == index);
            axi_out_comb[index].ar.valid=L2CacheMemory___axi_out_driver_comb.ar.valid && (unsigned'(32'(L2CacheMemory___axi_route_comb.ar_sel)) == index);
            axi_out_comb[index].ar.addr = L2CacheMemory___axi_out_driver_comb.ar.addr;
            axi_out_comb[index].ar.id = L2CacheMemory___axi_out_driver_comb.ar.id;
            axi_out_comb[index].r.ready=L2CacheMemory___axi_out_driver_comb.r.ready && (unsigned'(32'(L2CacheMemory___axi_route_comb.ar_sel)) == index);
        end
    end

    task send_slave_read_response (
        input logic[3-1:0] index
,       input logic[4-1:0] id
,       input logic[256-1:0] data
    );
    begin: send_slave_read_response
        L2CacheState___response_reg[index].r.valid<=1;
        L2CacheState___response_reg[index].r.id <= id;
        L2CacheState___response_reg[index].r.data <= data;
        L2CacheState___response_reg[index].r.last<=1;
    end
    endtask

    task send_slave_write_response (
        input logic[3-1:0] index
,       input logic[4-1:0] id
    );
    begin: send_slave_write_response
        L2CacheState___response_reg[index].b.valid<=1;
        L2CacheState___response_reg[index].b.id <= id;
    end
    endtask

    task send_cpu_response (input logic[256-1:0] data);
    begin: send_cpu_response
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].valid <= unsigned'(1'(1));
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].read <= L2CacheState___req_reg.read;
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].write <= L2CacheState___req_reg.write;
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].data_port <= L2CacheState___req_reg.port;
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].addr <= L2CacheState___req_reg.addr;
        L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].r.data <= data;
    end
    endtask

    always_comb begin : L2CacheTagData___read_data_comb_func  // L2CacheTagData___read_data_comb_func
        logic[31:0] index;
        for (index='h0;index < CPU_PORTS;index=index+1) begin
            L2CacheTagData___read_data_comb[index] = (L2CacheState___response_reg[CPU_RESPONSE_BASE + index].valid) ? (L2CacheState___response_reg[CPU_RESPONSE_BASE + index].r.data) : ('h0);
        end
    end

    always_comb begin : L2CacheWait___cpu_wait_comb_func  // L2CacheWait___cpu_wait_comb_func
        logic[31:0] index;
        logic done_i_read;
        logic done_d_read;
        logic done_d_write;
        for (index='h0;index < CPU_PORTS;index=index+1) begin
            done_i_read=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && !L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].read) && i_mem_in__read_in[index]) && (unsigned'(32'(i_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            done_d_read=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].read) && d_mem_in__read_in[index]) && (unsigned'(32'(d_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            done_d_write=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].write) && d_mem_in__write_in[index]) && (unsigned'(32'(d_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            L2CacheWait___cpu_wait_comb[index] = 0;
            if (i_mem_in__read_in[index]) begin
                L2CacheWait___cpu_wait_comb[index].instruction = unsigned'(1'(!done_i_read));
            end
            if (d_mem_in__write_in[index]) begin
                L2CacheWait___cpu_wait_comb[index].data = unsigned'(1'(!done_d_write));
            end
            if (d_mem_in__read_in[index]) begin
                L2CacheWait___cpu_wait_comb[index].data = unsigned'(1'(!done_d_read));
            end
            if ((L2CacheState___state_reg != L2CacheFsmState_pkg::ST_IDLE) && !done_i_read) begin
                L2CacheWait___cpu_wait_comb[index].instruction = unsigned'(1'(1));
            end
            if ((L2CacheState___state_reg != L2CacheFsmState_pkg::ST_IDLE) && !((done_d_read || done_d_write))) begin
                L2CacheWait___cpu_wait_comb[index].data = unsigned'(1'(1));
            end
        end
    end

    always_comb begin : L2CacheMemory___req_uncached_region_comb_func  // L2CacheMemory___req_uncached_region_comb_func
        logic[31:0] _local;
        logic[63:0] base;
        logic[31:0] i;
        _local=unsigned'(32'(L2CacheState___req_reg.addr)) - memory_base_in;
        base='h0;
        L2CacheMemory___req_uncached_region_comb=0;
        for (i='h0;i < MEM_PORTS;i=i+1) begin
            if (_local>=base && (unsigned'(64'(_local)) < (base + mem_region_size_in[i]))) begin
                L2CacheMemory___req_uncached_region_comb=mem_region_uncached_in[i];
            end
            base+=mem_region_size_in[i];
        end
        L2CacheMemory___req_uncached_region_comb=L2CacheRequest___request_geometry_comb.addr_in_memory && ((L2CacheState___req_reg.cache_disable || L2CacheMemory___req_uncached_region_comb));
    end

    generate  // _assign
        genvar gi;
        for (gi='h0;gi < CPU_PORTS;gi=gi+1) begin
            assign i_mem_in__read_data_out[gi] = L2CacheTagData___read_data_comb[gi];
            assign i_mem_in__wait_out[gi] = L2CacheWait___cpu_wait_comb[gi].instruction;
            assign d_mem_in__read_data_out[gi] = L2CacheTagData___read_data_comb[gi];
            assign d_mem_in__wait_out[gi] = L2CacheWait___cpu_wait_comb[gi].data;
        end
        for (gi='h0;gi < MEM_PORTS;gi=gi+1) begin
            assign axi_in__awready_out[gi] = axi_in_comb[gi].aw.ready;
            assign axi_in__wready_out[gi] = axi_in_comb[gi].w.ready;
            assign axi_in__bvalid_out[gi] = axi_in_comb[gi].b.valid;
            assign axi_in__bid_out[gi] = unsigned'(4'(unsigned'(4'(unsigned'(64'(axi_in_comb[gi].b.id))))));
            assign axi_in__arready_out[gi] = axi_in_comb[gi].ar.ready;
            assign axi_in__rvalid_out[gi] = axi_in_comb[gi].r.valid;
            assign axi_in__rdata_out[gi] = axi_in_comb[gi].r.data;
            assign axi_in__rlast_out[gi] = axi_in_comb[gi].r.last;
            assign axi_in__rid_out[gi] = unsigned'(4'(unsigned'(4'(unsigned'(64'(axi_in_comb[gi].r.id))))));
            assign axi_out__awvalid_out[gi] = axi_out_comb[gi].aw.valid;
            assign axi_out__awaddr_out[gi] = unsigned'(31'(unsigned'(31'(unsigned'(64'(axi_out_comb[gi].aw.addr))))));
            assign axi_out__awid_out[gi] = unsigned'(4'(unsigned'(4'(unsigned'(64'(axi_out_comb[gi].aw.id))))));
            assign axi_out__wvalid_out[gi] = axi_out_comb[gi].w.valid;
            assign axi_out__wdata_out[gi] = axi_out_comb[gi].w.data;
            assign axi_out__wstrb_out[gi] = axi_out_comb[gi].w.strb;
            assign axi_out__wlast_out[gi] = axi_out_comb[gi].w.last;
            assign axi_out__bready_out[gi] = axi_out_comb[gi].b.ready;
            assign axi_out__arvalid_out[gi] = axi_out_comb[gi].ar.valid;
            assign axi_out__araddr_out[gi] = unsigned'(31'(unsigned'(31'(unsigned'(64'(axi_out_comb[gi].ar.addr))))));
            assign axi_out__arid_out[gi] = unsigned'(4'(unsigned'(4'(unsigned'(64'(axi_out_comb[gi].ar.id))))));
            assign axi_out__rready_out[gi] = axi_out_comb[gi].r.ready;
        end
        assign L2CacheState___data_ram__addr_in['h0] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h0] = (('h0 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h0]) : (0);
        assign L2CacheState___data_ram__rd_in['h0] = (('h0 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h0] = (('h0 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h0]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1] = (('h1 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1]) : (0);
        assign L2CacheState___data_ram__rd_in['h1] = (('h1 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1] = (('h1 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h2] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h2] = (('h2 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h2]) : (0);
        assign L2CacheState___data_ram__rd_in['h2] = (('h2 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h2] = (('h2 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h2]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h3] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h3] = (('h3 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h3]) : (0);
        assign L2CacheState___data_ram__rd_in['h3] = (('h3 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h3] = (('h3 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h3]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h4] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h4] = (('h4 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h4]) : (0);
        assign L2CacheState___data_ram__rd_in['h4] = (('h4 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h4] = (('h4 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h4]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h5] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h5] = (('h5 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h5]) : (0);
        assign L2CacheState___data_ram__rd_in['h5] = (('h5 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h5] = (('h5 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h5]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h6] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h6] = (('h6 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h6]) : (0);
        assign L2CacheState___data_ram__rd_in['h6] = (('h6 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h6] = (('h6 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h6]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h7] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h7] = (('h7 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h7]) : (0);
        assign L2CacheState___data_ram__rd_in['h7] = (('h7 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h7] = (('h7 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h7]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h8] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h8] = (('h8 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h8]) : (0);
        assign L2CacheState___data_ram__rd_in['h8] = (('h8 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h8] = (('h8 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h8]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h9] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h9] = (('h9 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h9]) : (0);
        assign L2CacheState___data_ram__rd_in['h9] = (('h9 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h9] = (('h9 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h9]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hA] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hA] = (('hA < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hA]) : (0);
        assign L2CacheState___data_ram__rd_in['hA] = (('hA < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hA] = (('hA < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hA]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hB] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hB] = (('hB < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hB]) : (0);
        assign L2CacheState___data_ram__rd_in['hB] = (('hB < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hB] = (('hB < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hB]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hC] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hC] = (('hC < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hC]) : (0);
        assign L2CacheState___data_ram__rd_in['hC] = (('hC < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hC] = (('hC < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hC]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hD] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hD] = (('hD < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hD]) : (0);
        assign L2CacheState___data_ram__rd_in['hD] = (('hD < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hD] = (('hD < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hD]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hE] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hE] = (('hE < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hE]) : (0);
        assign L2CacheState___data_ram__rd_in['hE] = (('hE < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hE] = (('hE < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hE]) : ('h0);
        assign L2CacheState___data_ram__addr_in['hF] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['hF] = (('hF < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['hF]) : (0);
        assign L2CacheState___data_ram__rd_in['hF] = (('hF < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['hF] = (('hF < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['hF]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h10] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h10] = (('h10 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h10]) : (0);
        assign L2CacheState___data_ram__rd_in['h10] = (('h10 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h10] = (('h10 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h10]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h11] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h11] = (('h11 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h11]) : (0);
        assign L2CacheState___data_ram__rd_in['h11] = (('h11 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h11] = (('h11 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h11]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h12] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h12] = (('h12 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h12]) : (0);
        assign L2CacheState___data_ram__rd_in['h12] = (('h12 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h12] = (('h12 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h12]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h13] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h13] = (('h13 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h13]) : (0);
        assign L2CacheState___data_ram__rd_in['h13] = (('h13 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h13] = (('h13 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h13]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h14] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h14] = (('h14 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h14]) : (0);
        assign L2CacheState___data_ram__rd_in['h14] = (('h14 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h14] = (('h14 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h14]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h15] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h15] = (('h15 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h15]) : (0);
        assign L2CacheState___data_ram__rd_in['h15] = (('h15 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h15] = (('h15 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h15]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h16] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h16] = (('h16 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h16]) : (0);
        assign L2CacheState___data_ram__rd_in['h16] = (('h16 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h16] = (('h16 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h16]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h17] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h17] = (('h17 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h17]) : (0);
        assign L2CacheState___data_ram__rd_in['h17] = (('h17 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h17] = (('h17 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h17]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h18] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h18] = (('h18 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h18]) : (0);
        assign L2CacheState___data_ram__rd_in['h18] = (('h18 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h18] = (('h18 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h18]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h19] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h19] = (('h19 < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h19]) : (0);
        assign L2CacheState___data_ram__rd_in['h19] = (('h19 < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h19] = (('h19 < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h19]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1A] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1A] = (('h1A < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1A]) : (0);
        assign L2CacheState___data_ram__rd_in['h1A] = (('h1A < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1A] = (('h1A < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1A]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1B] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1B] = (('h1B < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1B]) : (0);
        assign L2CacheState___data_ram__rd_in['h1B] = (('h1B < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1B] = (('h1B < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1B]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1C] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1C] = (('h1C < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1C]) : (0);
        assign L2CacheState___data_ram__rd_in['h1C] = (('h1C < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1C] = (('h1C < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1C]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1D] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1D] = (('h1D < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1D]) : (0);
        assign L2CacheState___data_ram__rd_in['h1D] = (('h1D < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1D] = (('h1D < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1D]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1E] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1E] = (('h1E < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1E]) : (0);
        assign L2CacheState___data_ram__rd_in['h1E] = (('h1E < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1E] = (('h1E < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1E]) : ('h0);
        assign L2CacheState___data_ram__addr_in['h1F] = l2_bank_addr_comb;
        assign L2CacheState___data_ram__wr_in['h1F] = (('h1F < LOCAL_DATA_BANKS)) ? (data_bank_write_comb['h1F]) : (0);
        assign L2CacheState___data_ram__rd_in['h1F] = (('h1F < LOCAL_DATA_BANKS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___data_ram__data_in['h1F] = (('h1F < LOCAL_DATA_BANKS)) ? (data_bank_data_comb['h1F]) : ('h0);
        assign L2CacheState___tag_ram__addr_in['h0] = tag_bank_addr_comb;
        assign L2CacheState___tag_ram__wr_in['h0] = (('h0 < WAYS)) ? (tag_bank_write_comb['h0]) : (0);
        assign L2CacheState___tag_ram__rd_in['h0] = (('h0 < WAYS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___tag_ram__data_in['h0] = (('h0 < WAYS)) ? (tag_bank_data_comb) : ('h0);
        assign L2CacheState___tag_ram__addr_in['h1] = tag_bank_addr_comb;
        assign L2CacheState___tag_ram__wr_in['h1] = (('h1 < WAYS)) ? (tag_bank_write_comb['h1]) : (0);
        assign L2CacheState___tag_ram__rd_in['h1] = (('h1 < WAYS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___tag_ram__data_in['h1] = (('h1 < WAYS)) ? (tag_bank_data_comb) : ('h0);
        assign L2CacheState___tag_ram__addr_in['h2] = tag_bank_addr_comb;
        assign L2CacheState___tag_ram__wr_in['h2] = (('h2 < WAYS)) ? (tag_bank_write_comb['h2]) : (0);
        assign L2CacheState___tag_ram__rd_in['h2] = (('h2 < WAYS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___tag_ram__data_in['h2] = (('h2 < WAYS)) ? (tag_bank_data_comb) : ('h0);
        assign L2CacheState___tag_ram__addr_in['h3] = tag_bank_addr_comb;
        assign L2CacheState___tag_ram__wr_in['h3] = (('h3 < WAYS)) ? (tag_bank_write_comb['h3]) : (0);
        assign L2CacheState___tag_ram__rd_in['h3] = (('h3 < WAYS)) ? (l2_bank_read_comb) : (0);
        assign L2CacheState___tag_ram__data_in['h3] = (('h3 < WAYS)) ? (tag_bank_data_comb) : ('h0);
        assign dma_line_ready_out = (((((((((((((((unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IDLE) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_READ)) || (((unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_LOOKUP) && ((!L2CacheState___req_reg.write || L2CacheMemory___req_uncached_region_comb))))) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_LOOKUP_CAPTURE)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_LOOKUP_RESULT)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_CROSS_WRITE_CAPTURE)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_CROSS_WRITE_RESULT)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_AXI_AR)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_EVICT_AW)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_EVICT_W)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_EVICT_B)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IO_AW)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IO_W)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IO_B)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IO_AR)) || (unsigned'(32'(L2CacheState___state_reg)) == L2CacheFsmState_pkg::ST_IO_R);
    endgenerate

    always_comb begin : L2CacheMemory___evict_candidate_comb_func  // L2CacheMemory___evict_candidate_comb_func
        logic[31:0] i;
        logic[31:0] way;
        logic[31:0] word;
        L2CacheMemory___evict_candidate_comb = 0;
        way='h0;
        word='h0;
        L2CacheMemory___evict_candidate_comb.way = unsigned'(32'(((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP)) ? (unsigned'(32'(L2CacheState___victim_reg))) : (unsigned'(32'(L2CacheState___fill_way_reg)))));
        for (i='h0;i < WAYS;i=i+1) begin
            if (unsigned'(32'(L2CacheMemory___evict_candidate_comb.way)) == i) begin
                L2CacheMemory___evict_candidate_comb.valid = unsigned'(1'(L2CacheState___lookup_tag_reg[i][TAG_BITS + 'h1]));
                L2CacheMemory___evict_candidate_comb.dirty = unsigned'(1'(L2CacheState___lookup_tag_reg[i][TAG_BITS]));
                L2CacheMemory___evict_candidate_comb.tag = unsigned'(32'(unsigned'(64'(L2CacheState___lookup_tag_reg[i]['h0 +:TAG_BITS - 'h1 - 'h0 + 1]))));
            end
        end
        for (i='h0;i < DATA_BANKS;i=i+1) begin
            way=i/LINE_WORDS;
            word=i % LINE_WORDS;
            if (unsigned'(32'(L2CacheMemory___evict_candidate_comb.way)) == way) begin
                L2CacheMemory___evict_candidate_comb.line[word*'h20 +:32] = L2CacheState___lookup_data_reg[i];
            end
        end
    end

    always_comb begin : L2CacheMemory___axi_out_selected_resp_comb_func  // L2CacheMemory___axi_out_selected_resp_comb_func
        logic[31:0] i;
        L2CacheMemory___axi_out_selected_resp_comb.aw.ready=0;
        L2CacheMemory___axi_out_selected_resp_comb.w.ready=0;
        L2CacheMemory___axi_out_selected_resp_comb.b.valid=0;
        L2CacheMemory___axi_out_selected_resp_comb.b.id = 'h0;
        L2CacheMemory___axi_out_selected_resp_comb.ar.ready=0;
        L2CacheMemory___axi_out_selected_resp_comb.r.valid=0;
        L2CacheMemory___axi_out_selected_resp_comb.r.data = 'h0;
        L2CacheMemory___axi_out_selected_resp_comb.r.last=0;
        L2CacheMemory___axi_out_selected_resp_comb.r.id = 'h0;
        for (i='h0;i < MEM_PORTS;i=i+1) begin
            if (unsigned'(32'(L2CacheMemory___axi_route_comb.aw_sel)) == i) begin
                L2CacheMemory___axi_out_selected_resp_comb.aw.ready=axi_out__awready_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.w.ready=axi_out__wready_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.b.valid=axi_out__bvalid_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.b.id = axi_out__bid_in[i];
            end
            if (unsigned'(32'(L2CacheMemory___axi_route_comb.ar_sel)) == i) begin
                L2CacheMemory___axi_out_selected_resp_comb.ar.ready=axi_out__arready_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.r.valid=axi_out__rvalid_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.r.data = axi_out__rdata_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.r.last=axi_out__rlast_in[i];
                L2CacheMemory___axi_out_selected_resp_comb.r.id = axi_out__rid_in[i];
            end
        end
    end

    always_comb begin : L2CacheTagData___cross_read_data_comb_func  // L2CacheTagData___cross_read_data_comb_func
        logic[31:0] low_word;
        logic[31:0] _byte;
        logic[31:0] low;
        logic[31:0] high;
        logic[31:0] data;
        L2CacheTagData___cross_read_data_comb = L2CacheState___cross_low_reg;
        _byte=unsigned'(32'(L2CacheState___req_reg.addr)) & 'h3;
        low_word=(unsigned'(32'(L2CacheState___req_reg.addr)) % PORT_BYTES)/'h4;
        low=unsigned'(32'(L2CacheState___cross_low_reg[low_word*'h20 +:32]));
        high=unsigned'(32'(L2CacheState___cross_high_reg['h0 +:32]));
        data=((low >>> ((_byte*'h8)))) | ((high <<< (('h20 - (_byte*'h8)))));
        L2CacheTagData___cross_read_data_comb = 'h0;
        L2CacheTagData___cross_read_data_comb['h0 +:32] = data;
    end

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
        logic[31:0] i;
        logic[31:0] way;
        logic dma_line_fire;
        logic[31:0] trace_line;
        logic trace_line_enabled;
        logic trace_req_line;
        logic trace_active_line;
        logic[31:0] trace_word0;
        logic[31:0] trace_word1;
        L2ActiveRequestComb active_request;
        L2RequestGeometryComb request_geometry;
        L2EvictCandidateComb evict_candidate;
        L2HitLookupComb hit_lookup;
        L2WordPairComb hit_write_pair;
        L2WordPairComb fill_write_pair;
        logic[256-1:0] completion_data;
        active_request = L2CacheRequest___active_request_comb;
        request_geometry = L2CacheRequest___request_geometry_comb;
        evict_candidate = L2CacheMemory___evict_candidate_comb;
        hit_lookup = L2CacheTagData___hit_lookup_comb;
        if ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP_RESULT) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_RESULT)) begin
            evict_candidate = L2CacheState___lookup_evict_reg;
            hit_lookup = L2CacheState___lookup_hit_reg;
        end
        hit_write_pair = L2CacheTagData___hit_write_pair_comb;
        fill_write_pair = L2CacheTagData___fill_write_pair_comb;
        completion_data = 'h0;
        trace_line='h0;
        trace_line_enabled=0;
        trace_req_line=0;
        trace_active_line=0;
        if (debugen_in) begin
            trace_line_enabled=1;
            trace_line='h400;
            trace_req_line=(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) == trace_line);
            trace_active_line=(((unsigned'(32'(active_request.request.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) == trace_line);
        end
        trace_word0='h0;
        trace_word1='h0;
        dma_line_fire=dma_line_valid_in && dma_line_ready_out;
        for (i='h0;i < DATA_BANKS;i=i+1) begin
        end
        for (i='h0;i < WAYS;i=i+1) begin
        end
        for (i='h0;i < CPU_PORTS;i=i+1) begin
            L2CacheState___response_reg[CPU_RESPONSE_BASE + i].valid <= unsigned'(1'(0));
        end
        if ((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP_CAPTURE) || (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_CAPTURE)) begin
            for (i='h0;i < DATA_BANKS;i=i+1) begin
                L2CacheState___lookup_data_reg_tmp[i] = L2CacheState___data_ram__data_out[i];
            end
            for (way='h0;way < WAYS;way=way+1) begin
                L2CacheState___lookup_tag_reg_tmp[way] = L2CacheState___tag_ram__data_out[way];
            end
        end
        for (i='h0;i < MEM_PORTS;i=i+1) begin
            L2CacheState___slave_aw_novelty_reg_tmp[i] = (!L2CacheState___slave_aw_seen_reg[i].valid || (L2CacheState___slave_aw_seen_reg[i].addr != axi_in__awaddr_in[i])) || (L2CacheState___slave_aw_seen_reg[i].id != axi_in__awid_in[i]);
            L2CacheState___slave_ar_novelty_reg_tmp[i] = (!L2CacheState___slave_ar_seen_reg[i].valid || (L2CacheState___slave_ar_seen_reg[i].addr != axi_in__araddr_in[i])) || (L2CacheState___slave_ar_seen_reg[i].id != axi_in__arid_in[i]);
            if (!axi_in__awvalid_in[i]) begin
                L2CacheState___slave_aw_seen_reg[i].valid <= unsigned'(1'(0));
            end
            if (!axi_in__arvalid_in[i]) begin
                L2CacheState___slave_ar_seen_reg[i].valid <= unsigned'(1'(0));
            end
            if (L2CacheState___response_reg[i].b.valid && axi_in__bready_in[i]) begin
                L2CacheState___response_reg[i].b.valid<=0;
            end
            if (L2CacheState___response_reg[i].r.valid && axi_in__rready_in[i]) begin
                L2CacheState___response_reg[i].r.valid<=0;
                L2CacheState___response_reg[i].r.last<=0;
            end
            if (((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) && axi_in__awvalid_in[i]) && axi_in__awready_out[i]) begin
                L2CacheState___slave_aw_reg[i].valid <= unsigned'(1'(1));
                L2CacheState___slave_aw_reg[i].addr <= unsigned'(32'(unsigned'(32'(axi_in__awaddr_in[i]))));
                L2CacheState___slave_aw_reg[i].id <= axi_in__awid_in[i];
                L2CacheState___slave_aw_seen_reg[i].valid <= unsigned'(1'(1));
                L2CacheState___slave_aw_seen_reg[i].addr <= unsigned'(32'(unsigned'(32'(axi_in__awaddr_in[i]))));
                L2CacheState___slave_aw_seen_reg[i].id <= axi_in__awid_in[i];
            end
            if (((L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) && axi_in__arvalid_in[i]) && axi_in__arready_out[i]) begin
                L2CacheState___slave_ar_seen_reg[i].valid <= unsigned'(1'(1));
                L2CacheState___slave_ar_seen_reg[i].addr <= unsigned'(32'(unsigned'(32'(axi_in__araddr_in[i]))));
                L2CacheState___slave_ar_seen_reg[i].id <= axi_in__arid_in[i];
            end
        end
        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_INIT) begin
            if (L2CacheState___init_set_reg == (SETS - 'h1)) begin
                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
            end
            else begin
                L2CacheState___init_set_reg_tmp = L2CacheState___init_set_reg + 'h1;
            end
        end
        else begin
            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IDLE) begin
                if (active_request.valid && !((((((L2CacheState___response_reg[(CPU_RESPONSE_BASE + active_request.request.cpu_index)].valid && !active_request.request.from_slave) && (L2CacheState___response_reg[(CPU_RESPONSE_BASE + active_request.request.cpu_index)].data_port == active_request.request.port)) && (L2CacheState___response_reg[(CPU_RESPONSE_BASE + active_request.request.cpu_index)].read == active_request.request.read)) && (L2CacheState___response_reg[(CPU_RESPONSE_BASE + active_request.request.cpu_index)].write == active_request.request.write)) && (L2CacheState___response_reg[(CPU_RESPONSE_BASE + active_request.request.cpu_index)].addr == active_request.request.addr)))) begin
                    if (trace_active_line) begin
                        $write("trace-l2 cycle=%x cpu=%x accept addr=%08x rd=%x wr=%x wdata=%08x mask=%02x slave=%x dport=%x victim=%x\n", $time, unsigned'(32'(active_request.request.cpu_index)), unsigned'(32'(active_request.request.addr)), active_request.request.read, active_request.request.write, unsigned'(32'(active_request.request.write_data)), unsigned'(32'(active_request.request.write_mask)), active_request.request.from_slave, active_request.request.port, unsigned'(32'(L2CacheState___victim_reg)));
                    end
                    L2CacheState___req_reg_tmp = active_request.request;
                    if (!active_request.request.from_slave) begin
                        L2CacheState___cpu_rr_reg_tmp = (active_request.request.cpu_index == (CPU_PORTS - 'h1)) ? (unsigned'(32'('h0))) : (unsigned'(32'(active_request.request.cpu_index)) + 'h1);
                    end
                    for (i='h0;i < MEM_PORTS;i=i+1) begin
                        if ((active_request.request.from_slave && active_request.request.write) && (active_request.request.slave_index == i)) begin
                            L2CacheState___slave_aw_reg[i].valid <= unsigned'(1'(0));
                        end
                    end
                    L2CacheState___state_reg_tmp = (active_request.cross_line_read) ? (L2CacheFsmState_pkg::ST_CROSS_AR0) : (L2CacheFsmState_pkg::ST_READ);
                end
            end
            else begin
                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_READ) begin
                    if (!dma_line_fire) begin
                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_LOOKUP_CAPTURE;
                    end
                end
                else begin
                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP_CAPTURE) begin
                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_LOOKUP;
                    end
                    else begin
                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP) begin
                            L2CacheState___lookup_hit_reg_tmp = hit_lookup;
                            L2CacheState___lookup_evict_reg_tmp = evict_candidate;
                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_LOOKUP_RESULT;
                        end
                        else begin
                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_LOOKUP_RESULT) begin
                                if (!request_geometry.addr_in_memory) begin
                                    if (trace_req_line) begin
                                        $write("trace-l2 cycle=%x lookup-outside addr=%08x rd=%x wr=%x\n", $time, unsigned'(32'(L2CacheState___req_reg.addr)), L2CacheState___req_reg.read, L2CacheState___req_reg.write);
                                    end
                                    if (L2CacheState___req_reg.from_slave) begin
                                        for (i='h0;i < MEM_PORTS;i=i+1) begin
                                            if (L2CacheState___req_reg.slave_index == i) begin
                                                if (L2CacheState___req_reg.read) begin
                                                    send_slave_read_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)), 'h0);
                                                end
                                                if (L2CacheState___req_reg.write) begin
                                                    send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                end
                                            end
                                        end
                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                    end
                                    else begin
                                        send_cpu_response('h0);
                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                    end
                                end
                                else begin
                                    if (L2CacheMemory___req_uncached_region_comb) begin
                                        if (trace_req_line) begin
                                            $write("trace-l2 cycle=%x lookup-uncached addr=%08x rd=%x wr=%x\n", $time, unsigned'(32'(L2CacheState___req_reg.addr)), L2CacheState___req_reg.read, L2CacheState___req_reg.write);
                                        end
                                        L2CacheState___state_reg_tmp = (L2CacheState___req_reg.read) ? (L2CacheFsmState_pkg::ST_IO_AR) : (L2CacheFsmState_pkg::ST_IO_AW);
                                    end
                                    else begin
                                        if (hit_lookup.hit) begin
                                            if (trace_req_line) begin
                                                trace_word0=unsigned'(32'(hit_lookup.beat));
                                                trace_word1=(PORT_WORDS > 'h1) ? (unsigned'(32'((hit_lookup.beat >> 'h20)))) : ('h0);
                                                $write("trace-l2 cycle=%x lookup-hit addr=%08x rd=%x wr=%x way=%x word=%x hit_word=%08x beat0=%08x beat1=%08x wdata=%08x mask=%02x\n", $time, unsigned'(32'(L2CacheState___req_reg.addr)), L2CacheState___req_reg.read, L2CacheState___req_reg.write, unsigned'(32'(hit_lookup.way)), unsigned'(32'(request_geometry.word)), unsigned'(32'(hit_lookup.read_word)), trace_word0, trace_word1, unsigned'(32'(L2CacheState___req_reg.write_data)), unsigned'(32'(L2CacheState___req_reg.write_mask)));
                                            end
                                            if (L2CacheState___req_reg.from_slave) begin
                                                for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                    if (L2CacheState___req_reg.slave_index == i) begin
                                                        if (L2CacheState___req_reg.read) begin
                                                            send_slave_read_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)), hit_lookup.beat);
                                                        end
                                                        if (L2CacheState___req_reg.write && !request_geometry.cross_line_write) begin
                                                            send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                        end
                                                    end
                                                end
                                            end
                                            if (request_geometry.cross_line_write) begin
                                                L2CacheState___req_reg_tmp.addr = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) + CACHE_LINE_SIZE));
                                                L2CacheState___req_reg_tmp.write_data = request_geometry.cross_write_data;
                                                L2CacheState___req_reg_tmp.write_mask = request_geometry.cross_write_mask;
                                                L2CacheState___req_reg_tmp.write_strobe = active_request.request.write_strobe;
                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_WRITE_READ;
                                            end
                                            else begin
                                                if (!L2CacheState___req_reg.from_slave) begin
                                                    completion_data = 'h0;
                                                    if (L2CacheState___req_reg.read && request_geometry.cross_beat_read) begin
                                                        completion_data['h0 +:32] = hit_lookup.read_word;
                                                    end
                                                    else begin
                                                        if (L2CacheState___req_reg.read) begin
                                                            completion_data = hit_lookup.beat;
                                                        end
                                                    end
                                                    send_cpu_response(completion_data);
                                                end
                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                            end
                                        end
                                        else begin
                                            if (trace_req_line) begin
                                                $write("trace-l2 cycle=%x lookup-miss addr=%08x rd=%x wr=%x victim=%x evict_valid=%x evict_dirty=%x evict_tag=%08x\n", $time, unsigned'(32'(L2CacheState___req_reg.addr)), L2CacheState___req_reg.read, L2CacheState___req_reg.write, unsigned'(32'(L2CacheState___victim_reg)), evict_candidate.valid, evict_candidate.dirty, unsigned'(32'(evict_candidate.tag)));
                                            end
                                            L2CacheState___fill_way_reg_tmp = L2CacheState___victim_reg;
                                            L2CacheState___fill_beat_reg_tmp = 'h0;
                                            L2CacheState___evict_beat_reg_tmp = 'h0;
                                            L2CacheState___evict_tag_reg_tmp = evict_candidate.tag;
                                            L2CacheState___evict_line_reg_tmp = evict_candidate.line;
                                            L2CacheState___state_reg_tmp = ((!L2CacheState___req_reg.from_slave && request_geometry.cross_beat_read)) ? (L2CacheFsmState_pkg::ST_CROSS_AR0) : ((((evict_candidate.valid && evict_candidate.dirty)) ? (L2CacheFsmState_pkg::ST_EVICT_AW) : (L2CacheFsmState_pkg::ST_AXI_AR)));
                                        end
                                    end
                                end
                            end
                            else begin
                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_READ) begin
                                    if (!dma_line_fire) begin
                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_WRITE_CAPTURE;
                                    end
                                end
                                else begin
                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_CAPTURE) begin
                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_WRITE_LOOKUP;
                                    end
                                    else begin
                                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_LOOKUP) begin
                                            L2CacheState___lookup_hit_reg_tmp = hit_lookup;
                                            L2CacheState___lookup_evict_reg_tmp = evict_candidate;
                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_WRITE_RESULT;
                                        end
                                        else begin
                                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_WRITE_RESULT) begin
                                                if (!request_geometry.addr_in_memory) begin
                                                    if (L2CacheState___req_reg.from_slave) begin
                                                        for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                            if (L2CacheState___req_reg.slave_index == i) begin
                                                                send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                            end
                                                        end
                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                    end
                                                    else begin
                                                        send_cpu_response('h0);
                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                    end
                                                end
                                                else begin
                                                    if (hit_lookup.hit) begin
                                                        if (L2CacheState___req_reg.from_slave) begin
                                                            for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                                if (L2CacheState___req_reg.slave_index == i) begin
                                                                    send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                                end
                                                            end
                                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                        end
                                                        else begin
                                                            send_cpu_response('h0);
                                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                        end
                                                    end
                                                    else begin
                                                        L2CacheState___fill_way_reg_tmp = L2CacheState___victim_reg;
                                                        L2CacheState___fill_beat_reg_tmp = 'h0;
                                                        L2CacheState___evict_beat_reg_tmp = 'h0;
                                                        L2CacheState___evict_tag_reg_tmp = evict_candidate.tag;
                                                        L2CacheState___evict_line_reg_tmp = evict_candidate.line;
                                                        L2CacheState___state_reg_tmp = ((evict_candidate.valid && evict_candidate.dirty)) ? (L2CacheFsmState_pkg::ST_EVICT_AW) : (L2CacheFsmState_pkg::ST_AXI_AR);
                                                    end
                                                end
                                            end
                                            else begin
                                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_EVICT_AW) begin
                                                    if (L2CacheMemory___axi_out_driver_comb.aw.valid && L2CacheMemory___axi_out_selected_resp_comb.aw.ready) begin
                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_EVICT_W;
                                                    end
                                                end
                                                else begin
                                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_EVICT_W) begin
                                                        if (L2CacheMemory___axi_out_driver_comb.w.valid && L2CacheMemory___axi_out_selected_resp_comb.w.ready) begin
                                                            if (trace_line_enabled && ((((L2CacheMemory___axi_route_comb.aw_full_addr & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) == trace_line))) begin
                                                                trace_word0=unsigned'(32'(L2CacheMemory___evict_line_comb));
                                                                trace_word1=(PORT_WORDS > 'h1) ? (unsigned'(32'((L2CacheMemory___evict_line_comb >> 'h20)))) : ('h0);
                                                                $write("trace-l2 cycle=%x evict addr=%08x beat=%x data0=%08x data1=%08x way=%x\n", $time, unsigned'(32'(L2CacheMemory___axi_route_comb.aw_full_addr)), unsigned'(32'(L2CacheState___evict_beat_reg)), trace_word0, trace_word1, unsigned'(32'(evict_candidate.way)));
                                                            end
                                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_EVICT_B;
                                                        end
                                                    end
                                                    else begin
                                                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_EVICT_B) begin
                                                            if (L2CacheMemory___axi_out_selected_resp_comb.b.valid) begin
                                                                if (L2CacheState___evict_beat_reg == (LINE_BEATS - 'h1)) begin
                                                                    L2CacheState___fill_beat_reg_tmp = 'h0;
                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_AXI_AR;
                                                                end
                                                                else begin
                                                                    L2CacheState___evict_beat_reg_tmp = L2CacheState___evict_beat_reg + 'h1;
                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_EVICT_AW;
                                                                end
                                                            end
                                                        end
                                                        else begin
                                                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_AR) begin
                                                                if (L2CacheMemory___axi_out_driver_comb.ar.valid && L2CacheMemory___axi_out_selected_resp_comb.ar.ready) begin
                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_AXI_R;
                                                                end
                                                            end
                                                            else begin
                                                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_R) begin
                                                                    if (L2CacheMemory___axi_out_selected_resp_comb.r.valid && L2CacheMemory___axi_out_driver_comb.r.ready) begin
                                                                        L2CacheState___refill_data_reg_tmp = L2CacheMemory___axi_out_selected_resp_comb.r.data;
                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_AXI_R_WRITE;
                                                                    end
                                                                end
                                                                else begin
                                                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_AXI_R_WRITE) begin
                                                                        if (trace_req_line) begin
                                                                            trace_word0=unsigned'(32'(L2CacheState___refill_data_reg));
                                                                            trace_word1=(PORT_WORDS > 'h1) ? (unsigned'(32'((L2CacheState___refill_data_reg >> 'h20)))) : ('h0);
                                                                            $write("trace-l2 cycle=%x fill addr=%08x beat=%x data0=%08x data1=%08x req_word=%x req_beat=%x\n", $time, unsigned'(32'(L2CacheMemory___axi_route_comb.ar_full_addr)), unsigned'(32'(L2CacheState___fill_beat_reg)), trace_word0, trace_word1, unsigned'(32'(request_geometry.word)), unsigned'(32'(request_geometry.beat)));
                                                                        end
                                                                        if (L2CacheState___req_reg.read && (L2CacheState___fill_beat_reg == request_geometry.beat)) begin
                                                                            L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].r.data <= L2CacheState___refill_data_reg;
                                                                        end
                                                                        if (L2CacheState___fill_beat_reg == (LINE_BEATS - 'h1)) begin
                                                                            L2CacheState___victim_reg_tmp = ((L2CacheState___victim_reg == (WAYS - 'h1))) ? ('h0) : (L2CacheState___victim_reg + 'h1);
                                                                            if (request_geometry.cross_line_write) begin
                                                                                L2CacheState___req_reg_tmp.addr = unsigned'(32'(((unsigned'(32'(L2CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) + CACHE_LINE_SIZE));
                                                                                L2CacheState___req_reg_tmp.write_data = request_geometry.cross_write_data;
                                                                                L2CacheState___req_reg_tmp.write_mask = request_geometry.cross_write_mask;
                                                                                L2CacheState___req_reg_tmp.write_strobe = active_request.request.write_strobe;
                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_WRITE_READ;
                                                                            end
                                                                            else begin
                                                                                if (L2CacheState___req_reg.from_slave) begin
                                                                                    for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                                                        if (L2CacheState___req_reg.slave_index == i) begin
                                                                                            if (L2CacheState___req_reg.read) begin
                                                                                                send_slave_read_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)), ((L2CacheState___fill_beat_reg == request_geometry.beat)) ? (L2CacheState___refill_data_reg) : (L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].r.data));
                                                                                            end
                                                                                            if (L2CacheState___req_reg.write) begin
                                                                                                send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                                                            end
                                                                                        end
                                                                                    end
                                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                end
                                                                                else begin
                                                                                    completion_data = (L2CacheState___req_reg.read) ? ((((L2CacheState___fill_beat_reg == request_geometry.beat)) ? (L2CacheState___refill_data_reg) : (L2CacheState___response_reg[CPU_RESPONSE_BASE + L2CacheState___req_reg.cpu_index].r.data))) : ('h0);
                                                                                    send_cpu_response(completion_data);
                                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                end
                                                                            end
                                                                        end
                                                                        else begin
                                                                            L2CacheState___fill_beat_reg_tmp = L2CacheState___fill_beat_reg + 'h1;
                                                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_AXI_AR;
                                                                        end
                                                                    end
                                                                    else begin
                                                                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR0) begin
                                                                            if (L2CacheMemory___axi_out_driver_comb.ar.valid && L2CacheMemory___axi_out_selected_resp_comb.ar.ready) begin
                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_R0;
                                                                            end
                                                                        end
                                                                        else begin
                                                                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R0) begin
                                                                                if (L2CacheMemory___axi_out_selected_resp_comb.r.valid && L2CacheMemory___axi_out_driver_comb.r.ready) begin
                                                                                    L2CacheState___cross_low_reg_tmp = L2CacheMemory___axi_out_selected_resp_comb.r.data;
                                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_AR1;
                                                                                end
                                                                            end
                                                                            else begin
                                                                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_AR1) begin
                                                                                    if (L2CacheMemory___axi_out_driver_comb.ar.valid && L2CacheMemory___axi_out_selected_resp_comb.ar.ready) begin
                                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_R1;
                                                                                    end
                                                                                end
                                                                                else begin
                                                                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_R1) begin
                                                                                        if (L2CacheMemory___axi_out_selected_resp_comb.r.valid && L2CacheMemory___axi_out_driver_comb.r.ready) begin
                                                                                            L2CacheState___cross_high_reg_tmp = L2CacheMemory___axi_out_selected_resp_comb.r.data;
                                                                                            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_CROSS_DONE;
                                                                                        end
                                                                                    end
                                                                                    else begin
                                                                                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_CROSS_DONE) begin
                                                                                            if (L2CacheState___req_reg.from_slave) begin
                                                                                                for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                                                                    if (L2CacheState___req_reg.slave_index == i) begin
                                                                                                        send_slave_read_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)), L2CacheTagData___cross_read_data_comb);
                                                                                                    end
                                                                                                end
                                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                            end
                                                                                            else begin
                                                                                                send_cpu_response(L2CacheTagData___cross_read_data_comb);
                                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                            end
                                                                                        end
                                                                                        else begin
                                                                                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AW) begin
                                                                                                if (L2CacheMemory___axi_out_driver_comb.aw.valid && L2CacheMemory___axi_out_selected_resp_comb.aw.ready) begin
                                                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IO_W;
                                                                                                end
                                                                                            end
                                                                                            else begin
                                                                                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_W) begin
                                                                                                    if (L2CacheMemory___axi_out_driver_comb.w.valid && L2CacheMemory___axi_out_selected_resp_comb.w.ready) begin
                                                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IO_B;
                                                                                                    end
                                                                                                end
                                                                                                else begin
                                                                                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_B) begin
                                                                                                        if (L2CacheMemory___axi_out_selected_resp_comb.b.valid) begin
                                                                                                            if (L2CacheState___req_reg.from_slave) begin
                                                                                                                for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                                                                                    if (L2CacheState___req_reg.slave_index == i) begin
                                                                                                                        send_slave_write_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)));
                                                                                                                    end
                                                                                                                end
                                                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                                            end
                                                                                                            else begin
                                                                                                                send_cpu_response('h0);
                                                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                                            end
                                                                                                        end
                                                                                                    end
                                                                                                    else begin
                                                                                                        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_AR) begin
                                                                                                            if (L2CacheMemory___axi_out_driver_comb.ar.valid && L2CacheMemory___axi_out_selected_resp_comb.ar.ready) begin
                                                                                                                L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IO_R;
                                                                                                            end
                                                                                                        end
                                                                                                        else begin
                                                                                                            if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_R) begin
                                                                                                                if (L2CacheMemory___axi_out_selected_resp_comb.r.valid && L2CacheMemory___axi_out_driver_comb.r.ready) begin
                                                                                                                    L2CacheState___refill_data_reg_tmp = L2CacheMemory___axi_out_selected_resp_comb.r.data;
                                                                                                                    L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IO_R_RESULT;
                                                                                                                end
                                                                                                            end
                                                                                                            else begin
                                                                                                                if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_IO_R_RESULT) begin
                                                                                                                    if (L2CacheState___req_reg.from_slave) begin
                                                                                                                        for (i='h0;i < MEM_PORTS;i=i+1) begin
                                                                                                                            if (L2CacheState___req_reg.slave_index == i) begin
                                                                                                                                send_slave_read_response(unsigned'(3'(i)), unsigned'(4'(L2CacheState___req_reg.slave_id)), L2CacheState___refill_data_reg);
                                                                                                                            end
                                                                                                                        end
                                                                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                                                    end
                                                                                                                    else begin
                                                                                                                        send_cpu_response(L2CacheState___refill_data_reg);
                                                                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                                                    end
                                                                                                                end
                                                                                                                else begin
                                                                                                                    if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_DONE) begin
                                                                                                                        L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_IDLE;
                                                                                                                    end
                                                                                                                end
                                                                                                            end
                                                                                                        end
                                                                                                    end
                                                                                                end
                                                                                            end
                                                                                        end
                                                                                    end
                                                                                end
                                                                            end
                                                                        end
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if (reset) begin
            L2CacheState___state_reg_tmp = '0;
            L2CacheState___req_reg_tmp = '0;
            L2CacheState___cpu_rr_reg_tmp = '0;
            L2CacheState___victim_reg_tmp = '0;
            L2CacheState___fill_way_reg_tmp = '0;
            L2CacheState___init_set_reg_tmp = '0;
            L2CacheState___cross_low_reg_tmp = '0;
            L2CacheState___cross_high_reg_tmp = '0;
            L2CacheState___refill_data_reg_tmp = '0;
            L2CacheState___fill_beat_reg_tmp = '0;
            L2CacheState___evict_beat_reg_tmp = '0;
            L2CacheState___evict_tag_reg_tmp = '0;
            L2CacheState___evict_line_reg_tmp = '0;
            for (i='h0;i < RESPONSE_SLOTS;i=i+1) begin
                L2CacheState___response_reg[i].valid <= unsigned'(1'(0));
                L2CacheState___response_reg[i].read <= unsigned'(1'(0));
                L2CacheState___response_reg[i].write <= unsigned'(1'(0));
                L2CacheState___response_reg[i].data_port <= unsigned'(1'(0));
                L2CacheState___response_reg[i].addr <= unsigned'(32'h0);
                L2CacheState___response_reg[i].b.valid<=0;
                L2CacheState___response_reg[i].b.id <= 'h0;
                L2CacheState___response_reg[i].r.valid<=0;
                L2CacheState___response_reg[i].r.id <= 'h0;
                L2CacheState___response_reg[i].r.data <= 'h0;
                L2CacheState___response_reg[i].r.last<=0;
            end
            for (i='h0;i < MEM_PORTS;i=i+1) begin
                L2CacheState___slave_aw_reg[i].valid <= unsigned'(1'(0));
                L2CacheState___slave_aw_reg[i].addr <= unsigned'(32'h0);
                L2CacheState___slave_aw_reg[i].id <= 'h0;
                L2CacheState___slave_aw_seen_reg[i].valid <= unsigned'(1'(0));
                L2CacheState___slave_aw_seen_reg[i].addr <= unsigned'(32'h0);
                L2CacheState___slave_aw_seen_reg[i].id <= 'h0;
                L2CacheState___slave_ar_seen_reg[i].valid <= unsigned'(1'(0));
                L2CacheState___slave_ar_seen_reg[i].addr <= unsigned'(32'h0);
                L2CacheState___slave_ar_seen_reg[i].id <= 'h0;
            end
            L2CacheState___slave_aw_novelty_reg_tmp = '0;
            L2CacheState___slave_ar_novelty_reg_tmp = '0;
            L2CacheState___lookup_data_reg_tmp = '0;
            L2CacheState___lookup_tag_reg_tmp = '0;
            L2CacheState___lookup_hit_reg_tmp = '0;
            L2CacheState___lookup_evict_reg_tmp = '0;
            L2CacheState___state_reg_tmp = L2CacheFsmState_pkg::ST_INIT;
        end
    end
    endtask

    task _work_clk (input logic reset);
    begin: _work_clk
    end
    endtask

    always_ff @(posedge clk) begin

        _work_clk(reset);

    end

    always_ff @(posedge l2_clock) begin
        L2CacheState___lookup_data_reg_tmp = L2CacheState___lookup_data_reg;
        L2CacheState___lookup_tag_reg_tmp = L2CacheState___lookup_tag_reg;
        L2CacheState___lookup_hit_reg_tmp = L2CacheState___lookup_hit_reg;
        L2CacheState___lookup_evict_reg_tmp = L2CacheState___lookup_evict_reg;
        L2CacheState___state_reg_tmp = L2CacheState___state_reg;
        L2CacheState___req_reg_tmp = L2CacheState___req_reg;
        L2CacheState___cpu_rr_reg_tmp = L2CacheState___cpu_rr_reg;
        L2CacheState___victim_reg_tmp = L2CacheState___victim_reg;
        L2CacheState___fill_way_reg_tmp = L2CacheState___fill_way_reg;
        L2CacheState___init_set_reg_tmp = L2CacheState___init_set_reg;
        L2CacheState___cross_low_reg_tmp = L2CacheState___cross_low_reg;
        L2CacheState___cross_high_reg_tmp = L2CacheState___cross_high_reg;
        L2CacheState___refill_data_reg_tmp = L2CacheState___refill_data_reg;
        L2CacheState___fill_beat_reg_tmp = L2CacheState___fill_beat_reg;
        L2CacheState___evict_beat_reg_tmp = L2CacheState___evict_beat_reg;
        L2CacheState___evict_tag_reg_tmp = L2CacheState___evict_tag_reg;
        L2CacheState___evict_line_reg_tmp = L2CacheState___evict_line_reg;
        L2CacheState___slave_aw_novelty_reg_tmp = L2CacheState___slave_aw_novelty_reg;
        L2CacheState___slave_ar_novelty_reg_tmp = L2CacheState___slave_ar_novelty_reg;

        _work_l2_clock(reset);

        L2CacheState___lookup_data_reg <= L2CacheState___lookup_data_reg_tmp;
        L2CacheState___lookup_tag_reg <= L2CacheState___lookup_tag_reg_tmp;
        L2CacheState___lookup_hit_reg <= L2CacheState___lookup_hit_reg_tmp;
        L2CacheState___lookup_evict_reg <= L2CacheState___lookup_evict_reg_tmp;
        L2CacheState___state_reg <= L2CacheState___state_reg_tmp;
        L2CacheState___req_reg <= L2CacheState___req_reg_tmp;
        L2CacheState___cpu_rr_reg <= L2CacheState___cpu_rr_reg_tmp;
        L2CacheState___victim_reg <= L2CacheState___victim_reg_tmp;
        L2CacheState___fill_way_reg <= L2CacheState___fill_way_reg_tmp;
        L2CacheState___init_set_reg <= L2CacheState___init_set_reg_tmp;
        L2CacheState___cross_low_reg <= L2CacheState___cross_low_reg_tmp;
        L2CacheState___cross_high_reg <= L2CacheState___cross_high_reg_tmp;
        L2CacheState___refill_data_reg <= L2CacheState___refill_data_reg_tmp;
        L2CacheState___fill_beat_reg <= L2CacheState___fill_beat_reg_tmp;
        L2CacheState___evict_beat_reg <= L2CacheState___evict_beat_reg_tmp;
        L2CacheState___evict_tag_reg <= L2CacheState___evict_tag_reg_tmp;
        L2CacheState___evict_line_reg <= L2CacheState___evict_line_reg_tmp;
        L2CacheState___slave_aw_novelty_reg <= L2CacheState___slave_aw_novelty_reg_tmp;
        L2CacheState___slave_ar_novelty_reg <= L2CacheState___slave_ar_novelty_reg_tmp;
    end


endmodule
