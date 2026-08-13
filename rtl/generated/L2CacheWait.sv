`default_nettype none

import Predef_pkg::*;
import L2CpuWaitComb_pkg::*;
import L2CacheFsmState_pkg::*;
import L2HitLookupComb_pkg::*;
import L2WordPairComb_pkg::*;
import L2IoWritePayloadComb_pkg::*;
import L2AxiRouteComb_pkg::*;
import Axi4WriteAddress32_4_pkg::*;
import Axi4WriteData256_pkg::*;
import Axi4WriteResponseReady_pkg::*;
import Axi4ReadAddress32_4_pkg::*;
import Axi4ReadDataReady_pkg::*;
import Axi4Driver32_4_256_pkg::*;
import Axi4WriteAddressReady_pkg::*;
import Axi4WriteDataReady_pkg::*;
import Axi4WriteResponse4_pkg::*;
import Axi4ReadAddressReady_pkg::*;
import Axi4ReadData4_256_pkg::*;
import Axi4Responder4_256_pkg::*;
import L2EvictCandidateComb_pkg::*;
import L2AxiRequestNoveltyComb_pkg::*;
import CacheRequest_pkg::*;
import L2ActiveRequestComb_pkg::*;
import L2RequestGeometryComb_pkg::*;
import CacheResponse_pkg::*;


module L2CacheWait #(
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
    parameter  LINE_WORDS = CACHE_LINE_SIZE/'h4;
    parameter  PORT_BYTES = PORT_BITWIDTH/'h8;
    parameter  PORT_WORDS = PORT_BITWIDTH/'h20;
    parameter  LINE_BEATS = CACHE_LINE_SIZE/PORT_BYTES;
    parameter  SETS = (CACHE_SIZE/CACHE_LINE_SIZE)/WAYS;
    parameter  SET_BITS = $clog2(SETS);
    parameter  LINE_BITS = $clog2(CACHE_LINE_SIZE);
    parameter  TAG_BITS = (ADDR_BITS - SET_BITS) - LINE_BITS;
    parameter  DATA_BANKS = WAYS*LINE_WORDS;
    parameter  CPU_RESPONSE_BASE = 'h8;
    parameter  RESPONSE_SLOTS = 'h10;
    parameter  MEM_ADDR_MASK64 = ((MEM_ADDR_BITS>='h40)) ? (~64'h0) : ((((64'h1 <<< MEM_ADDR_BITS)) - 64'h1));
    parameter  LINE_BEAT_BITS = (LINE_BEATS<='h1) ? ('h1) : ($clog2(LINE_BEATS));
    parameter  WORD_BITS = $clog2(LINE_WORDS);
    parameter  WAY_BITS = (WAYS<='h1) ? ('h1) : ($clog2(WAYS));
    parameter  TAG_RAM_BITS = (((((TAG_BITS + 'h2) + 'h7))/'h8))*'h8;
    parameter  MEM_PORT_BITS = $clog2(MEM_PORTS);


    // regs and combs
    L2CpuWaitComb cpu_wait_comb[CPU_PORTS];
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
    (* ram_style = "block" *)
    reg[4-1:0][8-1:0] L2CacheState___data_ram[DATA_BANKS][((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)];
    (* ram_style = "block" *)
    reg[(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))-1:0][8-1:0] L2CacheState___tag_ram[WAYS][((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)];
    reg[DATA_BANKS-1:0][32-1:0] L2CacheState___data_q_reg;
    reg[DATA_BANKS-1:0][(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___tag_q_reg;
    reg[5-1:0] L2CacheState___state_reg;
    CacheRequest L2CacheState___req_reg;
    reg[3-1:0] L2CacheState___cpu_rr_reg;
    reg[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___victim_reg;
    reg[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___fill_way_reg;
    reg[$clog2((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)-1:0] L2CacheState___init_set_reg;
    CacheResponse[16-1:0] L2CacheState___response_reg;
    reg[PORT_BITWIDTH-1:0] L2CacheState___cross_low_reg;
    reg[PORT_BITWIDTH-1:0] L2CacheState___cross_high_reg;
    reg[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___fill_beat_reg;
    reg[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___evict_beat_reg;
    reg[(ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)-1:0] L2CacheState___evict_tag_reg;
    reg[CACHE_LINE_SIZE*'h8-1:0] L2CacheState___evict_line_reg;
    Axi4WriteAddressADDR_BITS_4[8-1:0] L2CacheState___slave_aw_reg;
    Axi4WriteAddressADDR_BITS_4[8-1:0] L2CacheState___slave_aw_seen_reg;
    Axi4ReadAddressADDR_BITS_4[8-1:0] L2CacheState___slave_ar_seen_reg;

    // members

    // tmp variables
    logic[DATA_BANKS-1:0][32-1:0] L2CacheState___data_q_reg_tmp;
    logic[DATA_BANKS-1:0][(((((((ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)) + 'h2) + 'h7))/'h8))*'h8-1:0] L2CacheState___tag_q_reg_tmp;
    logic[5-1:0] L2CacheState___state_reg_tmp;
    CacheRequest L2CacheState___req_reg_tmp;
    logic[3-1:0] L2CacheState___cpu_rr_reg_tmp;
    logic[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___victim_reg_tmp;
    logic[((WAYS<='h1) ? ('h1) : ($clog2(WAYS)))-1:0] L2CacheState___fill_way_reg_tmp;
    logic[$clog2((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS)-1:0] L2CacheState___init_set_reg_tmp;
    CacheResponse[16-1:0] L2CacheState___response_reg_tmp;
    logic[PORT_BITWIDTH-1:0] L2CacheState___cross_low_reg_tmp;
    logic[PORT_BITWIDTH-1:0] L2CacheState___cross_high_reg_tmp;
    logic[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___fill_beat_reg_tmp;
    logic[((CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8))<='h1) ? ('h1) : ($clog2(CACHE_LINE_SIZE/((PORT_BITWIDTH/'h8)))))-1:0] L2CacheState___evict_beat_reg_tmp;
    logic[(ADDR_BITS - $clog2(((CACHE_SIZE/CACHE_LINE_SIZE)/WAYS))) - $clog2(CACHE_LINE_SIZE)-1:0] L2CacheState___evict_tag_reg_tmp;
    logic[CACHE_LINE_SIZE*'h8-1:0] L2CacheState___evict_line_reg_tmp;
    Axi4WriteAddressADDR_BITS_4[8-1:0] L2CacheState___slave_aw_reg_tmp;
    Axi4WriteAddressADDR_BITS_4[8-1:0] L2CacheState___slave_aw_seen_reg_tmp;
    Axi4ReadAddressADDR_BITS_4[8-1:0] L2CacheState___slave_ar_seen_reg_tmp;


    always_comb begin : cpu_wait_comb_func  // cpu_wait_comb_func
        logic[31:0] index;
        logic done_i_read;
        logic done_d_read;
        logic done_d_write;
        for (index='h0;index < CPU_PORTS;index=index+1) begin
            done_i_read=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && !L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].read) && i_mem_in__read_in[index]) && (unsigned'(32'(i_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            done_d_read=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].read) && d_mem_in__read_in[index]) && (unsigned'(32'(d_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            done_d_write=(((L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].valid && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].data_port) && L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].write) && d_mem_in__write_in[index]) && (unsigned'(32'(d_mem_in__addr_in[index])) == unsigned'(32'(L2CacheState___response_reg[(CPU_RESPONSE_BASE + index)].addr)));
            cpu_wait_comb[index] = 0;
            if (i_mem_in__read_in[index]) begin
                cpu_wait_comb[index].instruction = unsigned'(1'(!done_i_read));
            end
            if (d_mem_in__write_in[index]) begin
                cpu_wait_comb[index].data = unsigned'(1'(!done_d_write));
            end
            if (d_mem_in__read_in[index]) begin
                cpu_wait_comb[index].data = unsigned'(1'(!done_d_read));
            end
            if ((L2CacheState___state_reg != L2CacheFsmState_pkg::ST_IDLE) && !done_i_read) begin
                cpu_wait_comb[index].instruction = unsigned'(1'(1));
            end
            if ((L2CacheState___state_reg != L2CacheFsmState_pkg::ST_IDLE) && !((done_d_read || done_d_write))) begin
                cpu_wait_comb[index].data = unsigned'(1'(1));
            end
        end
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
            if (L2CacheState___tag_q_reg[i][(TAG_BITS + 'h1)] && (L2CacheState___tag_q_reg[i]['h0 +:(TAG_BITS - 'h1) - 'h0 + 1] == L2CacheRequest___request_geometry_comb.tag)) begin
                L2CacheTagData___hit_lookup_comb.hit = unsigned'(1'(1));
                L2CacheTagData___hit_lookup_comb.way = unsigned'(32'(i));
            end
        end
        for (i='h0;i < DATA_BANKS;i=i+1) begin
            way=i/LINE_WORDS;
            word_index=i % LINE_WORDS;
            if (L2CacheTagData___hit_lookup_comb.hit && (unsigned'(32'(L2CacheTagData___hit_lookup_comb.way)) == way)) begin
                word_data=unsigned'(32'(L2CacheState___data_q_reg[i]));
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
                    L2CacheTagData___hit_lookup_comb.beat[beat_word*'h20 +:32] = L2CacheState___data_q_reg[i];
                end
            end
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
        old_word=unsigned'(32'((L2CacheMemory___axi_out_selected_resp_comb.r.data >> (word*'h20))));
        old_next_word='h0;
        if ((unsigned'(32'(L2CacheRequest___request_geometry_comb.word)) + 'h1) < LINE_WORDS) begin
            old_next_word=unsigned'(32'((L2CacheMemory___axi_out_selected_resp_comb.r.data >> (next_word*'h20))));
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

    always_comb begin : L2CacheTagData___tag_write_data_comb_func  // L2CacheTagData___tag_write_data_comb_func
        if (L2CacheState___state_reg == L2CacheFsmState_pkg::ST_INIT) begin
            L2CacheTagData___tag_write_data_comb = 'h0;
        end
        else begin
            L2CacheTagData___tag_write_data_comb = (((unsigned'(64'('h1)) <<< ((TAG_BITS + 'h1)))) | ((unsigned'(64'(L2CacheState___req_reg.write)) <<< TAG_BITS))) | unsigned'(64'(L2CacheRequest___request_geometry_comb.tag));
        end
    end

    always_comb begin : L2CacheTagData___read_data_comb_func  // L2CacheTagData___read_data_comb_func
        logic[31:0] index;
        for (index='h0;index < CPU_PORTS;index=index+1) begin
            L2CacheTagData___read_data_comb[index] = (L2CacheState___response_reg[CPU_RESPONSE_BASE + index].valid) ? (L2CacheState___response_reg[CPU_RESPONSE_BASE + index].r.data) : ('h0);
        end
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
                L2CacheMemory___evict_candidate_comb.valid = unsigned'(1'(L2CacheState___tag_q_reg[i][TAG_BITS + 'h1]));
                L2CacheMemory___evict_candidate_comb.dirty = unsigned'(1'(L2CacheState___tag_q_reg[i][TAG_BITS]));
                L2CacheMemory___evict_candidate_comb.tag = unsigned'(32'(unsigned'(64'(L2CacheState___tag_q_reg[i]['h0 +:TAG_BITS - 'h1 - 'h0 + 1]))));
            end
        end
        for (i='h0;i < DATA_BANKS;i=i+1) begin
            way=i/LINE_WORDS;
            word=i % LINE_WORDS;
            if (unsigned'(32'(L2CacheMemory___evict_candidate_comb.way)) == way) begin
                L2CacheMemory___evict_candidate_comb.line[word*'h20 +:32] = L2CacheState___data_q_reg[i];
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

    always_comb begin : L2CacheRequest___slave_request_novelty_comb_func  // L2CacheRequest___slave_request_novelty_comb_func
        logic[31:0] index;
        L2CacheRequest___slave_request_novelty_comb = 0;
        for (index='h0;index < MEM_PORTS;index=index+1) begin
            L2CacheRequest___slave_request_novelty_comb.aw[index] = (!L2CacheState___slave_aw_seen_reg[index].valid || (L2CacheState___slave_aw_seen_reg[index].addr != axi_in__awaddr_in[index])) || (L2CacheState___slave_aw_seen_reg[index].id != axi_in__awid_in[index]);
            L2CacheRequest___slave_request_novelty_comb.ar[index] = (!L2CacheState___slave_ar_seen_reg[index].valid || (L2CacheState___slave_ar_seen_reg[index].addr != axi_in__araddr_in[index])) || (L2CacheState___slave_ar_seen_reg[index].id != axi_in__arid_in[index]);
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

    task _work_clk (input logic reset);
    begin: _work_clk
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin

        _work_clk(reset);

    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
