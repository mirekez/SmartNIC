`default_nettype none

import Predef_pkg::*;


module OutputMerger #(
    parameter LANE_WIDTH = 'h40
,   parameter FIFO_WORDS = 'h800
,   parameter MIN_IPG_BYTES = 'hC
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire[2-1:0] tx_valid_in
,   input wire[STREAMS*LANE_WIDTH-1:0] tx_data_in
,   input wire[STREAMS*LANE_BYTES-1:0] tx_keep_in
,   input wire[2-1:0] tx_sop_in
,   input wire[2-1:0] tx_eop_in
,   output wire[2-1:0] tx_ready_out
,   output wire[2-1:0] tx_almost_full_out
,   output wire[2-1:0] tx_protocol_error_out
,   output wire valid_out
,   output wire[OUTPUT_BITS-1:0] data_out
,   output wire[OUTPUT_BYTES-1:0] keep_out
,   output wire[OUTPUT_BYTES-1:0] sop_out
,   output wire[OUTPUT_BYTES-1:0] eop_out
,   input wire ready_in
,   output wire protocol_error_out
);
    localparam  STREAMS = 64'h2;
    localparam  WINDOW_WORDS = 64'h2;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  OUTPUT_BITS = STREAMS*LANE_WIDTH;
    localparam  OUTPUT_BYTES = STREAMS*LANE_BYTES;
    localparam  GAP_BITS = $clog2(MIN_IPG_BYTES + 'h1);
    localparam  FIFO_DATA_BITS = (STREAMS*WINDOW_WORDS)*LANE_WIDTH;
    localparam  FIFO_KEEP_BITS = (STREAMS*WINDOW_WORDS)*LANE_BYTES;
    localparam  RESULT_DATA = 64'h0;
    localparam  RESULT_KEEP = RESULT_DATA + OUTPUT_BITS;
    localparam  RESULT_SOP = RESULT_KEEP + OUTPUT_BYTES;
    localparam  RESULT_EOP = RESULT_SOP + OUTPUT_BYTES;
    localparam  RESULT_VALID = RESULT_EOP + OUTPUT_BYTES;
    localparam  RESULT_NEXT_RR = RESULT_VALID + 'h1;
    localparam  RESULT_NEXT_ACTIVE = RESULT_NEXT_RR + 'h1;
    localparam  RESULT_NEXT_STREAM = RESULT_NEXT_ACTIVE + 'h1;
    localparam  RESULT_NEXT_GAP = RESULT_NEXT_STREAM + 'h1;
    localparam  RESULT_NEXT_CARRY_VALID = RESULT_NEXT_GAP + GAP_BITS;
    localparam  RESULT_NEXT_CARRY_DATA = RESULT_NEXT_CARRY_VALID + 'h1;
    localparam  RESULT_NEXT_CARRY_KEEP = RESULT_NEXT_CARRY_DATA + LANE_WIDTH;
    localparam  RESULT_NEXT_CARRY_SOP = RESULT_NEXT_CARRY_KEEP + LANE_BYTES;
    localparam  RESULT_NEXT_CARRY_EOP = RESULT_NEXT_CARRY_SOP + 'h1;
    localparam  RESULT_ERROR = RESULT_NEXT_CARRY_EOP + 'h1;
    localparam  RESULT_BITS = RESULT_ERROR + 'h1;
    localparam  MAX_LANE_WIDTH = 64'h40;
    localparam  MAX_LANE_BYTES = 64'h8;
    localparam  FIFO_FLAG_BITS = 64'h4;
    localparam  MAX_FIFO_DATA_BITS = 64'h100;
    localparam  MAX_FIFO_KEEP_BITS = 64'h20;
    localparam  READ_COUNT_BITS = 64'h8;


    // regs and combs
    reg rr_reg;
    reg active_reg;
    reg stream_reg;
    reg[GAP_BITS-1:0] gap_reg;
    reg carry_valid_reg;
    reg[LANE_WIDTH-1:0] carry_data_reg;
    reg[LANE_BYTES-1:0] carry_keep_reg;
    reg carry_sop_reg;
    reg carry_eop_reg;
    reg protocol_error_reg;
    logic[2-1:0] tx_ready_comb;
    logic[2-1:0] tx_almost_full_comb;
    logic[2-1:0] tx_fifo_error_comb;
    logic[8-1:0] merge_read_counts_comb;
    logic[LANE_WIDTH-1:0] tx_data_0_comb;
    logic[LANE_BYTES-1:0] tx_keep_0_comb;
    logic[LANE_WIDTH-1:0] tx_data_1_comb;
    logic[LANE_BYTES-1:0] tx_keep_1_comb;
    logic[FIFO_DATA_BITS-1:0] fifo_data_comb;
;
    logic[FIFO_KEEP_BITS-1:0] fifo_keep_comb;
;
    logic[4-1:0] fifo_sop_comb;
;
    logic[4-1:0] fifo_eop_comb;
;
    logic[4-1:0] fifo_valid_comb;
;
    logic[RESULT_BITS-1:0] merge_result_comb;
;
    logic[OUTPUT_BITS-1:0] output_data_comb;
    logic[OUTPUT_BYTES-1:0] output_keep_comb;
    logic[OUTPUT_BYTES-1:0] output_sop_comb;
    logic[OUTPUT_BYTES-1:0] output_eop_comb;
    logic output_valid_comb;
    logic[4-1:0] read_count_0_comb;
    logic[4-1:0] read_count_1_comb;
    logic error_comb;

    // members
    genvar __i;
    wire fifos__valid_in[2];
    wire[LANE_WIDTH-1:0] fifos__data_in[2];
    wire[LANE_WIDTH/'h8-1:0] fifos__keep_in[2];
    wire fifos__sop_in[2];
    wire fifos__eop_in[2];
    wire fifos__ready_out[2];
    wire[64'h2*LANE_WIDTH-1:0] fifos__data_out[2];
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] fifos__keep_out[2];
    wire[2-1:0] fifos__sop_out[2];
    wire[2-1:0] fifos__eop_out[2];
    wire[2-1:0] fifos__valid_out[2];
    wire[4-1:0] fifos__read_count_in[2];
    wire fifos__clear_in[2];
    wire fifos__almost_full_out[2];
    wire fifos__protocol_error_out[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        TxFifo #(
        LANE_WIDTH
,       FIFO_WORDS
        ) fifos (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(fifos__valid_in[__i])
        ,           .data_in(fifos__data_in[__i])
        ,           .keep_in(fifos__keep_in[__i])
        ,           .sop_in(fifos__sop_in[__i])
        ,           .eop_in(fifos__eop_in[__i])
        ,           .ready_out(fifos__ready_out[__i])
        ,           .data_out(fifos__data_out[__i])
        ,           .keep_out(fifos__keep_out[__i])
        ,           .sop_out(fifos__sop_out[__i])
        ,           .eop_out(fifos__eop_out[__i])
        ,           .valid_out(fifos__valid_out[__i])
        ,           .read_count_in(fifos__read_count_in[__i])
        ,           .clear_in(fifos__clear_in[__i])
        ,           .almost_full_out(fifos__almost_full_out[__i])
        ,           .protocol_error_out(fifos__protocol_error_out[__i])
        );
    end
    endgenerate

    // tmp variables
    logic rr_reg_tmp;
    logic active_reg_tmp;
    logic stream_reg_tmp;
    logic[GAP_BITS-1:0] gap_reg_tmp;
    logic carry_valid_reg_tmp;
    logic[LANE_WIDTH-1:0] carry_data_reg_tmp;
    logic[LANE_BYTES-1:0] carry_keep_reg_tmp;
    logic carry_sop_reg_tmp;
    logic carry_eop_reg_tmp;
    logic protocol_error_reg_tmp;


    always_comb begin : tx_data_0_comb_func  // tx_data_0_comb_func
        logic[63:0] _bit;
        for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
            tx_data_0_comb[_bit] = tx_data_in[('h0*LANE_WIDTH) + _bit];
        end
    end

    always_comb begin : tx_keep_0_comb_func  // tx_keep_0_comb_func
        logic[63:0] _byte;
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            tx_keep_0_comb[_byte] = tx_keep_in[('h0*LANE_BYTES) + _byte];
        end
    end

    always_comb begin : tx_data_1_comb_func  // tx_data_1_comb_func
        logic[63:0] _bit;
        for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
            tx_data_1_comb[_bit] = tx_data_in[('h1*LANE_WIDTH) + _bit];
        end
    end

    always_comb begin : tx_keep_1_comb_func  // tx_keep_1_comb_func
        logic[63:0] _byte;
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            tx_keep_1_comb[_byte] = tx_keep_in[('h1*LANE_BYTES) + _byte];
        end
    end

    always_comb begin : tx_ready_comb_func  // tx_ready_comb_func
        logic[63:0] stream;
        tx_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            tx_ready_comb[stream] = fifos__ready_out[stream];
        end
    end

    always_comb begin : tx_almost_full_comb_func  // tx_almost_full_comb_func
        logic[63:0] stream;
        tx_almost_full_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            tx_almost_full_comb[stream] = fifos__almost_full_out[stream];
        end
    end

    always_comb begin : tx_fifo_error_comb_func  // tx_fifo_error_comb_func
        logic[63:0] stream;
        tx_fifo_error_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            tx_fifo_error_comb[stream] = fifos__protocol_error_out[stream];
        end
    end

    always_comb begin : fifo_data_comb_func  // fifo_data_comb_func
        logic[63:0] stream;
        logic[63:0] _bit;
        logic[128-1:0] value;
        fifo_data_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            value = fifos__data_out[stream];
            for (_bit='h0;_bit < (WINDOW_WORDS*LANE_WIDTH);_bit=_bit+1) begin
                fifo_data_comb[((stream*WINDOW_WORDS)*LANE_WIDTH) + _bit] = value[_bit];
            end
        end
    end

    always_comb begin : fifo_keep_comb_func  // fifo_keep_comb_func
        logic[63:0] stream;
        logic[63:0] _bit;
        logic[16-1:0] value;
        fifo_keep_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            value = fifos__keep_out[stream];
            for (_bit='h0;_bit < (WINDOW_WORDS*LANE_BYTES);_bit=_bit+1) begin
                fifo_keep_comb[((stream*WINDOW_WORDS)*LANE_BYTES) + _bit] = value[_bit];
            end
        end
    end

    always_comb begin : fifo_sop_comb_func  // fifo_sop_comb_func
        logic[63:0] stream;
        logic[63:0] slot;
        logic[2-1:0] value;
        fifo_sop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            value = fifos__sop_out[stream];
            for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
                fifo_sop_comb[(stream*WINDOW_WORDS) + slot] = value[slot];
            end
        end
    end

    always_comb begin : fifo_eop_comb_func  // fifo_eop_comb_func
        logic[63:0] stream;
        logic[63:0] slot;
        logic[2-1:0] value;
        fifo_eop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            value = fifos__eop_out[stream];
            for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
                fifo_eop_comb[(stream*WINDOW_WORDS) + slot] = value[slot];
            end
        end
    end

    always_comb begin : fifo_valid_comb_func  // fifo_valid_comb_func
        logic[63:0] stream;
        logic[63:0] slot;
        logic[2-1:0] value;
        fifo_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            value = fifos__valid_out[stream];
            for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
                fifo_valid_comb[(stream*WINDOW_WORDS) + slot] = value[slot];
            end
        end
    end

    always_comb begin : merge_result_comb_func  // merge_result_comb_func
        logic[63:0] piece;
        logic[7:0] rr;
        logic[7:0] selected;
        logic[7:0] slot;
        logic[7:0] slot0;
        logic[7:0] slot1;
        logic[7:0] gap;
        logic[7:0] position;
        logic[7:0] space;
        logic[7:0] bytes;
        logic[7:0] take;
        logic[7:0] keep_mask;
        logic[63:0] data_mask;
        logic active;
        logic loaded;
        logic found;
        logic any_data;
        logic error;
        logic blocked;
        logic expect_sop;
        logic available0;
        logic available1;
        logic word_sop;
        logic word_eop;
        logic[8-1:0] read_counts;
        logic[64-1:0] word_data;
        logic[8-1:0] word_keep;
        logic[256-1:0] all_data;
        logic[32-1:0] all_keep;
        logic[4-1:0] all_sop;
        logic[4-1:0] all_eop;
        logic[4-1:0] all_valid;
        logic[128-1:0] output_data;
        logic[16-1:0] output_keep;
        logic[16-1:0] output_sop;
        logic[16-1:0] output_eop;
        merge_result_comb = 'h0;
        merge_read_counts_comb = 'h0;
        read_counts = 'h0;
        output_data = 'h0;
        output_keep = 'h0;
        output_sop = 'h0;
        output_eop = 'h0;
        all_data = fifo_data_comb;
        all_keep = fifo_keep_comb;
        all_sop = fifo_sop_comb;
        all_eop = fifo_eop_comb;
        all_valid = fifo_valid_comb;
        rr=unsigned'(8'(rr_reg));
        selected=unsigned'(8'(stream_reg));
        gap=unsigned'(8'(gap_reg));
        position='h0;
        active=active_reg;
        expect_sop=!active;
        loaded=carry_valid_reg;
        word_data = carry_data_reg;
        word_keep = carry_keep_reg;
        word_sop=carry_sop_reg;
        word_eop=carry_eop_reg;
        any_data=0;
        error=0;
        blocked=0;
        slot='h0;
        slot0='h0;
        slot1='h0;
        space='h0;
        bytes='h0;
        take='h0;
        keep_mask='h0;
        data_mask='h0;
        found=0;
        available0=0;
        available1=0;
        for (piece='h0;piece < 'h3;piece=piece+1) begin
            if (!blocked && (position < OUTPUT_BYTES)) begin
                if (gap != 'h0) begin
                    space=OUTPUT_BYTES - position;
                    take=(gap < space) ? (gap) : (space);
                    position+=take;
                    gap-=take;
                end
                if ((gap == 'h0) && (position < OUTPUT_BYTES)) begin
                    if (!active) begin
                        slot0=unsigned'(8'(unsigned'(64'(read_counts['h0 +:4]))));
                        slot1=unsigned'(8'(unsigned'(64'(read_counts['h4 +:4]))));
                        available0=(slot0 < WINDOW_WORDS) && (((slot0 == 'h0)) ? (all_valid['h0]) : (all_valid['h1]));
                        available1=(slot1 < WINDOW_WORDS) && (((slot1 == 'h0)) ? (all_valid['h2]) : (all_valid['h3]));
                        found=available0 || available1;
                        if (rr == 'h0) begin
                            selected=(available0) ? ('h0) : ('h1);
                        end
                        else begin
                            selected=(available1) ? ('h1) : ('h0);
                        end
                        if (!found) begin
                            blocked=1;
                        end
                        else begin
                            active=1;
                            expect_sop=1;
                            loaded=0;
                        end
                    end
                    if (!blocked && !loaded) begin
                        slot=(selected == 'h0) ? (unsigned'(8'(unsigned'(64'(read_counts['h0 +:4]))))) : (unsigned'(8'(unsigned'(64'(read_counts['h4 +:4])))));
                        if (slot>=WINDOW_WORDS || (((selected == 'h0)) ? ((((slot == 'h0)) ? (!all_valid['h0]) : (!all_valid['h1]))) : ((((slot == 'h0)) ? (!all_valid['h2]) : (!all_valid['h3]))))) begin
                            blocked=1;
                        end
                        else begin
                            if ((selected == 'h0) && (slot == 'h0)) begin
                                word_data = all_data['h0 +:64];
                                word_keep = all_keep['h0 +:8];
                                word_sop=all_sop['h0];
                                word_eop=all_eop['h0];
                            end
                            else begin
                                if (selected == 'h0) begin
                                    word_data = all_data['h40 +:64];
                                    word_keep = all_keep['h8 +:8];
                                    word_sop=all_sop['h1];
                                    word_eop=all_eop['h1];
                                end
                                else begin
                                    if (slot == 'h0) begin
                                        word_data = all_data['h80 +:64];
                                        word_keep = all_keep['h10 +:8];
                                        word_sop=all_sop['h2];
                                        word_eop=all_eop['h2];
                                    end
                                    else begin
                                        word_data = all_data['hC0 +:64];
                                        word_keep = all_keep['h18 +:8];
                                        word_sop=all_sop['h3];
                                        word_eop=all_eop['h3];
                                    end
                                end
                            end
                            if (selected == 'h0) begin
                                read_counts['h0 +:4] = slot + 'h1;
                            end
                            else begin
                                read_counts['h4 +:4] = slot + 'h1;
                            end
                            loaded=1;
                            if (word_sop != expect_sop) begin
                                error=1;
                            end
                            expect_sop=0;
                        end
                    end
                    if (!blocked && loaded) begin
                        bytes='h0;
                        if (word_keep['h7]) begin
                            bytes='h8;
                        end
                        else begin
                            if (word_keep['h6]) begin
                                bytes='h7;
                            end
                            else begin
                                if (word_keep['h5]) begin
                                    bytes='h6;
                                end
                                else begin
                                    if (word_keep['h4]) begin
                                        bytes='h5;
                                    end
                                    else begin
                                        if (word_keep['h3]) begin
                                            bytes='h4;
                                        end
                                        else begin
                                            if (word_keep['h2]) begin
                                                bytes='h3;
                                            end
                                            else begin
                                                if (word_keep['h1]) begin
                                                    bytes='h2;
                                                end
                                                else begin
                                                    if (word_keep['h0]) begin
                                                        bytes='h1;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if (bytes == 'h0) begin
                            error=1;
                            blocked=1;
                        end
                        else begin
                            space=OUTPUT_BYTES - position;
                            take=(bytes < space) ? (bytes) : (space);
                            data_mask=(take == LANE_BYTES) ? (~unsigned'(64'('h0))) : ((((unsigned'(64'('h1)) <<< ((take*'h8)))) - 'h1));
                            keep_mask=(('h1 <<< take)) - 'h1;
                            output_data = output_data | ((word_data & data_mask) << (position*'h8));
                            output_keep = output_keep | (keep_mask <<< position);
                            if (word_sop) begin
                                output_sop[position] = 'h1;
                            end
                            any_data=1;
                            position+=take;
                            if (take < bytes) begin
                                word_data = word_data >> (take*'h8);
                                word_keep = word_keep >> take;
                                word_sop=0;
                                loaded=1;
                            end
                            else begin
                                loaded=0;
                                if (word_eop) begin
                                    output_eop[position - 'h1] = 'h1;
                                    active=0;
                                    expect_sop=1;
                                    gap=MIN_IPG_BYTES;
                                    rr=((selected + 'h1)) & ((STREAMS - 'h1));
                                    space=OUTPUT_BYTES - position;
                                    take=(gap < space) ? (gap) : (space);
                                    position+=take;
                                    gap-=take;
                                end
                            end
                        end
                    end
                end
            end
        end
        merge_read_counts_comb = read_counts;
        merge_result_comb[RESULT_DATA +:(RESULT_DATA + OUTPUT_BITS) - 'h1 - RESULT_DATA + 1] = output_data;
        merge_result_comb[RESULT_KEEP +:(RESULT_KEEP + OUTPUT_BYTES) - 'h1 - RESULT_KEEP + 1] = output_keep;
        merge_result_comb[RESULT_SOP +:(RESULT_SOP + OUTPUT_BYTES) - 'h1 - RESULT_SOP + 1] = output_sop;
        merge_result_comb[RESULT_EOP +:(RESULT_EOP + OUTPUT_BYTES) - 'h1 - RESULT_EOP + 1] = output_eop;
        merge_result_comb[RESULT_VALID] = any_data;
        merge_result_comb[RESULT_NEXT_RR] = rr;
        merge_result_comb[RESULT_NEXT_ACTIVE] = active;
        merge_result_comb[RESULT_NEXT_STREAM] = selected;
        merge_result_comb[RESULT_NEXT_GAP +:(RESULT_NEXT_GAP + GAP_BITS) - 'h1 - RESULT_NEXT_GAP + 1] = gap;
        merge_result_comb[RESULT_NEXT_CARRY_VALID] = loaded;
        if (loaded) begin
            merge_result_comb[RESULT_NEXT_CARRY_DATA +:(RESULT_NEXT_CARRY_DATA + LANE_WIDTH) - 'h1 - RESULT_NEXT_CARRY_DATA + 1] = word_data;
            merge_result_comb[RESULT_NEXT_CARRY_KEEP +:(RESULT_NEXT_CARRY_KEEP + LANE_BYTES) - 'h1 - RESULT_NEXT_CARRY_KEEP + 1] = word_keep;
            merge_result_comb[RESULT_NEXT_CARRY_SOP] = word_sop;
            merge_result_comb[RESULT_NEXT_CARRY_EOP] = word_eop;
        end
        merge_result_comb[RESULT_ERROR] = error;
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        output_data_comb = merge_result_comb[RESULT_DATA +:(RESULT_DATA + OUTPUT_BITS) - 'h1 - RESULT_DATA + 1];
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        output_keep_comb = merge_result_comb[RESULT_KEEP +:(RESULT_KEEP + OUTPUT_BYTES) - 'h1 - RESULT_KEEP + 1];
    end

    always_comb begin : output_sop_comb_func  // output_sop_comb_func
        output_sop_comb = merge_result_comb[RESULT_SOP +:(RESULT_SOP + OUTPUT_BYTES) - 'h1 - RESULT_SOP + 1];
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        output_eop_comb = merge_result_comb[RESULT_EOP +:(RESULT_EOP + OUTPUT_BYTES) - 'h1 - RESULT_EOP + 1];
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        output_valid_comb=merge_result_comb[RESULT_VALID];
    end

    always_comb begin : read_count_0_comb_func  // read_count_0_comb_func
        read_count_0_comb = 'h0;
        if (output_valid_comb && ready_in) begin
            read_count_0_comb = ((unsigned'(32'(unsigned'(64'(merge_read_counts_comb)))) >>> (('h0*'h4)))) & 'hF;
        end
    end

    always_comb begin : read_count_1_comb_func  // read_count_1_comb_func
        read_count_1_comb = 'h0;
        if (output_valid_comb && ready_in) begin
            read_count_1_comb = ((unsigned'(32'(unsigned'(64'(merge_read_counts_comb)))) >>> (('h1*'h4)))) & 'hF;
        end
    end

    always_comb begin : error_comb_func  // error_comb_func
        error_comb=(protocol_error_reg || fifos__protocol_error_out['h0]) || fifos__protocol_error_out['h1];
    end

    generate  // _assign
        assign fifos__valid_in['h0] = tx_valid_in['h0];
        assign fifos__data_in['h0] = tx_data_0_comb;
        assign fifos__keep_in['h0] = tx_keep_0_comb;
        assign fifos__sop_in['h0] = tx_sop_in['h0];
        assign fifos__eop_in['h0] = tx_eop_in['h0];
        assign fifos__read_count_in['h0] = read_count_0_comb;
        assign fifos__clear_in['h0] = 0;
        assign fifos__valid_in['h1] = tx_valid_in['h1];
        assign fifos__data_in['h1] = tx_data_1_comb;
        assign fifos__keep_in['h1] = tx_keep_1_comb;
        assign fifos__sop_in['h1] = tx_sop_in['h1];
        assign fifos__eop_in['h1] = tx_eop_in['h1];
        assign fifos__read_count_in['h1] = read_count_1_comb;
        assign fifos__clear_in['h1] = 0;
        assign tx_ready_out = tx_ready_comb;
        assign tx_almost_full_out = tx_almost_full_comb;
        assign tx_protocol_error_out = tx_fifo_error_comb;
        assign valid_out = output_valid_comb;
        assign data_out = output_data_comb;
        assign keep_out = output_keep_comb;
        assign sop_out = output_sop_comb;
        assign eop_out = output_eop_comb;
        assign protocol_error_out = error_comb;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[63:0] stream;
        if (reset) begin
            rr_reg_tmp = '0;
            active_reg_tmp = '0;
            stream_reg_tmp = '0;
            gap_reg_tmp = '0;
            carry_valid_reg_tmp = '0;
            carry_data_reg_tmp = '0;
            carry_keep_reg_tmp = '0;
            carry_sop_reg_tmp = '0;
            carry_eop_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
            end
            disable _work_net_clk;
        end
        if (merge_result_comb[RESULT_VALID] && ready_in) begin
            rr_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_RR]));
            active_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_ACTIVE]));
            stream_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_STREAM]));
            gap_reg_tmp = merge_result_comb[RESULT_NEXT_GAP +:(RESULT_NEXT_GAP + GAP_BITS) - 'h1 - RESULT_NEXT_GAP + 1];
            carry_valid_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_CARRY_VALID]));
            carry_data_reg_tmp = merge_result_comb[RESULT_NEXT_CARRY_DATA +:(RESULT_NEXT_CARRY_DATA + LANE_WIDTH) - 'h1 - RESULT_NEXT_CARRY_DATA + 1];
            carry_keep_reg_tmp = merge_result_comb[RESULT_NEXT_CARRY_KEEP +:(RESULT_NEXT_CARRY_KEEP + LANE_BYTES) - 'h1 - RESULT_NEXT_CARRY_KEEP + 1];
            carry_sop_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_CARRY_SOP]));
            carry_eop_reg_tmp = unsigned'(1'(merge_result_comb[RESULT_NEXT_CARRY_EOP]));
            if (merge_result_comb[RESULT_ERROR]) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
        end
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
        _work_net_clk(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        rr_reg_tmp = rr_reg;
        active_reg_tmp = active_reg;
        stream_reg_tmp = stream_reg;
        gap_reg_tmp = gap_reg;
        carry_valid_reg_tmp = carry_valid_reg;
        carry_data_reg_tmp = carry_data_reg;
        carry_keep_reg_tmp = carry_keep_reg;
        carry_sop_reg_tmp = carry_sop_reg;
        carry_eop_reg_tmp = carry_eop_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        rr_reg <= rr_reg_tmp;
        active_reg <= active_reg_tmp;
        stream_reg <= stream_reg_tmp;
        gap_reg <= gap_reg_tmp;
        carry_valid_reg <= carry_valid_reg_tmp;
        carry_data_reg <= carry_data_reg_tmp;
        carry_keep_reg <= carry_keep_reg_tmp;
        carry_sop_reg <= carry_sop_reg_tmp;
        carry_eop_reg <= carry_eop_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
