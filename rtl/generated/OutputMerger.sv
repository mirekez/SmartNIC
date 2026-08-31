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
,   input wire[2-1:0] ready_in
,   output wire protocol_error_out
);
    localparam  STREAMS = 64'h2;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  OUTPUT_BITS = STREAMS*LANE_WIDTH;
    localparam  OUTPUT_BYTES = STREAMS*LANE_BYTES;
    localparam  IPG_CYCLES = (((MIN_IPG_BYTES + LANE_BYTES) - 'h1))/LANE_BYTES;
    localparam  IPG_COUNT_BITS = (IPG_CYCLES == 'h0) ? ('h1) : ($clog2(IPG_CYCLES + 'h1));


    // regs and combs
    reg[IPG_COUNT_BITS-1:0] ipg_cycles_reg[2];
    logic[LANE_WIDTH-1:0] tx_data_0_comb;
    logic[LANE_BYTES-1:0] tx_keep_0_comb;
    logic[LANE_WIDTH-1:0] tx_data_1_comb;
    logic[LANE_BYTES-1:0] tx_keep_1_comb;
    logic[2-1:0] lane_valid_comb;
;
    logic output_valid_comb;
    logic[OUTPUT_BITS-1:0] output_data_comb;
    logic[OUTPUT_BYTES-1:0] output_keep_comb;
    logic[OUTPUT_BYTES-1:0] output_sop_comb;
    logic[OUTPUT_BYTES-1:0] output_eop_comb;
    logic[2-1:0] tx_ready_comb;
    logic[2-1:0] tx_almost_full_comb;
    logic[2-1:0] tx_fifo_error_comb;
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
    logic[IPG_COUNT_BITS-1:0] ipg_cycles_reg_tmp[2];


    always_comb begin : tx_data_0_comb_func  // tx_data_0_comb_func
        tx_data_0_comb = tx_data_in['h0*LANE_WIDTH +:(('h0*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h0*LANE_WIDTH + 1];
    end

    always_comb begin : tx_keep_0_comb_func  // tx_keep_0_comb_func
        tx_keep_0_comb = tx_keep_in['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
    end

    always_comb begin : tx_data_1_comb_func  // tx_data_1_comb_func
        tx_data_1_comb = tx_data_in['h1*LANE_WIDTH +:(('h1*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h1*LANE_WIDTH + 1];
    end

    always_comb begin : tx_keep_1_comb_func  // tx_keep_1_comb_func
        tx_keep_1_comb = tx_keep_in['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
    end

    always_comb begin : lane_valid_comb_func  // lane_valid_comb_func
        logic[63:0] stream;
        lane_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            lane_valid_comb[stream] = (unsigned'(32'(ipg_cycles_reg[stream])) == 'h0) && fifos__valid_out[stream]['h0];
        end
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        output_valid_comb=unsigned'(64'(lane_valid_comb)) != 'h0;
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[63:0] stream;
        logic[63:0] _bit;
        output_data_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (lane_valid_comb[stream]) begin
                for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                    output_data_comb[(stream*LANE_WIDTH) + _bit] = fifos__data_out[stream][_bit];
                end
            end
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[63:0] stream;
        logic[63:0] _byte;
        output_keep_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (lane_valid_comb[stream]) begin
                for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                    output_keep_comb[(stream*LANE_BYTES) + _byte] = fifos__keep_out[stream][_byte];
                end
            end
        end
    end

    always_comb begin : output_sop_comb_func  // output_sop_comb_func
        logic[63:0] stream;
        output_sop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (lane_valid_comb[stream] && fifos__sop_out[stream]['h0]) begin
                output_sop_comb[stream*LANE_BYTES] = 'h1;
            end
        end
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        logic[63:0] stream;
        logic[63:0] _byte;
        logic[31:0] last_byte;
        output_eop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            last_byte='h0;
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                if (fifos__keep_out[stream][_byte]) begin
                    last_byte=_byte;
                end
            end
            if (lane_valid_comb[stream] && fifos__eop_out[stream]['h0]) begin
                output_eop_comb[(stream*LANE_BYTES) + last_byte] = 'h1;
            end
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

    always_comb begin : read_count_0_comb_func  // read_count_0_comb_func
        read_count_0_comb = (ready_in['h0] && lane_valid_comb['h0]) ? ('h1) : ('h0);
    end

    always_comb begin : read_count_1_comb_func  // read_count_1_comb_func
        read_count_1_comb = (ready_in['h1] && lane_valid_comb['h1]) ? ('h1) : ('h0);
    end

    always_comb begin : error_comb_func  // error_comb_func
        error_comb=unsigned'(64'(tx_fifo_error_comb)) != 'h0;
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
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (reset) begin
                ipg_cycles_reg_tmp[stream] = '0;
            end
            else begin
                if ((ready_in[stream] && lane_valid_comb[stream]) && fifos__eop_out[stream]['h0]) begin
                    ipg_cycles_reg_tmp[stream] = IPG_CYCLES;
                end
                else begin
                    if (ready_in[stream] && (unsigned'(32'(ipg_cycles_reg[stream])) != 'h0)) begin
                        ipg_cycles_reg_tmp[stream] = ipg_cycles_reg[stream] - 'h1;
                    end
                end
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
        ipg_cycles_reg_tmp = ipg_cycles_reg;

        _work_net_clk(reset);

        ipg_cycles_reg <= ipg_cycles_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
