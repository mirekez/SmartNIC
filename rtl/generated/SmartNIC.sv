`default_nettype none

import Predef_pkg::*;


module SmartNIC #(
    parameter LANE_WIDTH = 'hA0
,   parameter BANK_DEPTH = 'h1000
,   parameter RX_FIFO_DEPTH = 'h40
,   parameter TX_FIFO_WORDS = 'h400
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire net_rx_valid_in
,   input wire[NET_BITS-1:0] net_rx_data_in
,   input wire[NET_BYTES-1:0] net_rx_keep_in
,   input wire[NET_BYTES-1:0] net_rx_sop_in
,   input wire[NET_BYTES-1:0] net_rx_eop_in
,   input wire net_rx_raw_in
,   output wire net_rx_ready_out
,   output wire net_tx_valid_out
,   output wire[NET_BITS-1:0] net_tx_data_out
,   output wire[NET_BYTES-1:0] net_tx_keep_out
,   output wire[NET_BYTES-1:0] net_tx_sop_out
,   output wire[NET_BYTES-1:0] net_tx_eop_out
,   input wire net_tx_ready_in
,   output wire l2_descriptor_valid_out
,   output wire[256-1:0] l2_descriptor_data_out
,   output wire[3-1:0] l2_descriptor_word_out
,   output wire l2_descriptor_sop_out
,   output wire l2_descriptor_eop_out
,   input wire l2_descriptor_ready_in
,   input wire[8-1:0] l2_rx_read_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] l2_rx_read_handle_in
,   input wire[112-1:0] l2_rx_read_length_in
,   output wire[8-1:0] l2_rx_read_ready_out
,   output wire[8-1:0] l2_rx_valid_out
,   output wire[2048-1:0] l2_rx_data_out
,   output wire[256-1:0] l2_rx_keep_out
,   output wire[8-1:0] l2_rx_sop_out
,   output wire[8-1:0] l2_rx_eop_out
,   input wire[8-1:0] l2_rx_ready_in
,   input wire[8-1:0] l2_tx_valid_in
,   input wire[2048-1:0] l2_tx_data_in
,   input wire[256-1:0] l2_tx_keep_in
,   input wire[8-1:0] l2_tx_sop_in
,   input wire[8-1:0] l2_tx_eop_in
,   output wire[8-1:0] l2_tx_ready_out
,   output wire protocol_error_out
,   output wire storage_full_out
);
    parameter  STREAMS = 64'h8;
    parameter  READ_PORTS = 64'h8;
    parameter  L2_WIDTH = 64'h100;
    parameter  L2_BYTES = 64'h20;
    parameter  LANE_BYTES = LANE_WIDTH/'h8;
    parameter  NET_BITS = STREAMS*LANE_WIDTH;
    parameter  NET_BYTES = STREAMS*LANE_BYTES;
    parameter  LOGICAL_ROWS = BANK_DEPTH*'h2;
    parameter  LOGICAL_ROW_BITS = $clog2(LOGICAL_ROWS);
    parameter  HANDLE_BITS = LOGICAL_ROW_BITS + 'h3;
    parameter  FRAME_LENGTH_BITS = 64'hE;
    parameter  READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    parameter  READ_META_DEPTH = 64'h8;


    // regs and combs
    reg read_active_reg[8];
    reg[HANDLE_BITS-1:0] read_handle_reg[8];
    reg[14-1:0] read_remaining_reg[8];
    reg[LOGICAL_ROW_BITS-1:0] read_word_reg[8];
    reg[6-1:0] meta_bytes_reg[8][8];
    reg meta_sop_reg[8][8];
    reg meta_eop_reg[8][8];
    reg[3-1:0] meta_head_reg[8];
    reg[3-1:0] meta_tail_reg[8];
    reg[4-1:0] meta_count_reg[8];
    reg[1280-1:0] descriptor_hold_reg;
    reg[3-1:0] descriptor_word_reg;
    reg descriptor_valid_reg;
    logic[8-1:0] network_read_valid_comb;
    logic[READ_PORTS*HANDLE_BITS-1:0] network_read_handle_comb;
    logic[READ_PORTS*LOGICAL_ROW_BITS-1:0] network_read_word_comb;
    logic[8-1:0] network_read_ready_comb;
    logic[8-1:0] network_tx_valid_comb;
    logic[NET_BITS-1:0] network_tx_data_comb;
    logic[NET_BYTES-1:0] network_tx_keep_comb;
    logic[8-1:0] network_tx_sop_comb;
    logic[8-1:0] network_tx_eop_comb;
    logic[8-1:0] l2_read_command_ready_comb;
    logic[8-1:0] l2_rx_valid_comb;
    logic[2048-1:0] l2_rx_data_comb;
    logic[256-1:0] l2_rx_keep_comb;
    logic[8-1:0] l2_rx_sop_comb;
    logic[8-1:0] l2_rx_eop_comb;
    logic[8-1:0] l2_tx_ready_comb;
    logic[256-1:0] descriptor_word_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_0_comb;
    logic read_command_pop_0_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_0_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_0_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_1_comb;
    logic read_command_pop_1_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_1_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_1_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_2_comb;
    logic read_command_pop_2_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_2_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_2_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_3_comb;
    logic read_command_pop_3_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_3_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_3_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_4_comb;
    logic read_command_pop_4_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_4_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_4_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_5_comb;
    logic read_command_pop_5_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_5_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_5_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_6_comb;
    logic read_command_pop_6_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_6_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_6_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_7_comb;
    logic read_command_pop_7_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_7_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_7_comb;

    // members
    genvar __i;
    wire network__valid_in;
    wire[64'h8*LANE_WIDTH-1:0] network__data_in;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__keep_in;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__sop_in;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__eop_in;
    wire network__raw_in;
    wire network__ready_out;
    wire network__descriptor_valid_out;
    RxDescriptorWord network__descriptor_data_out;
    wire network__descriptor_ready_in;
    wire[READ_PORTS-1:0] network__read_valid_in;
    wire[READ_PORTS*($clog2((BANK_DEPTH*'h2)) + 'h3)-1:0] network__read_handle_in;
    wire[READ_PORTS*$clog2((BANK_DEPTH*'h2))-1:0] network__read_word_in;
    wire[READ_PORTS-1:0] network__read_ready_out;
    wire[READ_PORTS*LANE_WIDTH-1:0] network__read_data_out;
    wire[READ_PORTS-1:0] network__read_valid_out;
    wire[READ_PORTS-1:0] network__read_ready_in;
    wire[8-1:0] network__tx_valid_in;
    wire[64'h8*LANE_WIDTH-1:0] network__tx_data_in;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__tx_keep_in;
    wire[8-1:0] network__tx_sop_in;
    wire[8-1:0] network__tx_eop_in;
    wire[8-1:0] network__tx_ready_out;
    wire[8-1:0] network__tx_almost_full_out;
    wire network__tx_valid_out;
    wire[64'h8*LANE_WIDTH-1:0] network__tx_data_out;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__tx_keep_out;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__tx_sop_out;
    wire[64'h8*(LANE_WIDTH/'h8)-1:0] network__tx_eop_out;
    wire network__tx_ready_in;
    wire network__protocol_error_out;
    wire network__storage_full_out;
    Network #(
        LANE_WIDTH
,       READ_PORTS
,       BANK_DEPTH
,       RX_FIFO_DEPTH
,       TX_FIFO_WORDS
    ) network (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .valid_in(network__valid_in)
,       .data_in(network__data_in)
,       .keep_in(network__keep_in)
,       .sop_in(network__sop_in)
,       .eop_in(network__eop_in)
,       .raw_in(network__raw_in)
,       .ready_out(network__ready_out)
,       .descriptor_valid_out(network__descriptor_valid_out)
,       .descriptor_data_out(network__descriptor_data_out)
,       .descriptor_ready_in(network__descriptor_ready_in)
,       .read_valid_in(network__read_valid_in)
,       .read_handle_in(network__read_handle_in)
,       .read_word_in(network__read_word_in)
,       .read_ready_out(network__read_ready_out)
,       .read_data_out(network__read_data_out)
,       .read_valid_out(network__read_valid_out)
,       .read_ready_in(network__read_ready_in)
,       .tx_valid_in(network__tx_valid_in)
,       .tx_data_in(network__tx_data_in)
,       .tx_keep_in(network__tx_keep_in)
,       .tx_sop_in(network__tx_sop_in)
,       .tx_eop_in(network__tx_eop_in)
,       .tx_ready_out(network__tx_ready_out)
,       .tx_almost_full_out(network__tx_almost_full_out)
,       .tx_valid_out(network__tx_valid_out)
,       .tx_data_out(network__tx_data_out)
,       .tx_keep_out(network__tx_keep_out)
,       .tx_sop_out(network__tx_sop_out)
,       .tx_eop_out(network__tx_eop_out)
,       .tx_ready_in(network__tx_ready_in)
,       .protocol_error_out(network__protocol_error_out)
,       .storage_full_out(network__storage_full_out)
    );
    wire descriptor_fifo__write_valid_in;
    wire[1280-1:0] descriptor_fifo__write_data_in;
    wire descriptor_fifo__write_ready_out;
    wire descriptor_fifo__read_ready_in;
    wire descriptor_fifo__read_valid_out;
    wire[1280-1:0] descriptor_fifo__read_data_out;
    AsyncFifoNetToL2 #(
        1280
,       16
    ) descriptor_fifo (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .write_valid_in(descriptor_fifo__write_valid_in)
,       .write_data_in(descriptor_fifo__write_data_in)
,       .write_ready_out(descriptor_fifo__write_ready_out)
,       .read_ready_in(descriptor_fifo__read_ready_in)
,       .read_valid_out(descriptor_fifo__read_valid_out)
,       .read_data_out(descriptor_fifo__read_data_out)
    );
    wire read_command_fifo__write_valid_in[8];
    wire[READ_COMMAND_BITS-1:0] read_command_fifo__write_data_in[8];
    wire read_command_fifo__write_ready_out[8];
    wire read_command_fifo__read_ready_in[8];
    wire read_command_fifo__read_valid_out[8];
    wire[READ_COMMAND_BITS-1:0] read_command_fifo__read_data_out[8];
    generate
    for (__i=0; __i < 8; __i = __i + 1) begin
        AsyncFifoL2ToNet #(
        READ_COMMAND_BITS
,       'h10
        ) read_command_fifo (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .write_valid_in(read_command_fifo__write_valid_in[__i])
        ,           .write_data_in(read_command_fifo__write_data_in[__i])
        ,           .write_ready_out(read_command_fifo__write_ready_out[__i])
        ,           .read_ready_in(read_command_fifo__read_ready_in[__i])
        ,           .read_valid_out(read_command_fifo__read_valid_out[__i])
        ,           .read_data_out(read_command_fifo__read_data_out[__i])
        );
    end
    endgenerate
    wire rx_stream_cdc__valid_in[8];
    wire[LANE_WIDTH-1:0] rx_stream_cdc__data_in[8];
    wire[LANE_WIDTH/'h8-1:0] rx_stream_cdc__keep_in[8];
    wire rx_stream_cdc__sop_in[8];
    wire rx_stream_cdc__eop_in[8];
    wire rx_stream_cdc__ready_out[8];
    wire rx_stream_cdc__valid_out[8];
    wire[L2_WIDTH-1:0] rx_stream_cdc__data_out[8];
    wire[L2_WIDTH/'h8-1:0] rx_stream_cdc__keep_out[8];
    wire rx_stream_cdc__sop_out[8];
    wire rx_stream_cdc__eop_out[8];
    wire rx_stream_cdc__ready_in[8];
    generate
    for (__i=0; __i < 8; __i = __i + 1) begin
        AsyncPacketStreamNetToL2 #(
        LANE_WIDTH
,       L2_WIDTH
,       'h10
        ) rx_stream_cdc (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(rx_stream_cdc__valid_in[__i])
        ,           .data_in(rx_stream_cdc__data_in[__i])
        ,           .keep_in(rx_stream_cdc__keep_in[__i])
        ,           .sop_in(rx_stream_cdc__sop_in[__i])
        ,           .eop_in(rx_stream_cdc__eop_in[__i])
        ,           .ready_out(rx_stream_cdc__ready_out[__i])
        ,           .valid_out(rx_stream_cdc__valid_out[__i])
        ,           .data_out(rx_stream_cdc__data_out[__i])
        ,           .keep_out(rx_stream_cdc__keep_out[__i])
        ,           .sop_out(rx_stream_cdc__sop_out[__i])
        ,           .eop_out(rx_stream_cdc__eop_out[__i])
        ,           .ready_in(rx_stream_cdc__ready_in[__i])
        );
    end
    endgenerate
    wire tx_stream_cdc__valid_in[8];
    wire[L2_WIDTH-1:0] tx_stream_cdc__data_in[8];
    wire[L2_WIDTH/'h8-1:0] tx_stream_cdc__keep_in[8];
    wire tx_stream_cdc__sop_in[8];
    wire tx_stream_cdc__eop_in[8];
    wire tx_stream_cdc__ready_out[8];
    wire tx_stream_cdc__valid_out[8];
    wire[LANE_WIDTH-1:0] tx_stream_cdc__data_out[8];
    wire[LANE_WIDTH/'h8-1:0] tx_stream_cdc__keep_out[8];
    wire tx_stream_cdc__sop_out[8];
    wire tx_stream_cdc__eop_out[8];
    wire tx_stream_cdc__ready_in[8];
    generate
    for (__i=0; __i < 8; __i = __i + 1) begin
        AsyncPacketStreamL2ToNet #(
        L2_WIDTH
,       LANE_WIDTH
,       'h10
        ) tx_stream_cdc (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(tx_stream_cdc__valid_in[__i])
        ,           .data_in(tx_stream_cdc__data_in[__i])
        ,           .keep_in(tx_stream_cdc__keep_in[__i])
        ,           .sop_in(tx_stream_cdc__sop_in[__i])
        ,           .eop_in(tx_stream_cdc__eop_in[__i])
        ,           .ready_out(tx_stream_cdc__ready_out[__i])
        ,           .valid_out(tx_stream_cdc__valid_out[__i])
        ,           .data_out(tx_stream_cdc__data_out[__i])
        ,           .keep_out(tx_stream_cdc__keep_out[__i])
        ,           .sop_out(tx_stream_cdc__sop_out[__i])
        ,           .eop_out(tx_stream_cdc__eop_out[__i])
        ,           .ready_in(tx_stream_cdc__ready_in[__i])
        );
    end
    endgenerate

    // tmp variables
    logic read_active_reg_tmp[8];
    logic[HANDLE_BITS-1:0] read_handle_reg_tmp[8];
    logic[14-1:0] read_remaining_reg_tmp[8];
    logic[LOGICAL_ROW_BITS-1:0] read_word_reg_tmp[8];
    logic[6-1:0] meta_bytes_reg_tmp[8][8];
    logic meta_sop_reg_tmp[8][8];
    logic meta_eop_reg_tmp[8][8];
    logic[3-1:0] meta_head_reg_tmp[8];
    logic[3-1:0] meta_tail_reg_tmp[8];
    logic[4-1:0] meta_count_reg_tmp[8];
    logic[1280-1:0] descriptor_hold_reg_tmp;
    logic[3-1:0] descriptor_word_reg_tmp;
    logic descriptor_valid_reg_tmp;


    always_comb begin : descriptor_word_comb_func  // descriptor_word_comb_func
        logic[31:0] _bit;
        logic[31:0] base;
        descriptor_word_comb = 'h0;
        base=unsigned'(32'(descriptor_word_reg))*L2_WIDTH;
        for (_bit='h0;_bit < L2_WIDTH;_bit=_bit+1) begin
            descriptor_word_comb[_bit] = descriptor_hold_reg[base + _bit];
        end
    end

    always_comb begin : network_read_valid_comb_func  // network_read_valid_comb_func
        logic[31:0] port;
        network_read_valid_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            network_read_valid_comb[port] = read_active_reg[port] && (unsigned'(32'(meta_count_reg[port])) < READ_META_DEPTH);
        end
    end

    always_comb begin : network_read_handle_comb_func  // network_read_handle_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        network_read_handle_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < HANDLE_BITS;_bit=_bit+1) begin
                network_read_handle_comb[(port*HANDLE_BITS) + _bit] = read_handle_reg[port][_bit];
            end
        end
    end

    always_comb begin : network_read_word_comb_func  // network_read_word_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        network_read_word_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < LOGICAL_ROW_BITS;_bit=_bit+1) begin
                network_read_word_comb[(port*LOGICAL_ROW_BITS) + _bit] = read_word_reg[port][_bit];
            end
        end
    end

    always_comb begin : network_read_ready_comb_func  // network_read_ready_comb_func
        logic[31:0] port;
        network_read_ready_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            network_read_ready_comb[port] = (unsigned'(32'(meta_count_reg[port])) != 'h0) && rx_stream_cdc__ready_out[port];
        end
    end

    always_comb begin : l2_read_command_ready_comb_func  // l2_read_command_ready_comb_func
        logic[31:0] port;
        l2_read_command_ready_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_read_command_ready_comb[port] = read_command_fifo__write_ready_out[port];
        end
    end

    always_comb begin : l2_rx_valid_comb_func  // l2_rx_valid_comb_func
        logic[31:0] port;
        l2_rx_valid_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_valid_comb[port] = rx_stream_cdc__valid_out[port];
        end
    end

    always_comb begin : l2_rx_data_comb_func  // l2_rx_data_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        l2_rx_data_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < L2_WIDTH;_bit=_bit+1) begin
                l2_rx_data_comb[(port*L2_WIDTH) + _bit] = rx_stream_cdc__data_out[port][_bit];
            end
        end
    end

    always_comb begin : l2_rx_keep_comb_func  // l2_rx_keep_comb_func
        logic[31:0] port;
        logic[31:0] _byte;
        l2_rx_keep_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_byte='h0;_byte < L2_BYTES;_byte=_byte+1) begin
                l2_rx_keep_comb[(port*L2_BYTES) + _byte] = rx_stream_cdc__keep_out[port][_byte];
            end
        end
    end

    always_comb begin : l2_rx_sop_comb_func  // l2_rx_sop_comb_func
        logic[31:0] port;
        l2_rx_sop_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_sop_comb[port] = rx_stream_cdc__sop_out[port];
        end
    end

    always_comb begin : l2_rx_eop_comb_func  // l2_rx_eop_comb_func
        logic[31:0] port;
        l2_rx_eop_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_eop_comb[port] = rx_stream_cdc__eop_out[port];
        end
    end

    always_comb begin : l2_tx_ready_comb_func  // l2_tx_ready_comb_func
        logic[31:0] stream;
        l2_tx_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            l2_tx_ready_comb[stream] = tx_stream_cdc__ready_out[stream];
        end
    end

    always_comb begin : network_tx_valid_comb_func  // network_tx_valid_comb_func
        logic[31:0] stream;
        network_tx_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_valid_comb[stream] = tx_stream_cdc__valid_out[stream];
        end
    end

    always_comb begin : network_tx_data_comb_func  // network_tx_data_comb_func
        logic[31:0] stream;
        logic[31:0] _bit;
        network_tx_data_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                network_tx_data_comb[(stream*LANE_WIDTH) + _bit] = tx_stream_cdc__data_out[stream][_bit];
            end
        end
    end

    always_comb begin : network_tx_keep_comb_func  // network_tx_keep_comb_func
        logic[31:0] stream;
        logic[31:0] _byte;
        network_tx_keep_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                network_tx_keep_comb[(stream*LANE_BYTES) + _byte] = tx_stream_cdc__keep_out[stream][_byte];
            end
        end
    end

    always_comb begin : network_tx_sop_comb_func  // network_tx_sop_comb_func
        logic[31:0] stream;
        network_tx_sop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_sop_comb[stream] = tx_stream_cdc__sop_out[stream];
        end
    end

    always_comb begin : network_tx_eop_comb_func  // network_tx_eop_comb_func
        logic[31:0] stream;
        network_tx_eop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_eop_comb[stream] = tx_stream_cdc__eop_out[stream];
        end
    end

    always_comb begin : read_command_0_comb_func  // read_command_0_comb_func
        read_command_0_comb = 'h0;
        read_command_0_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h0*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_0_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h0*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_0_comb_func  // read_command_pop_0_comb_func
        read_command_pop_0_comb=!read_active_reg['h0] && (unsigned'(32'(meta_count_reg['h0])) == 'h0);
    end

    always_comb begin : rx_input_data_0_comb_func  // rx_input_data_0_comb_func
        rx_input_data_0_comb = network__read_data_out['h0*LANE_WIDTH +:(('h0*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h0*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_0_comb_func  // rx_input_keep_0_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_0_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h0]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_0_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h0][head]));
        end
    end

    always_comb begin : read_command_1_comb_func  // read_command_1_comb_func
        read_command_1_comb = 'h0;
        read_command_1_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h1*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_1_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h1*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_1_comb_func  // read_command_pop_1_comb_func
        read_command_pop_1_comb=!read_active_reg['h1] && (unsigned'(32'(meta_count_reg['h1])) == 'h0);
    end

    always_comb begin : rx_input_data_1_comb_func  // rx_input_data_1_comb_func
        rx_input_data_1_comb = network__read_data_out['h1*LANE_WIDTH +:(('h1*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h1*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_1_comb_func  // rx_input_keep_1_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_1_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h1]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_1_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h1][head]));
        end
    end

    always_comb begin : read_command_2_comb_func  // read_command_2_comb_func
        read_command_2_comb = 'h0;
        read_command_2_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h2*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_2_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h2*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_2_comb_func  // read_command_pop_2_comb_func
        read_command_pop_2_comb=!read_active_reg['h2] && (unsigned'(32'(meta_count_reg['h2])) == 'h0);
    end

    always_comb begin : rx_input_data_2_comb_func  // rx_input_data_2_comb_func
        rx_input_data_2_comb = network__read_data_out['h2*LANE_WIDTH +:(('h2*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h2*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_2_comb_func  // rx_input_keep_2_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_2_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h2]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_2_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h2][head]));
        end
    end

    always_comb begin : read_command_3_comb_func  // read_command_3_comb_func
        read_command_3_comb = 'h0;
        read_command_3_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h3*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_3_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h3*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_3_comb_func  // read_command_pop_3_comb_func
        read_command_pop_3_comb=!read_active_reg['h3] && (unsigned'(32'(meta_count_reg['h3])) == 'h0);
    end

    always_comb begin : rx_input_data_3_comb_func  // rx_input_data_3_comb_func
        rx_input_data_3_comb = network__read_data_out['h3*LANE_WIDTH +:(('h3*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h3*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_3_comb_func  // rx_input_keep_3_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_3_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h3]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_3_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h3][head]));
        end
    end

    always_comb begin : read_command_4_comb_func  // read_command_4_comb_func
        read_command_4_comb = 'h0;
        read_command_4_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h4*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_4_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h4*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_4_comb_func  // read_command_pop_4_comb_func
        read_command_pop_4_comb=!read_active_reg['h4] && (unsigned'(32'(meta_count_reg['h4])) == 'h0);
    end

    always_comb begin : rx_input_data_4_comb_func  // rx_input_data_4_comb_func
        rx_input_data_4_comb = network__read_data_out['h4*LANE_WIDTH +:(('h4*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h4*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_4_comb_func  // rx_input_keep_4_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_4_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h4]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_4_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h4][head]));
        end
    end

    always_comb begin : read_command_5_comb_func  // read_command_5_comb_func
        read_command_5_comb = 'h0;
        read_command_5_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h5*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_5_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h5*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_5_comb_func  // read_command_pop_5_comb_func
        read_command_pop_5_comb=!read_active_reg['h5] && (unsigned'(32'(meta_count_reg['h5])) == 'h0);
    end

    always_comb begin : rx_input_data_5_comb_func  // rx_input_data_5_comb_func
        rx_input_data_5_comb = network__read_data_out['h5*LANE_WIDTH +:(('h5*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h5*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_5_comb_func  // rx_input_keep_5_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_5_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h5]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_5_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h5][head]));
        end
    end

    always_comb begin : read_command_6_comb_func  // read_command_6_comb_func
        read_command_6_comb = 'h0;
        read_command_6_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h6*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_6_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h6*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_6_comb_func  // read_command_pop_6_comb_func
        read_command_pop_6_comb=!read_active_reg['h6] && (unsigned'(32'(meta_count_reg['h6])) == 'h0);
    end

    always_comb begin : rx_input_data_6_comb_func  // rx_input_data_6_comb_func
        rx_input_data_6_comb = network__read_data_out['h6*LANE_WIDTH +:(('h6*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h6*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_6_comb_func  // rx_input_keep_6_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_6_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h6]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_6_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h6][head]));
        end
    end

    always_comb begin : read_command_7_comb_func  // read_command_7_comb_func
        read_command_7_comb = 'h0;
        read_command_7_comb['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1] = l2_rx_read_handle_in['h7*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1];
        read_command_7_comb[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] = l2_rx_read_length_in['h7*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1];
    end

    always_comb begin : read_command_pop_7_comb_func  // read_command_pop_7_comb_func
        read_command_pop_7_comb=!read_active_reg['h7] && (unsigned'(32'(meta_count_reg['h7])) == 'h0);
    end

    always_comb begin : rx_input_data_7_comb_func  // rx_input_data_7_comb_func
        rx_input_data_7_comb = network__read_data_out['h7*LANE_WIDTH +:(('h7*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h7*LANE_WIDTH + 1];
    end

    always_comb begin : rx_input_keep_7_comb_func  // rx_input_keep_7_comb_func
        logic[31:0] _byte;
        logic[31:0] head;
        rx_input_keep_7_comb = 'h0;
        head=unsigned'(32'(meta_head_reg['h7]));
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            rx_input_keep_7_comb[_byte] = _byte < unsigned'(32'(meta_bytes_reg['h7][head]));
        end
    end

    generate  // _assign
        assign network__valid_in = net_rx_valid_in;
        assign network__data_in = net_rx_data_in;
        assign network__keep_in = net_rx_keep_in;
        assign network__sop_in = net_rx_sop_in;
        assign network__eop_in = net_rx_eop_in;
        assign network__raw_in = net_rx_raw_in;
        assign network__descriptor_ready_in = descriptor_fifo__write_ready_out;
        assign network__read_valid_in = network_read_valid_comb;
        assign network__read_handle_in = network_read_handle_comb;
        assign network__read_word_in = network_read_word_comb;
        assign network__read_ready_in = network_read_ready_comb;
        assign network__tx_valid_in = network_tx_valid_comb;
        assign network__tx_data_in = network_tx_data_comb;
        assign network__tx_keep_in = network_tx_keep_comb;
        assign network__tx_sop_in = network_tx_sop_comb;
        assign network__tx_eop_in = network_tx_eop_comb;
        assign network__tx_ready_in = net_tx_ready_in;
        assign descriptor_fifo__write_valid_in = network__descriptor_valid_out;
        assign descriptor_fifo__write_data_in = network__descriptor_data_out.raw;
        assign descriptor_fifo__read_ready_in = !descriptor_valid_reg;
        assign read_command_fifo__write_valid_in['h0] = l2_rx_read_valid_in['h0];
        assign read_command_fifo__write_data_in['h0] = read_command_0_comb;
        assign read_command_fifo__read_ready_in['h0] = read_command_pop_0_comb;
        assign rx_stream_cdc__valid_in['h0] = network__read_valid_out['h0] && (unsigned'(32'(meta_count_reg['h0])) != 'h0);
        assign rx_stream_cdc__data_in['h0] = rx_input_data_0_comb;
        assign rx_stream_cdc__keep_in['h0] = rx_input_keep_0_comb;
        assign rx_stream_cdc__sop_in['h0] = meta_sop_reg['h0][unsigned'(32'(meta_head_reg['h0]))];
        assign rx_stream_cdc__eop_in['h0] = meta_eop_reg['h0][unsigned'(32'(meta_head_reg['h0]))];
        assign rx_stream_cdc__ready_in['h0] = l2_rx_ready_in['h0];
        assign read_command_fifo__write_valid_in['h1] = l2_rx_read_valid_in['h1];
        assign read_command_fifo__write_data_in['h1] = read_command_1_comb;
        assign read_command_fifo__read_ready_in['h1] = read_command_pop_1_comb;
        assign rx_stream_cdc__valid_in['h1] = network__read_valid_out['h1] && (unsigned'(32'(meta_count_reg['h1])) != 'h0);
        assign rx_stream_cdc__data_in['h1] = rx_input_data_1_comb;
        assign rx_stream_cdc__keep_in['h1] = rx_input_keep_1_comb;
        assign rx_stream_cdc__sop_in['h1] = meta_sop_reg['h1][unsigned'(32'(meta_head_reg['h1]))];
        assign rx_stream_cdc__eop_in['h1] = meta_eop_reg['h1][unsigned'(32'(meta_head_reg['h1]))];
        assign rx_stream_cdc__ready_in['h1] = l2_rx_ready_in['h1];
        assign read_command_fifo__write_valid_in['h2] = l2_rx_read_valid_in['h2];
        assign read_command_fifo__write_data_in['h2] = read_command_2_comb;
        assign read_command_fifo__read_ready_in['h2] = read_command_pop_2_comb;
        assign rx_stream_cdc__valid_in['h2] = network__read_valid_out['h2] && (unsigned'(32'(meta_count_reg['h2])) != 'h0);
        assign rx_stream_cdc__data_in['h2] = rx_input_data_2_comb;
        assign rx_stream_cdc__keep_in['h2] = rx_input_keep_2_comb;
        assign rx_stream_cdc__sop_in['h2] = meta_sop_reg['h2][unsigned'(32'(meta_head_reg['h2]))];
        assign rx_stream_cdc__eop_in['h2] = meta_eop_reg['h2][unsigned'(32'(meta_head_reg['h2]))];
        assign rx_stream_cdc__ready_in['h2] = l2_rx_ready_in['h2];
        assign read_command_fifo__write_valid_in['h3] = l2_rx_read_valid_in['h3];
        assign read_command_fifo__write_data_in['h3] = read_command_3_comb;
        assign read_command_fifo__read_ready_in['h3] = read_command_pop_3_comb;
        assign rx_stream_cdc__valid_in['h3] = network__read_valid_out['h3] && (unsigned'(32'(meta_count_reg['h3])) != 'h0);
        assign rx_stream_cdc__data_in['h3] = rx_input_data_3_comb;
        assign rx_stream_cdc__keep_in['h3] = rx_input_keep_3_comb;
        assign rx_stream_cdc__sop_in['h3] = meta_sop_reg['h3][unsigned'(32'(meta_head_reg['h3]))];
        assign rx_stream_cdc__eop_in['h3] = meta_eop_reg['h3][unsigned'(32'(meta_head_reg['h3]))];
        assign rx_stream_cdc__ready_in['h3] = l2_rx_ready_in['h3];
        assign read_command_fifo__write_valid_in['h4] = l2_rx_read_valid_in['h4];
        assign read_command_fifo__write_data_in['h4] = read_command_4_comb;
        assign read_command_fifo__read_ready_in['h4] = read_command_pop_4_comb;
        assign rx_stream_cdc__valid_in['h4] = network__read_valid_out['h4] && (unsigned'(32'(meta_count_reg['h4])) != 'h0);
        assign rx_stream_cdc__data_in['h4] = rx_input_data_4_comb;
        assign rx_stream_cdc__keep_in['h4] = rx_input_keep_4_comb;
        assign rx_stream_cdc__sop_in['h4] = meta_sop_reg['h4][unsigned'(32'(meta_head_reg['h4]))];
        assign rx_stream_cdc__eop_in['h4] = meta_eop_reg['h4][unsigned'(32'(meta_head_reg['h4]))];
        assign rx_stream_cdc__ready_in['h4] = l2_rx_ready_in['h4];
        assign read_command_fifo__write_valid_in['h5] = l2_rx_read_valid_in['h5];
        assign read_command_fifo__write_data_in['h5] = read_command_5_comb;
        assign read_command_fifo__read_ready_in['h5] = read_command_pop_5_comb;
        assign rx_stream_cdc__valid_in['h5] = network__read_valid_out['h5] && (unsigned'(32'(meta_count_reg['h5])) != 'h0);
        assign rx_stream_cdc__data_in['h5] = rx_input_data_5_comb;
        assign rx_stream_cdc__keep_in['h5] = rx_input_keep_5_comb;
        assign rx_stream_cdc__sop_in['h5] = meta_sop_reg['h5][unsigned'(32'(meta_head_reg['h5]))];
        assign rx_stream_cdc__eop_in['h5] = meta_eop_reg['h5][unsigned'(32'(meta_head_reg['h5]))];
        assign rx_stream_cdc__ready_in['h5] = l2_rx_ready_in['h5];
        assign read_command_fifo__write_valid_in['h6] = l2_rx_read_valid_in['h6];
        assign read_command_fifo__write_data_in['h6] = read_command_6_comb;
        assign read_command_fifo__read_ready_in['h6] = read_command_pop_6_comb;
        assign rx_stream_cdc__valid_in['h6] = network__read_valid_out['h6] && (unsigned'(32'(meta_count_reg['h6])) != 'h0);
        assign rx_stream_cdc__data_in['h6] = rx_input_data_6_comb;
        assign rx_stream_cdc__keep_in['h6] = rx_input_keep_6_comb;
        assign rx_stream_cdc__sop_in['h6] = meta_sop_reg['h6][unsigned'(32'(meta_head_reg['h6]))];
        assign rx_stream_cdc__eop_in['h6] = meta_eop_reg['h6][unsigned'(32'(meta_head_reg['h6]))];
        assign rx_stream_cdc__ready_in['h6] = l2_rx_ready_in['h6];
        assign read_command_fifo__write_valid_in['h7] = l2_rx_read_valid_in['h7];
        assign read_command_fifo__write_data_in['h7] = read_command_7_comb;
        assign read_command_fifo__read_ready_in['h7] = read_command_pop_7_comb;
        assign rx_stream_cdc__valid_in['h7] = network__read_valid_out['h7] && (unsigned'(32'(meta_count_reg['h7])) != 'h0);
        assign rx_stream_cdc__data_in['h7] = rx_input_data_7_comb;
        assign rx_stream_cdc__keep_in['h7] = rx_input_keep_7_comb;
        assign rx_stream_cdc__sop_in['h7] = meta_sop_reg['h7][unsigned'(32'(meta_head_reg['h7]))];
        assign rx_stream_cdc__eop_in['h7] = meta_eop_reg['h7][unsigned'(32'(meta_head_reg['h7]))];
        assign rx_stream_cdc__ready_in['h7] = l2_rx_ready_in['h7];
        assign tx_stream_cdc__valid_in['h0] = l2_tx_valid_in['h0];
        assign tx_stream_cdc__data_in['h0] = l2_tx_data_in['h0*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h0] = l2_tx_keep_in['h0*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h0] = l2_tx_sop_in['h0];
        assign tx_stream_cdc__eop_in['h0] = l2_tx_eop_in['h0];
        assign tx_stream_cdc__ready_in['h0] = network__tx_ready_out['h0];
        assign tx_stream_cdc__valid_in['h1] = l2_tx_valid_in['h1];
        assign tx_stream_cdc__data_in['h1] = l2_tx_data_in['h1*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h1] = l2_tx_keep_in['h1*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h1] = l2_tx_sop_in['h1];
        assign tx_stream_cdc__eop_in['h1] = l2_tx_eop_in['h1];
        assign tx_stream_cdc__ready_in['h1] = network__tx_ready_out['h1];
        assign tx_stream_cdc__valid_in['h2] = l2_tx_valid_in['h2];
        assign tx_stream_cdc__data_in['h2] = l2_tx_data_in['h2*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h2] = l2_tx_keep_in['h2*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h2] = l2_tx_sop_in['h2];
        assign tx_stream_cdc__eop_in['h2] = l2_tx_eop_in['h2];
        assign tx_stream_cdc__ready_in['h2] = network__tx_ready_out['h2];
        assign tx_stream_cdc__valid_in['h3] = l2_tx_valid_in['h3];
        assign tx_stream_cdc__data_in['h3] = l2_tx_data_in['h3*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h3] = l2_tx_keep_in['h3*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h3] = l2_tx_sop_in['h3];
        assign tx_stream_cdc__eop_in['h3] = l2_tx_eop_in['h3];
        assign tx_stream_cdc__ready_in['h3] = network__tx_ready_out['h3];
        assign tx_stream_cdc__valid_in['h4] = l2_tx_valid_in['h4];
        assign tx_stream_cdc__data_in['h4] = l2_tx_data_in['h4*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h4] = l2_tx_keep_in['h4*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h4] = l2_tx_sop_in['h4];
        assign tx_stream_cdc__eop_in['h4] = l2_tx_eop_in['h4];
        assign tx_stream_cdc__ready_in['h4] = network__tx_ready_out['h4];
        assign tx_stream_cdc__valid_in['h5] = l2_tx_valid_in['h5];
        assign tx_stream_cdc__data_in['h5] = l2_tx_data_in['h5*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h5] = l2_tx_keep_in['h5*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h5] = l2_tx_sop_in['h5];
        assign tx_stream_cdc__eop_in['h5] = l2_tx_eop_in['h5];
        assign tx_stream_cdc__ready_in['h5] = network__tx_ready_out['h5];
        assign tx_stream_cdc__valid_in['h6] = l2_tx_valid_in['h6];
        assign tx_stream_cdc__data_in['h6] = l2_tx_data_in['h6*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h6] = l2_tx_keep_in['h6*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h6] = l2_tx_sop_in['h6];
        assign tx_stream_cdc__eop_in['h6] = l2_tx_eop_in['h6];
        assign tx_stream_cdc__ready_in['h6] = network__tx_ready_out['h6];
        assign tx_stream_cdc__valid_in['h7] = l2_tx_valid_in['h7];
        assign tx_stream_cdc__data_in['h7] = l2_tx_data_in['h7*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream_cdc__keep_in['h7] = l2_tx_keep_in['h7*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream_cdc__sop_in['h7] = l2_tx_sop_in['h7];
        assign tx_stream_cdc__eop_in['h7] = l2_tx_eop_in['h7];
        assign tx_stream_cdc__ready_in['h7] = network__tx_ready_out['h7];
        assign net_rx_ready_out = network__ready_out;
        assign net_tx_valid_out = network__tx_valid_out;
        assign net_tx_data_out = network__tx_data_out;
        assign net_tx_keep_out = network__tx_keep_out;
        assign net_tx_sop_out = network__tx_sop_out;
        assign net_tx_eop_out = network__tx_eop_out;
        assign l2_descriptor_valid_out = descriptor_valid_reg;
        assign l2_descriptor_data_out = descriptor_word_comb;
        assign l2_descriptor_word_out = descriptor_word_reg;
        assign l2_descriptor_sop_out = descriptor_valid_reg && (unsigned'(32'(descriptor_word_reg)) == 'h0);
        assign l2_descriptor_eop_out = descriptor_valid_reg && (unsigned'(32'(descriptor_word_reg)) == 'h4);
        assign l2_rx_read_ready_out = l2_read_command_ready_comb;
        assign l2_rx_valid_out = l2_rx_valid_comb;
        assign l2_rx_data_out = l2_rx_data_comb;
        assign l2_rx_keep_out = l2_rx_keep_comb;
        assign l2_rx_sop_out = l2_rx_sop_comb;
        assign l2_rx_eop_out = l2_rx_eop_comb;
        assign l2_tx_ready_out = l2_tx_ready_comb;
        assign protocol_error_out = network__protocol_error_out;
        assign storage_full_out = network__storage_full_out;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[31:0] port;
        logic[31:0] slot;
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] count;
        logic[31:0] remaining;
        logic[31:0] bytes;
        logic command_fire;
        logic request_fire;
        logic response_fire;
        logic[30-1:0] command;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            head=unsigned'(32'(meta_head_reg[port]));
            tail=unsigned'(32'(meta_tail_reg[port]));
            count=unsigned'(32'(meta_count_reg[port]));
            command_fire=(read_command_fifo__read_valid_out[port] && !read_active_reg[port]) && (count == 'h0);
            if (command_fire) begin
                command = read_command_fifo__read_data_out[port];
                read_handle_reg_tmp[port] = command['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1];
                read_remaining_reg_tmp[port] = command[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1];
                read_word_reg_tmp[port] = 'h0;
                read_active_reg_tmp[port] = unsigned'(1'(command[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1] != 'h0));
            end
            request_fire=network_read_valid_comb[port] && network__read_ready_out[port];
            response_fire=network__read_valid_out[port] && network_read_ready_comb[port];
            if (response_fire) begin
                head=((head + 'h1)) & ((READ_META_DEPTH - 'h1));
                --count;
            end
            if (request_fire) begin
                remaining=unsigned'(32'(read_remaining_reg[port]));
                bytes=(remaining > LANE_BYTES) ? (LANE_BYTES) : (remaining);
                meta_bytes_reg_tmp[port][tail] = bytes;
                meta_sop_reg_tmp[port][tail] = unsigned'(1'(unsigned'(32'(read_word_reg[port])) == 'h0));
                meta_eop_reg_tmp[port][tail] = unsigned'(1'(remaining<=LANE_BYTES));
                tail=((tail + 'h1)) & ((READ_META_DEPTH - 'h1));
                count=count+1;
                read_word_reg_tmp[port] = read_word_reg[port] + 'h1;
                if (remaining<=LANE_BYTES) begin
                    read_remaining_reg_tmp[port] = 'h0;
                    read_active_reg_tmp[port] = unsigned'(1'h0);
                end
                else begin
                    read_remaining_reg_tmp[port] = remaining - LANE_BYTES;
                end
            end
            meta_head_reg_tmp[port] = head;
            meta_tail_reg_tmp[port] = tail;
            meta_count_reg_tmp[port] = count;
        end
        if (reset) begin
            for (port='h0;port < READ_PORTS;port=port+1) begin
                read_active_reg_tmp[port] = '0;
                read_handle_reg_tmp[port] = '0;
                read_remaining_reg_tmp[port] = '0;
                read_word_reg_tmp[port] = '0;
                meta_head_reg_tmp[port] = '0;
                meta_tail_reg_tmp[port] = '0;
                meta_count_reg_tmp[port] = '0;
                for (slot='h0;slot < READ_META_DEPTH;slot=slot+1) begin
                    meta_bytes_reg_tmp[port][slot] = '0;
                    meta_sop_reg_tmp[port][slot] = '0;
                    meta_eop_reg_tmp[port][slot] = '0;
                end
            end
        end
    end
    endtask

    task _work_l2_clk (input logic reset);
    begin: _work_l2_clk
        logic[31:0] port;
        if (descriptor_fifo__read_valid_out && !descriptor_valid_reg) begin
            descriptor_hold_reg_tmp = descriptor_fifo__read_data_out;
            descriptor_word_reg_tmp = 'h0;
            descriptor_valid_reg_tmp = unsigned'(1'h1);
        end
        if (descriptor_valid_reg && l2_descriptor_ready_in) begin
            if (unsigned'(32'(descriptor_word_reg)) == 'h4) begin
                descriptor_valid_reg_tmp = unsigned'(1'h0);
                descriptor_word_reg_tmp = 'h0;
            end
            else begin
                descriptor_word_reg_tmp = descriptor_word_reg + 'h1;
            end
        end
        if (reset) begin
            descriptor_hold_reg_tmp = '0;
            descriptor_word_reg_tmp = '0;
            descriptor_valid_reg_tmp = '0;
        end
    end
    endtask

    always_ff @(posedge net_clk) begin
        read_active_reg_tmp = read_active_reg;
        read_handle_reg_tmp = read_handle_reg;
        read_remaining_reg_tmp = read_remaining_reg;
        read_word_reg_tmp = read_word_reg;
        meta_bytes_reg_tmp = meta_bytes_reg;
        meta_sop_reg_tmp = meta_sop_reg;
        meta_eop_reg_tmp = meta_eop_reg;
        meta_head_reg_tmp = meta_head_reg;
        meta_tail_reg_tmp = meta_tail_reg;
        meta_count_reg_tmp = meta_count_reg;

        _work_net_clk(reset);

        read_active_reg <= read_active_reg_tmp;
        read_handle_reg <= read_handle_reg_tmp;
        read_remaining_reg <= read_remaining_reg_tmp;
        read_word_reg <= read_word_reg_tmp;
        meta_bytes_reg <= meta_bytes_reg_tmp;
        meta_sop_reg <= meta_sop_reg_tmp;
        meta_eop_reg <= meta_eop_reg_tmp;
        meta_head_reg <= meta_head_reg_tmp;
        meta_tail_reg <= meta_tail_reg_tmp;
        meta_count_reg <= meta_count_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin
        descriptor_hold_reg_tmp = descriptor_hold_reg;
        descriptor_word_reg_tmp = descriptor_word_reg;
        descriptor_valid_reg_tmp = descriptor_valid_reg;

        _work_l2_clk(reset);

        descriptor_hold_reg <= descriptor_hold_reg_tmp;
        descriptor_word_reg <= descriptor_word_reg_tmp;
        descriptor_valid_reg <= descriptor_valid_reg_tmp;
    end


endmodule
