`default_nettype none

import Predef_pkg::*;
import PacketParserFields_pkg::*;
import PacketParserWord_pkg::*;
import RxDescriptor_pkg::*;
import RxDescriptorWord_pkg::*;


module RxFifo #(
    parameter FIFO_DEPTH = 'h40
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire[2-1:0] valid_in
,   input wire RxDescriptorWord[2-1:0] data_in
,   output wire[2-1:0] ready_out
,   output wire[2-1:0] almost_full_out
,   output wire valid_out
,   output wire RxDescriptorWord data_out
,   input wire ready_in
,   input wire clear_in
);
    parameter  STREAMS = 64'h2;
    parameter  DESCRIPTOR_BYTES = 64'hA0;
    parameter  DESCRIPTOR_BITS = 64'h500;


    // regs and combs
    reg[1-1:0] rr_reg;
    logic[2-1:0] input_ready_comb;
    logic[2-1:0] almost_full_comb;
    logic[2-1:0] fifo_read_comb;
    logic[1280-1:0] input_bits_0_comb;
    logic[1280-1:0] input_bits_1_comb;
    logic output_valid_comb;
    RxDescriptorWord output_data_comb;

    // members
    genvar __i;
    wire fifos__write_in[2];
    wire[DESCRIPTOR_BYTES*'h8-1:0] fifos__write_data_in[2];
    wire fifos__read_in[2];
    wire[DESCRIPTOR_BYTES*'h8-1:0] fifos__read_data_out[2];
    wire fifos__empty_out[2];
    wire fifos__full_out[2];
    wire fifos__clear_in[2];
    wire fifos__afull_out[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        Fifo #(
        DESCRIPTOR_BYTES
,       FIFO_DEPTH
,       1
,       0
        ) fifos (
            .l2_clock(net_clk)
,           .system_clock(l2_clk)
        ,           .reset(reset)
        ,           .write_in(fifos__write_in[__i])
        ,           .write_data_in(fifos__write_data_in[__i])
        ,           .read_in(fifos__read_in[__i])
        ,           .read_data_out(fifos__read_data_out[__i])
        ,           .empty_out(fifos__empty_out[__i])
        ,           .full_out(fifos__full_out[__i])
        ,           .clear_in(fifos__clear_in[__i])
        ,           .afull_out(fifos__afull_out[__i])
        );
    end
    endgenerate

    // tmp variables
    logic[1-1:0] rr_reg_tmp;


    always_comb begin : input_bits_0_comb_func  // input_bits_0_comb_func
        RxDescriptorWord word;
        word = data_in['h0];
        input_bits_0_comb = word.raw;
    end

    always_comb begin : input_bits_1_comb_func  // input_bits_1_comb_func
        RxDescriptorWord word;
        word = data_in['h1];
        input_bits_1_comb = word.raw;
    end

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[31:0] stream;
        input_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            input_ready_comb[stream] = !fifos__full_out[stream];
        end
    end

    always_comb begin : almost_full_comb_func  // almost_full_comb_func
        logic[31:0] stream;
        almost_full_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            almost_full_comb[stream] = fifos__afull_out[stream];
        end
    end

    function logic[31:0] selected_stream_value ();
        logic[31:0] offset;
        logic[31:0] candidate;
        for (offset='h0;offset < STREAMS;offset=offset+1) begin
            candidate=((unsigned'(32'(rr_reg)) + offset)) & 'h1;
            if (!fifos__empty_out[candidate]) begin
                return candidate;
            end
        end
        return STREAMS;
    endfunction

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        output_valid_comb=selected_stream_value() < STREAMS;
    end

    always_comb begin : fifo_read_comb_func  // fifo_read_comb_func
        logic[31:0] selected;
        fifo_read_comb = 'h0;
        selected=selected_stream_value();
        if ((selected < STREAMS) && ready_in) begin
            fifo_read_comb[selected] = 'h1;
        end
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[31:0] selected;
        output_data_comb.raw = 'h0;
        selected=selected_stream_value();
        if (selected < STREAMS) begin
            output_data_comb.raw = fifos__read_data_out[selected];
        end
    end

    generate  // _assign
        assign fifos__write_in['h0] = valid_in['h0] && input_ready_comb['h0];
        assign fifos__write_data_in['h0] = input_bits_0_comb;
        assign fifos__read_in['h0] = fifo_read_comb['h0];
        assign fifos__clear_in['h0] = clear_in;
        assign fifos__write_in['h1] = valid_in['h1] && input_ready_comb['h1];
        assign fifos__write_data_in['h1] = input_bits_1_comb;
        assign fifos__read_in['h1] = fifo_read_comb['h1];
        assign fifos__clear_in['h1] = clear_in;
        assign ready_out = input_ready_comb;
        assign almost_full_out = almost_full_comb;
        assign valid_out = output_valid_comb;
        assign data_out = output_data_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] stream;
        logic[31:0] selected;
        if (reset) begin
            rr_reg_tmp = '0;
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
            end
            disable _work;
        end
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
        end
        selected=selected_stream_value();
        if ((selected < STREAMS) && ready_in) begin
            rr_reg_tmp = ((selected + 'h1)) & 'h1;
        end
    end
    endtask

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        _work(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        rr_reg_tmp = rr_reg;

        _work_net_clk(reset);

        rr_reg <= rr_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
