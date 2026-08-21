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
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  OUTPUT_BITS = STREAMS*LANE_WIDTH;
    localparam  OUTPUT_BYTES = STREAMS*LANE_BYTES;
    localparam  BATCH_BYTES = OUTPUT_BYTES;
    localparam  TIME_QUEUE_BYTES = 64'h40;
    localparam  BATCH_COUNT_BITS = $clog2(BATCH_BYTES + 'h1);
    localparam  SCHED_VALID = 64'h0;
    localparam  SCHED_SELECTED = 64'h1;
    localparam  SCHED_READ_COUNT = 64'h2;
    localparam  SCHED_DATA = 64'h4;
    localparam  SCHED_KEEP = SCHED_DATA + OUTPUT_BITS;
    localparam  SCHED_SOP = SCHED_KEEP + OUTPUT_BYTES;
    localparam  SCHED_EOP = SCHED_SOP + OUTPUT_BYTES;
    localparam  SCHED_BYTES = SCHED_EOP + OUTPUT_BYTES;
    localparam  SCHED_NEXT_RR = SCHED_BYTES + BATCH_COUNT_BITS;
    localparam  SCHED_NEXT_ACTIVE = SCHED_NEXT_RR + 'h1;
    localparam  SCHED_NEXT_STREAM = SCHED_NEXT_ACTIVE + 'h1;
    localparam  SCHED_ERROR = SCHED_NEXT_STREAM + 'h1;
    localparam  SCHED_BITS = SCHED_ERROR + 'h1;
    localparam  WINDOW_WORDS = 64'h2;
    localparam  TIME_QUEUE_BITS = 64'h200;
    localparam  TIME_COUNT_BITS = 64'h7;


    // regs and combs
    reg scheduler_rr_reg;
    reg scheduler_active_reg;
    reg scheduler_stream_reg;
    reg batch_valid_reg;
    reg[OUTPUT_BITS-1:0] batch_data_reg;
    reg[OUTPUT_BYTES-1:0] batch_keep_reg;
    reg[OUTPUT_BYTES-1:0] batch_sop_reg;
    reg[OUTPUT_BYTES-1:0] batch_eop_reg;
    reg[BATCH_COUNT_BITS-1:0] batch_bytes_reg;
    reg[512-1:0] time_data_reg;
    reg[64-1:0] time_keep_reg;
    reg[64-1:0] time_sop_reg;
    reg[64-1:0] time_eop_reg;
    reg[7-1:0] time_count_reg;
    reg protocol_error_reg;
    logic[2-1:0] tx_ready_comb;
    logic[2-1:0] tx_almost_full_comb;
    logic[2-1:0] tx_fifo_error_comb;
    logic[LANE_WIDTH-1:0] tx_data_0_comb;
    logic[LANE_BYTES-1:0] tx_keep_0_comb;
    logic[LANE_WIDTH-1:0] tx_data_1_comb;
    logic[LANE_BYTES-1:0] tx_keep_1_comb;
    logic[SCHED_BITS-1:0] scheduler_result_comb;
;
    logic output_valid_comb;
    logic output_drain_comb;
    logic queue_append_comb;
    logic batch_slot_ready_comb;
    logic[4-1:0] read_count_0_comb;
    logic[4-1:0] read_count_1_comb;
    logic[OUTPUT_BITS-1:0] output_data_comb;
    logic[OUTPUT_BYTES-1:0] output_keep_comb;
    logic[OUTPUT_BYTES-1:0] output_sop_comb;
    logic[OUTPUT_BYTES-1:0] output_eop_comb;
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
    logic scheduler_rr_reg_tmp;
    logic scheduler_active_reg_tmp;
    logic scheduler_stream_reg_tmp;
    logic batch_valid_reg_tmp;
    logic[OUTPUT_BITS-1:0] batch_data_reg_tmp;
    logic[OUTPUT_BYTES-1:0] batch_keep_reg_tmp;
    logic[OUTPUT_BYTES-1:0] batch_sop_reg_tmp;
    logic[OUTPUT_BYTES-1:0] batch_eop_reg_tmp;
    logic[BATCH_COUNT_BITS-1:0] batch_bytes_reg_tmp;
    logic[512-1:0] time_data_reg_tmp;
    logic[64-1:0] time_keep_reg_tmp;
    logic[64-1:0] time_sop_reg_tmp;
    logic[64-1:0] time_eop_reg_tmp;
    logic[7-1:0] time_count_reg_tmp;
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
        tx_ready_comb = 'h0;
        tx_ready_comb['h0] = fifos__ready_out['h0];
        tx_ready_comb['h1] = fifos__ready_out['h1];
    end

    always_comb begin : tx_almost_full_comb_func  // tx_almost_full_comb_func
        tx_almost_full_comb = 'h0;
        tx_almost_full_comb['h0] = fifos__almost_full_out['h0];
        tx_almost_full_comb['h1] = fifos__almost_full_out['h1];
    end

    always_comb begin : tx_fifo_error_comb_func  // tx_fifo_error_comb_func
        tx_fifo_error_comb = 'h0;
        tx_fifo_error_comb['h0] = fifos__protocol_error_out['h0];
        tx_fifo_error_comb['h1] = fifos__protocol_error_out['h1];
    end

    function logic[31:0] prefix_bytes (input logic[8-1:0] keep);
        logic[31:0] count;
        logic[31:0] _byte;
        count='h0;
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            if (keep[_byte]) begin
                count=count+1;
            end
        end
        return count;
    endfunction

    function logic prefix_keep_valid (input logic[8-1:0] keep);
        logic[31:0] _byte;
        logic seen_zero;
        logic malformed;
        seen_zero=0;
        malformed=0;
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            if (!keep[_byte]) begin
                seen_zero=1;
            end
            else begin
                if (seen_zero) begin
                    malformed=1;
                end
            end
        end
        return !malformed && (unsigned'(64'(keep)) != 'h0);
    endfunction

    always_comb begin : scheduler_result_comb_func  // scheduler_result_comb_func
        logic[31:0] selected;
        logic[31:0] read_count;
        logic[31:0] bytes0;
        logic[31:0] bytes1;
        logic[31:0] total_bytes;
        logic active;
        logic valid0;
        logic valid1;
        logic eop0;
        logic eop1;
        logic sop0;
        logic sop1;
        logic error;
        logic[128-1:0] words_data;
        logic[16-1:0] words_keep;
        logic[2-1:0] words_sop;
        logic[2-1:0] words_eop;
        logic[2-1:0] words_valid;
        logic[128-1:0] batch_data;
        logic[16-1:0] batch_keep;
        logic[16-1:0] batch_sop;
        logic[16-1:0] batch_eop;
        scheduler_result_comb = 'h0;
        selected=unsigned'(32'(scheduler_stream_reg));
        active=scheduler_active_reg;
        if (!active) begin
            if (scheduler_rr_reg) begin
                selected=(fifos__valid_out['h1]['h0]) ? ('h1) : ('h0);
            end
            else begin
                selected=(fifos__valid_out['h0]['h0]) ? ('h0) : ('h1);
            end
        end
        if (selected == 'h0) begin
            words_data = fifos__data_out['h0];
            words_keep = fifos__keep_out['h0];
            words_sop = fifos__sop_out['h0];
            words_eop = fifos__eop_out['h0];
            words_valid = fifos__valid_out['h0];
        end
        else begin
            words_data = fifos__data_out['h1];
            words_keep = fifos__keep_out['h1];
            words_sop = fifos__sop_out['h1];
            words_eop = fifos__eop_out['h1];
            words_valid = fifos__valid_out['h1];
        end
        valid0=words_valid['h0];
        valid1=words_valid['h1];
        eop0=words_eop['h0];
        eop1=words_eop['h1];
        sop0=words_sop['h0];
        sop1=words_sop['h1];
        read_count='h0;
        bytes0='h0;
        bytes1='h0;
        total_bytes='h0;
        error=0;
        batch_data = 'h0;
        batch_keep = 'h0;
        batch_sop = 'h0;
        batch_eop = 'h0;
        if (valid0) begin
            read_count='h1;
            bytes0=prefix_bytes(words_keep['h0 +:LANE_BYTES - 'h1 - 'h0 + 1]);
            if (!prefix_keep_valid(words_keep['h0 +:LANE_BYTES - 'h1 - 'h0 + 1])) begin
                error=1;
            end
            if (sop0 == active) begin
                error=1;
            end
            if (!eop0 && (bytes0 != LANE_BYTES)) begin
                error=1;
            end
            batch_data['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1] = words_data['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1];
            batch_keep['h0 +:LANE_BYTES - 'h1 - 'h0 + 1] = words_keep['h0 +:LANE_BYTES - 'h1 - 'h0 + 1];
            if (sop0) begin
                batch_sop['h0] = 'h1;
            end
            total_bytes=bytes0;
            if (!eop0) begin
                if (!valid1) begin
                    error=1;
                end
                else begin
                    read_count='h2;
                    bytes1=prefix_bytes(words_keep['h8 +:8]);
                    if (!prefix_keep_valid(words_keep['h8 +:8])) begin
                        error=1;
                    end
                    if (sop1) begin
                        error=1;
                    end
                    if (!eop1 && (bytes1 != LANE_BYTES)) begin
                        error=1;
                    end
                    batch_data[LANE_WIDTH +:OUTPUT_BITS - 'h1 - LANE_WIDTH + 1] = words_data['h40 +:64];
                    batch_keep[LANE_BYTES +:OUTPUT_BYTES - 'h1 - LANE_BYTES + 1] = words_keep['h8 +:8];
                    total_bytes+=bytes1;
                end
            end
            if (((eop0 || (((read_count == 'h2) && eop1)))) && (total_bytes != 'h0)) begin
                batch_eop[total_bytes - 'h1] = 'h1;
            end
            scheduler_result_comb[SCHED_VALID] = 'h1;
            scheduler_result_comb[SCHED_SELECTED] = selected;
            scheduler_result_comb[SCHED_READ_COUNT +:SCHED_READ_COUNT + 'h1 - SCHED_READ_COUNT + 1] = read_count;
            scheduler_result_comb[SCHED_DATA +:(SCHED_DATA + OUTPUT_BITS) - 'h1 - SCHED_DATA + 1] = batch_data;
            scheduler_result_comb[SCHED_KEEP +:(SCHED_KEEP + OUTPUT_BYTES) - 'h1 - SCHED_KEEP + 1] = batch_keep;
            scheduler_result_comb[SCHED_SOP +:(SCHED_SOP + OUTPUT_BYTES) - 'h1 - SCHED_SOP + 1] = batch_sop;
            scheduler_result_comb[SCHED_EOP +:(SCHED_EOP + OUTPUT_BYTES) - 'h1 - SCHED_EOP + 1] = batch_eop;
            scheduler_result_comb[SCHED_BYTES +:(SCHED_BYTES + BATCH_COUNT_BITS) - 'h1 - SCHED_BYTES + 1] = total_bytes;
            if (eop0 || (((read_count == 'h2) && eop1))) begin
                scheduler_result_comb[SCHED_NEXT_RR] = selected ^ 'h1;
                scheduler_result_comb[SCHED_NEXT_ACTIVE] = 'h0;
                scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
            end
            else begin
                scheduler_result_comb[SCHED_NEXT_RR] = scheduler_rr_reg;
                scheduler_result_comb[SCHED_NEXT_ACTIVE] = 'h1;
                scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
            end
        end
        else begin
            scheduler_result_comb[SCHED_NEXT_RR] = scheduler_rr_reg;
            scheduler_result_comb[SCHED_NEXT_ACTIVE] = active;
            scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
        end
        scheduler_result_comb[SCHED_ERROR] = error;
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        logic[31:0] count;
        count=unsigned'(32'(time_count_reg));
        output_valid_comb=(count != 'h0) && ((count>=OUTPUT_BYTES || ((!batch_valid_reg && !scheduler_active_reg))));
    end

    always_comb begin : output_drain_comb_func  // output_drain_comb_func
        output_drain_comb=output_valid_comb && ready_in;
    end

    function logic[31:0] queue_count_after_drain ();
        logic[31:0] count;
        count=unsigned'(32'(time_count_reg));
        if (output_drain_comb) begin
            count=(count > OUTPUT_BYTES) ? (count - OUTPUT_BYTES) : ('h0);
        end
        return count;
    endfunction

    always_comb begin : queue_append_comb_func  // queue_append_comb_func
        logic[31:0] span;
        span=unsigned'(32'(batch_bytes_reg));
        if (unsigned'(64'(batch_eop_reg)) != 'h0) begin
            span+=MIN_IPG_BYTES;
        end
        queue_append_comb=batch_valid_reg && (queue_count_after_drain() + span)<=TIME_QUEUE_BYTES;
    end

    always_comb begin : batch_slot_ready_comb_func  // batch_slot_ready_comb_func
        batch_slot_ready_comb=!batch_valid_reg || queue_append_comb;
    end

    always_comb begin : read_count_0_comb_func  // read_count_0_comb_func
        read_count_0_comb = 'h0;
        if ((batch_slot_ready_comb && scheduler_result_comb[SCHED_VALID]) && ((scheduler_result_comb[SCHED_SELECTED] == (('h0 != 'h0))))) begin
            read_count_0_comb = scheduler_result_comb[SCHED_READ_COUNT +:SCHED_READ_COUNT + 'h1 - SCHED_READ_COUNT + 1];
        end
    end

    always_comb begin : read_count_1_comb_func  // read_count_1_comb_func
        read_count_1_comb = 'h0;
        if ((batch_slot_ready_comb && scheduler_result_comb[SCHED_VALID]) && ((scheduler_result_comb[SCHED_SELECTED] == (('h1 != 'h0))))) begin
            read_count_1_comb = scheduler_result_comb[SCHED_READ_COUNT +:SCHED_READ_COUNT + 'h1 - SCHED_READ_COUNT + 1];
        end
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        output_data_comb = time_data_reg['h0 +:OUTPUT_BITS - 'h1 - 'h0 + 1];
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        output_keep_comb = time_keep_reg['h0 +:OUTPUT_BYTES - 'h1 - 'h0 + 1];
    end

    always_comb begin : output_sop_comb_func  // output_sop_comb_func
        output_sop_comb = time_sop_reg['h0 +:OUTPUT_BYTES - 'h1 - 'h0 + 1];
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        output_eop_comb = time_eop_reg['h0 +:OUTPUT_BYTES - 'h1 - 'h0 + 1];
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
        logic[31:0] count;
        logic[31:0] append_position;
        logic[31:0] append_span;
        logic[512-1:0] queue_data;
        logic[64-1:0] queue_keep;
        logic[64-1:0] queue_sop;
        logic[64-1:0] queue_eop;
        logic[189-1:0] candidate;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
        end
        if (reset) begin
            scheduler_rr_reg_tmp = '0;
            scheduler_active_reg_tmp = '0;
            scheduler_stream_reg_tmp = '0;
            batch_valid_reg_tmp = '0;
            batch_data_reg_tmp = '0;
            batch_keep_reg_tmp = '0;
            batch_sop_reg_tmp = '0;
            batch_eop_reg_tmp = '0;
            batch_bytes_reg_tmp = '0;
            time_data_reg_tmp = '0;
            time_keep_reg_tmp = '0;
            time_sop_reg_tmp = '0;
            time_eop_reg_tmp = '0;
            time_count_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            disable _work_net_clk;
        end
        queue_data = time_data_reg;
        queue_keep = time_keep_reg;
        queue_sop = time_sop_reg;
        queue_eop = time_eop_reg;
        count=unsigned'(32'(time_count_reg));
        if (output_drain_comb) begin
            queue_data = queue_data >> OUTPUT_BITS;
            queue_keep = queue_keep >> OUTPUT_BYTES;
            queue_sop = queue_sop >> OUTPUT_BYTES;
            queue_eop = queue_eop >> OUTPUT_BYTES;
            count=(count > OUTPUT_BYTES) ? (count - OUTPUT_BYTES) : ('h0);
        end
        if (queue_append_comb) begin
            append_position=count;
            append_span=unsigned'(32'(batch_bytes_reg));
            queue_data = queue_data | (batch_data_reg << (append_position*'h8));
            queue_keep = queue_keep | (batch_keep_reg << append_position);
            queue_sop = queue_sop | (batch_sop_reg << append_position);
            queue_eop = queue_eop | (batch_eop_reg << append_position);
            if (unsigned'(64'(batch_eop_reg)) != 'h0) begin
                append_span+=MIN_IPG_BYTES;
            end
            count+=append_span;
        end
        time_data_reg_tmp = queue_data;
        time_keep_reg_tmp = queue_keep;
        time_sop_reg_tmp = queue_sop;
        time_eop_reg_tmp = queue_eop;
        time_count_reg_tmp = count;
        if (batch_slot_ready_comb) begin
            candidate = scheduler_result_comb;
            if (candidate[SCHED_VALID]) begin
                batch_valid_reg_tmp = unsigned'(1'h1);
                batch_data_reg_tmp = candidate[SCHED_DATA +:(SCHED_DATA + OUTPUT_BITS) - 'h1 - SCHED_DATA + 1];
                batch_keep_reg_tmp = candidate[SCHED_KEEP +:(SCHED_KEEP + OUTPUT_BYTES) - 'h1 - SCHED_KEEP + 1];
                batch_sop_reg_tmp = candidate[SCHED_SOP +:(SCHED_SOP + OUTPUT_BYTES) - 'h1 - SCHED_SOP + 1];
                batch_eop_reg_tmp = candidate[SCHED_EOP +:(SCHED_EOP + OUTPUT_BYTES) - 'h1 - SCHED_EOP + 1];
                batch_bytes_reg_tmp = candidate[SCHED_BYTES +:(SCHED_BYTES + BATCH_COUNT_BITS) - 'h1 - SCHED_BYTES + 1];
                scheduler_rr_reg_tmp = unsigned'(1'(candidate[SCHED_NEXT_RR]));
                scheduler_active_reg_tmp = unsigned'(1'(candidate[SCHED_NEXT_ACTIVE]));
                scheduler_stream_reg_tmp = unsigned'(1'(candidate[SCHED_NEXT_STREAM]));
                if (candidate[SCHED_ERROR]) begin
                    protocol_error_reg_tmp = unsigned'(1'h1);
                end
            end
            else begin
                batch_valid_reg_tmp = unsigned'(1'h0);
            end
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
        scheduler_rr_reg_tmp = scheduler_rr_reg;
        scheduler_active_reg_tmp = scheduler_active_reg;
        scheduler_stream_reg_tmp = scheduler_stream_reg;
        batch_valid_reg_tmp = batch_valid_reg;
        batch_data_reg_tmp = batch_data_reg;
        batch_keep_reg_tmp = batch_keep_reg;
        batch_sop_reg_tmp = batch_sop_reg;
        batch_eop_reg_tmp = batch_eop_reg;
        batch_bytes_reg_tmp = batch_bytes_reg;
        time_data_reg_tmp = time_data_reg;
        time_keep_reg_tmp = time_keep_reg;
        time_sop_reg_tmp = time_sop_reg;
        time_eop_reg_tmp = time_eop_reg;
        time_count_reg_tmp = time_count_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        scheduler_rr_reg <= scheduler_rr_reg_tmp;
        scheduler_active_reg <= scheduler_active_reg_tmp;
        scheduler_stream_reg <= scheduler_stream_reg_tmp;
        batch_valid_reg <= batch_valid_reg_tmp;
        batch_data_reg <= batch_data_reg_tmp;
        batch_keep_reg <= batch_keep_reg_tmp;
        batch_sop_reg <= batch_sop_reg_tmp;
        batch_eop_reg <= batch_eop_reg_tmp;
        batch_bytes_reg <= batch_bytes_reg_tmp;
        time_data_reg <= time_data_reg_tmp;
        time_keep_reg <= time_keep_reg_tmp;
        time_sop_reg <= time_sop_reg_tmp;
        time_eop_reg <= time_eop_reg_tmp;
        time_count_reg <= time_count_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
