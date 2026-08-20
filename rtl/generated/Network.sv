`default_nettype none

import Predef_pkg::*;
import PacketParserFields_pkg::*;
import PacketParserWord_pkg::*;
import PacketParserProgress_pkg::*;
import PacketParserPipeWord_pkg::*;
import PacketParserHeaderId_pkg::*;
import PacketParserCall_pkg::*;
import PacketParserFlags_pkg::*;
import RxRAMWritePair_pkg::*;
import RxDescriptor_pkg::*;
import RxDescriptorWord_pkg::*;
import RxDescriptorFlags_pkg::*;


module Network #(
    parameter LANE_WIDTH = 'h40
,   parameter READ_PORTS = 'h1
,   parameter BANK_DEPTH = 'h1000
,   parameter RX_FIFO_DEPTH = 'h40
,   parameter TX_FIFO_WORDS = 'h800
,   parameter ENABLE_RAW = 1
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire valid_in
,   input wire[INPUT_BITS-1:0] data_in
,   input wire[INPUT_BYTES-1:0] keep_in
,   input wire[INPUT_BYTES-1:0] sop_in
,   input wire[INPUT_BYTES-1:0] eop_in
,   input wire raw_in
,   output wire ready_out
,   output wire descriptor_valid_out
,   output wire RxDescriptorWord descriptor_data_out
,   input wire descriptor_ready_in
,   input wire[READ_PORTS-1:0] read_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] read_handle_in
,   input wire[READ_PORTS*LOGICAL_ROW_BITS-1:0] read_word_in
,   output wire[READ_PORTS-1:0] read_ready_out
,   output wire[READ_PORTS*LANE_WIDTH-1:0] read_data_out
,   output wire[READ_PORTS-1:0] read_valid_out
,   input wire[READ_PORTS-1:0] read_ready_in
,   input wire[READ_PORTS-1:0] release_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] release_handle_in
,   input wire[READ_PORTS*FRAME_LENGTH_BITS-1:0] release_length_in
,   input wire[2-1:0] tx_valid_in
,   input wire[INPUT_BITS-1:0] tx_data_in
,   input wire[INPUT_BYTES-1:0] tx_keep_in
,   input wire[2-1:0] tx_sop_in
,   input wire[2-1:0] tx_eop_in
,   output wire[2-1:0] tx_ready_out
,   output wire[2-1:0] tx_almost_full_out
,   output wire tx_valid_out
,   output wire[INPUT_BITS-1:0] tx_data_out
,   output wire[INPUT_BYTES-1:0] tx_keep_out
,   output wire[INPUT_BYTES-1:0] tx_sop_out
,   output wire[INPUT_BYTES-1:0] tx_eop_out
,   input wire tx_ready_in
,   output wire protocol_error_out
,   output wire storage_full_out
);
    localparam  STREAMS = 64'h2;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  INPUT_BITS = STREAMS*LANE_WIDTH;
    localparam  INPUT_BYTES = STREAMS*LANE_BYTES;
    localparam  LOGICAL_ROWS = BANK_DEPTH*'h2;
    localparam  LOGICAL_ROW_BITS = $clog2(LOGICAL_ROWS);
    localparam  HANDLE_BITS = LOGICAL_ROW_BITS + 'h3;
    localparam  FRAME_LENGTH_BITS = 64'hE;


    // regs and combs
    reg[512-1:0] parser_word0_reg[2];
    reg[512-1:0] parser_word1_reg[2];
    reg parser_raw_reg[2];
    reg parser_first_reg[2];
    reg parser_complete_reg[2];
    reg[32-1:0] ram_address_reg[2];
    reg[16-1:0] ram_length_reg[2];
    reg ram_complete_reg[2];
    reg protocol_error_reg;
    logic[2-1:0] balanced_ready_comb;
    logic[2-1:0] parser_valid_comb;
    logic[2-1:0] ram_valid_comb;
    logic[2-1:0] raw_mask_comb;
    logic[2-1:0] parser_ready_comb;
    logic[2-1:0] ram_completion_ready_comb;
    logic[2-1:0] descriptor_valid_comb;
    RxDescriptorWord[2-1:0] descriptor_input_comb;
    logic error_comb;

    // members
    genvar __i;
    wire balancer__valid_in;
    wire[64'h2*LANE_WIDTH-1:0] balancer__data_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__keep_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__sop_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__eop_in;
    wire balancer__ready_out;
    wire[64'h2*LANE_WIDTH-1:0] balancer__data_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__keep_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__sop_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] balancer__eop_out;
    wire[2-1:0] balancer__valid_out;
    wire[2-1:0] balancer__ready_in;
    wire balancer__protocol_error_out;
    InputBalancer #(
        LANE_WIDTH
    ) balancer (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .valid_in(balancer__valid_in)
,       .data_in(balancer__data_in)
,       .keep_in(balancer__keep_in)
,       .sop_in(balancer__sop_in)
,       .eop_in(balancer__eop_in)
,       .ready_out(balancer__ready_out)
,       .data_out(balancer__data_out)
,       .keep_out(balancer__keep_out)
,       .sop_out(balancer__sop_out)
,       .eop_out(balancer__eop_out)
,       .valid_out(balancer__valid_out)
,       .ready_in(balancer__ready_in)
,       .protocol_error_out(balancer__protocol_error_out)
    );
    wire parser__valid_in[2];
    wire[LANE_WIDTH-1:0] parser__data_in[2];
    wire[LANE_WIDTH/'h8-1:0] parser__keep_in[2];
    wire[LANE_WIDTH/'h8-1:0] parser__sop_in[2];
    wire[LANE_WIDTH/'h8-1:0] parser__eop_in[2];
    wire parser__raw_in[2];
    wire parser__ready_out[2];
    wire PacketParserWord parser__data_out[2];
    wire[64-1:0] parser__keep_out[2];
    wire parser__valid_out[2];
    wire parser__last_out[2];
    wire parser__raw_out[2];
    wire parser__ready_in[2];
    wire parser__protocol_error_out[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        PacketParser #(
        LANE_WIDTH
,       ENABLE_RAW
        ) parser (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(parser__valid_in[__i])
        ,           .data_in(parser__data_in[__i])
        ,           .keep_in(parser__keep_in[__i])
        ,           .sop_in(parser__sop_in[__i])
        ,           .eop_in(parser__eop_in[__i])
        ,           .raw_in(parser__raw_in[__i])
        ,           .ready_out(parser__ready_out[__i])
        ,           .data_out(parser__data_out[__i])
        ,           .keep_out(parser__keep_out[__i])
        ,           .valid_out(parser__valid_out[__i])
        ,           .last_out(parser__last_out[__i])
        ,           .raw_out(parser__raw_out[__i])
        ,           .ready_in(parser__ready_in[__i])
        ,           .protocol_error_out(parser__protocol_error_out[__i])
        );
    end
    endgenerate
    wire[2-1:0] rx_ram__valid_in;
    wire[64'h2*LANE_WIDTH-1:0] rx_ram__data_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] rx_ram__keep_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] rx_ram__sop_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] rx_ram__eop_in;
    wire[2-1:0] rx_ram__ready_out;
    wire[2-1:0] rx_ram__packet_valid_out;
    wire[64'h2*($clog2((BANK_DEPTH*64'h2)) + 'h3)-1:0] rx_ram__packet_handle_out;
    wire[28-1:0] rx_ram__packet_length_out;
    wire[2-1:0] rx_ram__packet_ready_in;
    wire[READ_PORTS-1:0] rx_ram__read_valid_in;
    wire[READ_PORTS*($clog2((BANK_DEPTH*64'h2)) + 'h3)-1:0] rx_ram__read_handle_in;
    wire[READ_PORTS*$clog2((BANK_DEPTH*64'h2))-1:0] rx_ram__read_word_in;
    wire[READ_PORTS-1:0] rx_ram__read_ready_out;
    wire[READ_PORTS*LANE_WIDTH-1:0] rx_ram__read_data_out;
    wire[READ_PORTS-1:0] rx_ram__read_valid_out;
    wire[READ_PORTS-1:0] rx_ram__read_ready_in;
    wire[READ_PORTS-1:0] rx_ram__release_valid_in;
    wire[READ_PORTS*($clog2((BANK_DEPTH*64'h2)) + 'h3)-1:0] rx_ram__release_handle_in;
    wire[READ_PORTS*64'hE-1:0] rx_ram__release_length_in;
    wire rx_ram__protocol_error_out;
    wire rx_ram__storage_full_out;
    RxRAM #(
        LANE_WIDTH
,       READ_PORTS
,       BANK_DEPTH
    ) rx_ram (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .valid_in(rx_ram__valid_in)
,       .data_in(rx_ram__data_in)
,       .keep_in(rx_ram__keep_in)
,       .sop_in(rx_ram__sop_in)
,       .eop_in(rx_ram__eop_in)
,       .ready_out(rx_ram__ready_out)
,       .packet_valid_out(rx_ram__packet_valid_out)
,       .packet_handle_out(rx_ram__packet_handle_out)
,       .packet_length_out(rx_ram__packet_length_out)
,       .packet_ready_in(rx_ram__packet_ready_in)
,       .read_valid_in(rx_ram__read_valid_in)
,       .read_handle_in(rx_ram__read_handle_in)
,       .read_word_in(rx_ram__read_word_in)
,       .read_ready_out(rx_ram__read_ready_out)
,       .read_data_out(rx_ram__read_data_out)
,       .read_valid_out(rx_ram__read_valid_out)
,       .read_ready_in(rx_ram__read_ready_in)
,       .release_valid_in(rx_ram__release_valid_in)
,       .release_handle_in(rx_ram__release_handle_in)
,       .release_length_in(rx_ram__release_length_in)
,       .protocol_error_out(rx_ram__protocol_error_out)
,       .storage_full_out(rx_ram__storage_full_out)
    );
    wire[2-1:0] rx_fifo__valid_in;
    wire RxDescriptorWord[2-1:0] rx_fifo__data_in;
    wire[2-1:0] rx_fifo__ready_out;
    wire[2-1:0] rx_fifo__almost_full_out;
    wire rx_fifo__valid_out;
    wire RxDescriptorWord rx_fifo__data_out;
    wire rx_fifo__ready_in;
    wire rx_fifo__clear_in;
    RxFifo #(
        RX_FIFO_DEPTH
    ) rx_fifo (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .valid_in(rx_fifo__valid_in)
,       .data_in(rx_fifo__data_in)
,       .ready_out(rx_fifo__ready_out)
,       .almost_full_out(rx_fifo__almost_full_out)
,       .valid_out(rx_fifo__valid_out)
,       .data_out(rx_fifo__data_out)
,       .ready_in(rx_fifo__ready_in)
,       .clear_in(rx_fifo__clear_in)
    );
    wire[2-1:0] output_merger__tx_valid_in;
    wire[64'h2*LANE_WIDTH-1:0] output_merger__tx_data_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] output_merger__tx_keep_in;
    wire[2-1:0] output_merger__tx_sop_in;
    wire[2-1:0] output_merger__tx_eop_in;
    wire[2-1:0] output_merger__tx_ready_out;
    wire[2-1:0] output_merger__tx_almost_full_out;
    wire[2-1:0] output_merger__tx_protocol_error_out;
    wire output_merger__valid_out;
    wire[64'h2*LANE_WIDTH-1:0] output_merger__data_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] output_merger__keep_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] output_merger__sop_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] output_merger__eop_out;
    wire output_merger__ready_in;
    wire output_merger__protocol_error_out;
    OutputMerger #(
        LANE_WIDTH
,       TX_FIFO_WORDS
,       'hC
    ) output_merger (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .tx_valid_in(output_merger__tx_valid_in)
,       .tx_data_in(output_merger__tx_data_in)
,       .tx_keep_in(output_merger__tx_keep_in)
,       .tx_sop_in(output_merger__tx_sop_in)
,       .tx_eop_in(output_merger__tx_eop_in)
,       .tx_ready_out(output_merger__tx_ready_out)
,       .tx_almost_full_out(output_merger__tx_almost_full_out)
,       .tx_protocol_error_out(output_merger__tx_protocol_error_out)
,       .valid_out(output_merger__valid_out)
,       .data_out(output_merger__data_out)
,       .keep_out(output_merger__keep_out)
,       .sop_out(output_merger__sop_out)
,       .eop_out(output_merger__eop_out)
,       .ready_in(output_merger__ready_in)
,       .protocol_error_out(output_merger__protocol_error_out)
    );

    // tmp variables
    logic[512-1:0] parser_word0_reg_tmp[2];
    logic[512-1:0] parser_word1_reg_tmp[2];
    logic parser_raw_reg_tmp[2];
    logic parser_first_reg_tmp[2];
    logic parser_complete_reg_tmp[2];
    logic[32-1:0] ram_address_reg_tmp[2];
    logic[16-1:0] ram_length_reg_tmp[2];
    logic ram_complete_reg_tmp[2];
    logic protocol_error_reg_tmp;


    always_comb begin : balanced_ready_comb_func  // balanced_ready_comb_func
        logic[31:0] stream;
        balanced_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            balanced_ready_comb[stream] = parser__ready_out[stream] && rx_ram__ready_out[stream];
        end
    end

    always_comb begin : parser_valid_comb_func  // parser_valid_comb_func
        logic[31:0] stream;
        parser_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            parser_valid_comb[stream] = balancer__valid_out[stream] && rx_ram__ready_out[stream];
        end
    end

    always_comb begin : ram_valid_comb_func  // ram_valid_comb_func
        logic[31:0] stream;
        ram_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            ram_valid_comb[stream] = balancer__valid_out[stream] && parser__ready_out[stream];
        end
    end

    always_comb begin : raw_mask_comb_func  // raw_mask_comb_func
        logic[31:0] stream;
        raw_mask_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            raw_mask_comb[stream] = ENABLE_RAW && raw_in;
        end
    end

    always_comb begin : parser_ready_comb_func  // parser_ready_comb_func
        logic[31:0] stream;
        parser_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            parser_ready_comb[stream] = !parser_complete_reg[stream];
        end
    end

    always_comb begin : ram_completion_ready_comb_func  // ram_completion_ready_comb_func
        logic[31:0] stream;
        ram_completion_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            ram_completion_ready_comb[stream] = !ram_complete_reg[stream];
        end
    end

    always_comb begin : descriptor_valid_comb_func  // descriptor_valid_comb_func
        logic[31:0] stream;
        descriptor_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            descriptor_valid_comb[stream] = parser_complete_reg[stream] && ram_complete_reg[stream];
        end
    end

    always_comb begin : descriptor_input_comb_func  // descriptor_input_comb_func
        logic[31:0] stream;
        RxDescriptorWord word;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            word.raw = 'h0;
            word.descriptor = 0;
            word.descriptor.packet_address = ram_address_reg[stream];
            word.descriptor.packet_length = ram_length_reg[stream];
            word.descriptor.ingress_stream = unsigned'(8'(stream));
            word.descriptor.flags = unsigned'(8'((parser_raw_reg[stream]) ? (RxDescriptorFlags_pkg::RX_DESCRIPTOR_FLAG_RAW) : ('h0)));
            word.descriptor.reserved = 'h0;
            word.descriptor.packet_word0.raw = parser_word0_reg[stream];
            word.descriptor.packet_word1.raw = parser_word1_reg[stream];
            descriptor_input_comb[stream] = word;
        end
    end

    always_comb begin : error_comb_func  // error_comb_func
        error_comb=((((protocol_error_reg || balancer__protocol_error_out) || parser__protocol_error_out['h0]) || parser__protocol_error_out['h1]) || rx_ram__protocol_error_out) || output_merger__protocol_error_out;
    end

    generate  // _assign
        assign balancer__valid_in = valid_in;
        assign balancer__data_in = data_in;
        assign balancer__keep_in = keep_in;
        assign balancer__sop_in = sop_in;
        assign balancer__eop_in = eop_in;
        assign balancer__ready_in = balanced_ready_comb;
        assign parser__valid_in['h0] = parser_valid_comb['h0];
        assign parser__data_in['h0] = balancer__data_out['h0*LANE_WIDTH +:(('h0*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h0*LANE_WIDTH + 1];
        assign parser__keep_in['h0] = balancer__keep_out['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__sop_in['h0] = balancer__sop_out['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__eop_in['h0] = balancer__eop_out['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__raw_in['h0] = raw_mask_comb['h0];
        assign parser__ready_in['h0] = parser_ready_comb['h0];
        assign parser__valid_in['h1] = parser_valid_comb['h1];
        assign parser__data_in['h1] = balancer__data_out['h1*LANE_WIDTH +:(('h1*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h1*LANE_WIDTH + 1];
        assign parser__keep_in['h1] = balancer__keep_out['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__sop_in['h1] = balancer__sop_out['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__eop_in['h1] = balancer__eop_out['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        assign parser__raw_in['h1] = raw_mask_comb['h1];
        assign parser__ready_in['h1] = parser_ready_comb['h1];
        assign rx_ram__valid_in = ram_valid_comb;
        assign rx_ram__data_in = balancer__data_out;
        assign rx_ram__keep_in = balancer__keep_out;
        assign rx_ram__sop_in = balancer__sop_out;
        assign rx_ram__eop_in = balancer__eop_out;
        assign rx_ram__packet_ready_in = ram_completion_ready_comb;
        assign rx_ram__read_valid_in = read_valid_in;
        assign rx_ram__read_handle_in = read_handle_in;
        assign rx_ram__read_word_in = read_word_in;
        assign rx_ram__read_ready_in = read_ready_in;
        assign rx_ram__release_valid_in = release_valid_in;
        assign rx_ram__release_handle_in = release_handle_in;
        assign rx_ram__release_length_in = release_length_in;
        assign rx_fifo__valid_in = descriptor_valid_comb;
        assign rx_fifo__data_in = descriptor_input_comb;
        assign rx_fifo__ready_in = descriptor_ready_in;
        assign rx_fifo__clear_in = 0;
        assign output_merger__tx_valid_in = tx_valid_in;
        assign output_merger__tx_data_in = tx_data_in;
        assign output_merger__tx_keep_in = tx_keep_in;
        assign output_merger__tx_sop_in = tx_sop_in;
        assign output_merger__tx_eop_in = tx_eop_in;
        assign output_merger__ready_in = tx_ready_in;
        assign ready_out = balancer__ready_out;
        assign descriptor_valid_out = rx_fifo__valid_out;
        assign descriptor_data_out = rx_fifo__data_out;
        assign read_ready_out = rx_ram__read_ready_out;
        assign read_data_out = rx_ram__read_data_out;
        assign read_valid_out = rx_ram__read_valid_out;
        assign tx_ready_out = output_merger__tx_ready_out;
        assign tx_almost_full_out = output_merger__tx_almost_full_out;
        assign tx_valid_out = output_merger__valid_out;
        assign tx_data_out = output_merger__data_out;
        assign tx_keep_out = output_merger__keep_out;
        assign tx_sop_out = output_merger__sop_out;
        assign tx_eop_out = output_merger__eop_out;
        assign protocol_error_out = error_comb;
        assign storage_full_out = rx_ram__storage_full_out;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[31:0] stream;
        logic[31:0] _bit;
        logic[31:0] address;
        logic[31:0] length;
        logic parser_fire;
        logic parser_raw;
        logic parser_last;
        logic fifo_fire;
        PacketParserWord parser_word;
        logic[32-1:0] handles;
        logic[28-1:0] lengths;
        if (reset) begin
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
                parser_word0_reg_tmp[stream] = '0;
                parser_word1_reg_tmp[stream] = '0;
                parser_raw_reg_tmp[stream] = '0;
                parser_first_reg_tmp[stream] = '0;
                parser_complete_reg_tmp[stream] = '0;
                ram_address_reg_tmp[stream] = '0;
                ram_length_reg_tmp[stream] = '0;
                ram_complete_reg_tmp[stream] = '0;
            end
            protocol_error_reg_tmp = '0;
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
            end
            disable _work_net_clk;
        end
        handles = rx_ram__packet_handle_out;
        lengths = rx_ram__packet_length_out;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            fifo_fire=descriptor_valid_comb[stream] && rx_fifo__ready_out[stream];
            if (fifo_fire) begin
                parser_complete_reg_tmp[stream] = unsigned'(1'h0);
                parser_first_reg_tmp[stream] = unsigned'(1'h0);
                ram_complete_reg_tmp[stream] = unsigned'(1'h0);
            end
            parser_fire=parser__valid_out[stream] && parser_ready_comb[stream];
            if (parser_fire) begin
                parser_word = parser__data_out[stream];
                parser_raw=parser__raw_out[stream];
                parser_last=parser__last_out[stream];
                if (!parser_raw) begin
                    parser_word0_reg_tmp[stream] = parser_word.raw;
                    parser_word1_reg_tmp[stream] = 'h0;
                    parser_raw_reg_tmp[stream] = unsigned'(1'h0);
                    parser_first_reg_tmp[stream] = unsigned'(1'h1);
                    parser_complete_reg_tmp[stream] = unsigned'(1'(parser_last));
                    if (!parser_last) begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
                else begin
                    if (!parser_first_reg[stream]) begin
                        parser_word0_reg_tmp[stream] = parser_word.raw;
                        parser_word1_reg_tmp[stream] = 'h0;
                        parser_raw_reg_tmp[stream] = unsigned'(1'h1);
                        parser_first_reg_tmp[stream] = unsigned'(1'h1);
                        parser_complete_reg_tmp[stream] = unsigned'(1'(parser_last));
                    end
                    else begin
                        parser_word1_reg_tmp[stream] = parser_word.raw;
                        parser_complete_reg_tmp[stream] = unsigned'(1'(parser_last));
                        if (!parser_last) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                end
            end
            if (rx_ram__packet_valid_out[stream] && ram_completion_ready_comb[stream]) begin
                address='h0;
                length='h0;
                for (_bit='h0;_bit < HANDLE_BITS;_bit=_bit+1) begin
                    address|=unsigned'(32'(handles[((stream*HANDLE_BITS) + _bit)])) <<< _bit;
                end
                for (_bit='h0;_bit < FRAME_LENGTH_BITS;_bit=_bit+1) begin
                    length|=unsigned'(32'(lengths[((stream*FRAME_LENGTH_BITS) + _bit)])) <<< _bit;
                end
                ram_address_reg_tmp[stream] = unsigned'(32'(address));
                ram_length_reg_tmp[stream] = unsigned'(16'(length));
                ram_complete_reg_tmp[stream] = unsigned'(1'h1);
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
        parser_word0_reg_tmp = parser_word0_reg;
        parser_word1_reg_tmp = parser_word1_reg;
        parser_raw_reg_tmp = parser_raw_reg;
        parser_first_reg_tmp = parser_first_reg;
        parser_complete_reg_tmp = parser_complete_reg;
        ram_address_reg_tmp = ram_address_reg;
        ram_length_reg_tmp = ram_length_reg;
        ram_complete_reg_tmp = ram_complete_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        parser_word0_reg <= parser_word0_reg_tmp;
        parser_word1_reg <= parser_word1_reg_tmp;
        parser_raw_reg <= parser_raw_reg_tmp;
        parser_first_reg <= parser_first_reg_tmp;
        parser_complete_reg <= parser_complete_reg_tmp;
        ram_address_reg <= ram_address_reg_tmp;
        ram_length_reg <= ram_length_reg_tmp;
        ram_complete_reg <= ram_complete_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
