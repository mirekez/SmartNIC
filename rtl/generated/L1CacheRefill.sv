`default_nettype none

import Predef_pkg::*;
import L1RefillLinesComb_pkg::*;
import L1RequestGeometryComb_pkg::*;
import L1InputRequestComb_pkg::*;
import L1MemDriver_pkg::*;
import L1CacheFsmState_pkg::*;
import L1CachePerf_pkg::*;
import L1RequestState_pkg::*;
import L1RefillState_pkg::*;
import L1HeldResponse_pkg::*;


module L1CacheRefill #(
    parameter TOTAL_CACHE_SIZE = 'h400
,   parameter CACHE_LINE_SIZE = 'h20
,   parameter WAYS = 'h2
,   parameter DCACHE = 'h0
,   parameter ADDR_BITS = 'h20
,   parameter PORT_BITWIDTH = 'h20
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire write_in
,   input wire[31:0] write_data_in
,   input wire[7:0] write_mask_in
,   input wire read_in
,   input wire[31:0] addr_in
,   output wire[31:0] read_data_out
,   output wire[31:0] read_addr_out
,   output wire read_valid_out
,   output wire busy_out
,   input wire stall_in
,   input wire flush_in
,   input wire invalidate_in
,   input wire invalidate_line_in
,   input wire[31:0] invalidate_addr_in
,   input wire cache_disable_in
,   output wire mem_out__read_out
,   output wire mem_out__write_out
,   output wire[31:0] mem_out__addr_out
,   output wire[31:0] mem_out__write_data_out
,   output wire[7:0] mem_out__write_mask_out
,   output wire mem_out__cache_disable_out
,   input wire[PORT_BITWIDTH-1:0] mem_out__read_data_in
,   input wire mem_out__wait_in
,   output L1CachePerf perf_out
,   input wire debugen_in
);
    parameter  LINE_WORDS = CACHE_LINE_SIZE/'h4;
    parameter  SETS = (TOTAL_CACHE_SIZE/CACHE_LINE_SIZE)/WAYS;
    parameter  SET_BITS = $clog2(SETS);
    parameter  LINE_BITS = $clog2(CACHE_LINE_SIZE);
    parameter  HALF_LINE_BITS = CACHE_LINE_SIZE*'h4;
    parameter  PORT_BYTES = PORT_BITWIDTH/'h8;
    parameter  PORT_WORDS = PORT_BITWIDTH/'h20;
    parameter  REFILL_BEATS = CACHE_LINE_SIZE/PORT_BYTES;
    parameter  TAG_BITS = (ADDR_BITS - SET_BITS) - LINE_BITS;
    parameter  WAY_BITS = (WAYS<='h1) ? ('h1) : ($clog2(WAYS));
    parameter  WORD_BITS = $clog2(LINE_WORDS);
    parameter  REFILL_BEAT_BITS = (REFILL_BEATS<='h1) ? ('h1) : ($clog2(REFILL_BEATS));


    // regs and combs
    L1RefillLinesComb refill_lines_comb;
;
    logic[31:0] refill_data_comb;
;
    logic[31:0] direct_data_comb;
;
    L1RequestGeometryComb L1CacheRequest___request_geometry_comb;
;
    L1InputRequestComb L1CacheRequest___input_decode_comb;
;
    L1MemDriver L1CacheRequest___mem_driver_comb;
;
    reg[3-1:0] L1CacheState___state_reg;
    L1RequestState L1CacheState___req_reg;
    reg L1CacheState___tag_epoch_reg;
    reg[SETS-1:0][8-1:0] L1CacheState___tag_set_epoch_reg;
    L1RefillState L1CacheState___refill_reg;
    reg[WAY_BITS-1:0] L1CacheState___victim_reg;
    reg[SET_BITS-1:0] L1CacheState___init_set_reg;
    L1HeldResponse L1CacheState___response_reg;

    // members
    genvar __i;
    wire[$clog2(SETS)-1:0] L1CacheState___even_ram__addr_in[WAYS];
    wire[HALF_LINE_BITS-1:0] L1CacheState___even_ram__data_in[WAYS];
    wire L1CacheState___even_ram__wr_in[WAYS];
    wire L1CacheState___even_ram__rd_in[WAYS];
    wire[HALF_LINE_BITS-1:0] L1CacheState___even_ram__q_out[WAYS];
    wire signed[31:0] L1CacheState___even_ram__id_in[WAYS];
    generate
    for (__i=0; __i < WAYS; __i = __i + 1) begin
        RAM #(
        HALF_LINE_BITS
,       SETS
        ) L1CacheState___even_ram (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .addr_in(L1CacheState___even_ram__addr_in[__i])
        ,           .data_in(L1CacheState___even_ram__data_in[__i])
        ,           .wr_in(L1CacheState___even_ram__wr_in[__i])
        ,           .rd_in(L1CacheState___even_ram__rd_in[__i])
        ,           .q_out(L1CacheState___even_ram__q_out[__i])
        ,           .id_in(L1CacheState___even_ram__id_in[__i])
        );
    end
    endgenerate
    wire[$clog2(SETS)-1:0] L1CacheState___odd_ram__addr_in[WAYS];
    wire[HALF_LINE_BITS-1:0] L1CacheState___odd_ram__data_in[WAYS];
    wire L1CacheState___odd_ram__wr_in[WAYS];
    wire L1CacheState___odd_ram__rd_in[WAYS];
    wire[HALF_LINE_BITS-1:0] L1CacheState___odd_ram__q_out[WAYS];
    wire signed[31:0] L1CacheState___odd_ram__id_in[WAYS];
    generate
    for (__i=0; __i < WAYS; __i = __i + 1) begin
        RAM #(
        HALF_LINE_BITS
,       SETS
        ) L1CacheState___odd_ram (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .addr_in(L1CacheState___odd_ram__addr_in[__i])
        ,           .data_in(L1CacheState___odd_ram__data_in[__i])
        ,           .wr_in(L1CacheState___odd_ram__wr_in[__i])
        ,           .rd_in(L1CacheState___odd_ram__rd_in[__i])
        ,           .q_out(L1CacheState___odd_ram__q_out[__i])
        ,           .id_in(L1CacheState___odd_ram__id_in[__i])
        );
    end
    endgenerate
    wire[$clog2(SETS)-1:0] L1CacheState___tag_ram__addr_in[WAYS];
    wire[TAG_BITS + 'hA-1:0] L1CacheState___tag_ram__data_in[WAYS];
    wire L1CacheState___tag_ram__wr_in[WAYS];
    wire L1CacheState___tag_ram__rd_in[WAYS];
    wire[TAG_BITS + 'hA-1:0] L1CacheState___tag_ram__q_out[WAYS];
    wire signed[31:0] L1CacheState___tag_ram__id_in[WAYS];
    generate
    for (__i=0; __i < WAYS; __i = __i + 1) begin
        RAM #(
        TAG_BITS + 'hA
,       SETS
        ) L1CacheState___tag_ram (
            .clk(clk)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .addr_in(L1CacheState___tag_ram__addr_in[__i])
        ,           .data_in(L1CacheState___tag_ram__data_in[__i])
        ,           .wr_in(L1CacheState___tag_ram__wr_in[__i])
        ,           .rd_in(L1CacheState___tag_ram__rd_in[__i])
        ,           .q_out(L1CacheState___tag_ram__q_out[__i])
        ,           .id_in(L1CacheState___tag_ram__id_in[__i])
        );
    end
    endgenerate

    // tmp variables
    logic[3-1:0] L1CacheState___state_reg_tmp;
    L1RequestState L1CacheState___req_reg_tmp;
    logic L1CacheState___tag_epoch_reg_tmp;
    logic[SETS-1:0][8-1:0] L1CacheState___tag_set_epoch_reg_tmp;
    L1RefillState L1CacheState___refill_reg_tmp;
    logic[WAY_BITS-1:0] L1CacheState___victim_reg_tmp;
    logic[SET_BITS-1:0] L1CacheState___init_set_reg_tmp;
    L1HeldResponse L1CacheState___response_reg_tmp;


    always_comb begin : refill_lines_comb_func  // refill_lines_comb_func
        logic[63:0] i;
        logic[31:0] word;
        refill_lines_comb = 0;
        refill_lines_comb.even = L1CacheState___refill_reg.even_line;
        refill_lines_comb.odd = L1CacheState___refill_reg.odd_line;
        for (i='h0;i < PORT_WORDS;i=i+1) begin
            word=(unsigned'(32'(L1CacheState___refill_reg.beat))*PORT_WORDS) + i;
            refill_lines_comb.even[word*'h10 +:16] = unsigned'(32'(mem_out__read_data_in[i*'h20 +:16]));
            refill_lines_comb.odd[word*'h10 +:16] = unsigned'(32'(mem_out__read_data_in[(i*'h20) + 'h10 +:16]));
        end
    end

    function logic[31:0] assemble_line_word (
        input logic[128-1:0] even_line
,       input logic[128-1:0] odd_line
,       input logic[31:0] word
,       input logic[31:0] byte_offset
    );
        logic[31:0] word_data;
        logic[31:0] next_word_data;
        logic[31:0] even_half;
        logic[31:0] odd_half;
        even_half=unsigned'(32'(even_line[word*'h10 +:16]));
        odd_half=unsigned'(32'(odd_line[word*'h10 +:16]));
        word_data=even_half | ((odd_half <<< 'h10));
        next_word_data='h0;
        if ((byte_offset != 'h0) && ((word + 'h1) < LINE_WORDS)) begin
            even_half=unsigned'(32'(even_line[((word + 'h1))*'h10 +:16]));
            odd_half=unsigned'(32'(odd_line[((word + 'h1))*'h10 +:16]));
            next_word_data=even_half | ((odd_half <<< 'h10));
        end
        return (byte_offset == 'h0) ? (word_data) : (((word_data >>> ((byte_offset*'h8)))) | ((next_word_data <<< (('h20 - (byte_offset*'h8))))));
    endfunction

    always_comb begin : L1CacheRequest___request_geometry_comb_func  // L1CacheRequest___request_geometry_comb_func
        L1CacheRequest___request_geometry_comb = 0;
        L1CacheRequest___request_geometry_comb.set = unsigned'(32'(((unsigned'(32'(L1CacheState___req_reg.addr))/CACHE_LINE_SIZE)) % SETS));
        L1CacheRequest___request_geometry_comb.tag = unsigned'(32'(unsigned'(32'(L1CacheState___req_reg.addr))/((CACHE_LINE_SIZE*SETS))));
        L1CacheRequest___request_geometry_comb.word = unsigned'(32'(((unsigned'(32'(L1CacheState___req_reg.addr)) >>> 'h2)) & ((LINE_WORDS - 'h1))));
        L1CacheRequest___request_geometry_comb.refill_beat = unsigned'(32'(((unsigned'(32'(L1CacheState___req_reg.addr)) & ((CACHE_LINE_SIZE - 'h1))))/PORT_BYTES));
        L1CacheRequest___request_geometry_comb.direct_cross_beat = unsigned'(1'((!L1CacheState___req_reg.cache_disable && ((((unsigned'(32'(L1CacheState___req_reg.addr)) & 'h3)) != 'h0))) && (((((unsigned'(32'(L1CacheState___req_reg.addr)) % PORT_BYTES))/'h4)) + 'h1)>=PORT_WORDS));
    end

    always_comb begin : refill_data_comb_func  // refill_data_comb_func
        refill_data_comb=assemble_line_word(refill_lines_comb.even, refill_lines_comb.odd, unsigned'(32'(L1CacheRequest___request_geometry_comb.word)), unsigned'(32'(L1CacheState___req_reg.addr)) & 'h3);
    end

    always_comb begin : direct_data_comb_func  // direct_data_comb_func
        logic[31:0] _byte;
        logic[31:0] word;
        _byte=unsigned'(32'(L1CacheState___req_reg.addr)) & 'h3;
        word=((unsigned'(32'(L1CacheState___req_reg.addr)) % PORT_BYTES))/'h4;
        if (!L1CacheState___req_reg.cacheable && L1CacheRequest___request_geometry_comb.direct_cross_beat) begin
            direct_data_comb=unsigned'(32'(mem_out__read_data_in['h0 +:32]));
        end
        else begin
            direct_data_comb=unsigned'(32'(mem_out__read_data_in[(word*'h20) +:32])) >>> ((_byte*'h8));
            if ((_byte != 'h0) && ((word + 'h1) < PORT_WORDS)) begin
                direct_data_comb|=unsigned'(32'(mem_out__read_data_in[(((word + 'h1))*'h20) +:32])) <<< (('h20 - (_byte*'h8)));
            end
            else begin
                if (_byte != 'h0) begin
                    direct_data_comb|=unsigned'(32'(mem_out__read_data_in['h0 +:32])) <<< (('h20 - (_byte*'h8)));
                end
            end
        end
    end

    always_comb begin : L1CacheRequest___input_decode_comb_func  // L1CacheRequest___input_decode_comb_func
        L1CacheRequest___input_decode_comb = 0;
        L1CacheRequest___input_decode_comb.set = unsigned'(32'(((addr_in/CACHE_LINE_SIZE)) % SETS));
        L1CacheRequest___input_decode_comb.cacheable = unsigned'(1'(!cache_disable_in && !((addr_in & 'h1))));
        if (((DCACHE != 'h0) && (((addr_in & 'h3)) != 'h0)) && ((((((addr_in >>> 'h2)) & ((LINE_WORDS - 'h1)))) == (LINE_WORDS - 'h1)))) begin
            L1CacheRequest___input_decode_comb.cacheable = unsigned'(1'(0));
        end
        if (((DCACHE == 'h0) && (((addr_in & 'h2)) != 'h0)) && ((((((addr_in >>> 'h2)) & ((LINE_WORDS - 'h1)))) == (LINE_WORDS - 'h1)))) begin
            L1CacheRequest___input_decode_comb.cacheable = unsigned'(1'(0));
        end
    end

    always_comb begin : L1CacheRequest___mem_driver_comb_func  // L1CacheRequest___mem_driver_comb_func
        L1CacheRequest___mem_driver_comb = 0;
        L1CacheRequest___mem_driver_comb.write = unsigned'(1'(write_in));
        L1CacheRequest___mem_driver_comb.write_data = unsigned'(32'(write_data_in));
        L1CacheRequest___mem_driver_comb.write_mask = unsigned'(8'(write_mask_in));
        L1CacheRequest___mem_driver_comb.cache_disable = unsigned'(1'((write_in) ? (cache_disable_in) : (L1CacheState___req_reg.cache_disable)));
        L1CacheRequest___mem_driver_comb.read = unsigned'(1'((L1CacheState___state_reg == L1CacheFsmState_pkg::L1_ST_REFILL) && L1CacheState___req_reg.read));
        if (((L1CacheState___state_reg == L1CacheFsmState_pkg::L1_ST_REFILL) && L1CacheState___req_reg.read) && L1CacheState___req_reg.cacheable) begin
            L1CacheRequest___mem_driver_comb.addr = unsigned'(32'(((unsigned'(32'(L1CacheState___req_reg.addr)) & ~unsigned'(32'(((CACHE_LINE_SIZE - 'h1)))))) + (unsigned'(32'(L1CacheState___refill_reg.beat))*PORT_BYTES)));
        end
        else begin
            if ((L1CacheState___state_reg == L1CacheFsmState_pkg::L1_ST_REFILL) && L1CacheState___req_reg.read) begin
                if ((DCACHE != 'h0) && !L1CacheState___req_reg.cache_disable) begin
                    L1CacheRequest___mem_driver_comb.addr = unsigned'(32'((L1CacheRequest___request_geometry_comb.direct_cross_beat) ? (unsigned'(32'(L1CacheState___req_reg.addr))) : ((unsigned'(32'(L1CacheState___req_reg.addr)) & ~unsigned'(32'(((PORT_BYTES - 'h1))))))));
                end
                else begin
                    L1CacheRequest___mem_driver_comb.addr = L1CacheState___req_reg.addr;
                end
            end
            else begin
                L1CacheRequest___mem_driver_comb.addr = unsigned'(32'(addr_in));
            end
        end
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
