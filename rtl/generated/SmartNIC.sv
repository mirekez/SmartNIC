`default_nettype none

import Predef_pkg::*;


module SmartNIC #(
    parameter LANE_WIDTH = 'h40
,   parameter BANK_DEPTH = 'h1000
,   parameter RX_FIFO_DEPTH = 'h40
,   parameter TX_FIFO_WORDS = 'h800
,   parameter ENABLE_RAW = 1
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
,   input wire[1-1:0] l2_rx_read_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] l2_rx_read_handle_in
,   input wire[14-1:0] l2_rx_read_length_in
,   output wire[1-1:0] l2_rx_read_ready_out
,   output wire[1-1:0] l2_rx_valid_out
,   output wire[256-1:0] l2_rx_data_out
,   output wire[32-1:0] l2_rx_keep_out
,   output wire[1-1:0] l2_rx_sop_out
,   output wire[1-1:0] l2_rx_eop_out
,   input wire[1-1:0] l2_rx_ready_in
,   input wire[2-1:0] l2_tx_valid_in
,   input wire[512-1:0] l2_tx_data_in
,   input wire[64-1:0] l2_tx_keep_in
,   input wire[2-1:0] l2_tx_sop_in
,   input wire[2-1:0] l2_tx_eop_in
,   output wire[2-1:0] l2_tx_ready_out
,   output wire protocol_error_out
,   output wire storage_full_out
);
    localparam  STREAMS = 64'h2;
    localparam  READ_PORTS = 64'h1;
    localparam  L2_WIDTH = 64'h100;
    localparam  L2_BYTES = 64'h20;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  NET_BITS = STREAMS*LANE_WIDTH;
    localparam  NET_BYTES = STREAMS*LANE_BYTES;
    localparam  LOGICAL_ROWS = BANK_DEPTH*'h2;
    localparam  LOGICAL_ROW_BITS = $clog2(LOGICAL_ROWS);
    localparam  HANDLE_BITS = LOGICAL_ROW_BITS + 'h3;
    localparam  FRAME_LENGTH_BITS = 64'hE;
    localparam  READ_COMMAND_BITS = HANDLE_BITS + FRAME_LENGTH_BITS;
    localparam  READ_META_DEPTH = 64'h8;


    // regs and combs
    reg read_active_reg[1];
    reg[HANDLE_BITS-1:0] read_handle_reg[1];
    reg[14-1:0] read_length_reg[1];
    reg[14-1:0] read_remaining_reg[1];
    reg[LOGICAL_ROW_BITS-1:0] read_word_reg[1];
    reg[6-1:0] meta_bytes_reg[1][8];
    reg meta_sop_reg[1][8];
    reg meta_eop_reg[1][8];
    reg[HANDLE_BITS-1:0] meta_handle_reg[1][8];
    reg[14-1:0] meta_length_reg[1][8];
    reg[3-1:0] meta_head_reg[1];
    reg[3-1:0] meta_tail_reg[1];
    reg[4-1:0] meta_count_reg[1];
    reg[1280-1:0] descriptor_hold_reg;
    reg[3-1:0] descriptor_word_reg;
    reg descriptor_valid_reg;
    logic[1-1:0] network_read_valid_comb;
    logic[READ_PORTS*HANDLE_BITS-1:0] network_read_handle_comb;
    logic[READ_PORTS*LOGICAL_ROW_BITS-1:0] network_read_word_comb;
    logic[1-1:0] network_read_ready_comb;
    logic[1-1:0] network_release_valid_comb;
    logic[READ_PORTS*HANDLE_BITS-1:0] network_release_handle_comb;
    logic[14-1:0] network_release_length_comb;
    logic[2-1:0] network_tx_valid_comb;
    logic[NET_BITS-1:0] network_tx_data_comb;
    logic[NET_BYTES-1:0] network_tx_keep_comb;
    logic[2-1:0] network_tx_sop_comb;
    logic[2-1:0] network_tx_eop_comb;
    logic[1-1:0] l2_read_command_ready_comb;
    logic[1-1:0] l2_rx_valid_comb;
    logic[256-1:0] l2_rx_data_comb;
    logic[32-1:0] l2_rx_keep_comb;
    logic[1-1:0] l2_rx_sop_comb;
    logic[1-1:0] l2_rx_eop_comb;
    logic[2-1:0] l2_tx_ready_comb;
    logic[256-1:0] descriptor_word_comb;
    logic[READ_COMMAND_BITS-1:0] read_command_0_comb;
    logic read_command_pop_0_comb;
    logic[LANE_WIDTH-1:0] rx_input_data_0_comb;
    logic[LANE_BYTES-1:0] rx_input_keep_0_comb;

    // members
    genvar __i;
    wire network__valid_in;
    wire[64'h2*LANE_WIDTH-1:0] network__data_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__keep_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__sop_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__eop_in;
    wire network__raw_in;
    wire network__ready_out;
    wire network__descriptor_valid_out;
    wire RxDescriptorWord network__descriptor_data_out;
    wire network__descriptor_ready_in;
    wire[READ_PORTS-1:0] network__read_valid_in;
    wire[READ_PORTS*($clog2((BANK_DEPTH*'h2)) + 'h3)-1:0] network__read_handle_in;
    wire[READ_PORTS*$clog2((BANK_DEPTH*'h2))-1:0] network__read_word_in;
    wire[READ_PORTS-1:0] network__read_ready_out;
    wire[READ_PORTS*LANE_WIDTH-1:0] network__read_data_out;
    wire[READ_PORTS-1:0] network__read_valid_out;
    wire[READ_PORTS-1:0] network__read_ready_in;
    wire[READ_PORTS-1:0] network__release_valid_in;
    wire[READ_PORTS*($clog2((BANK_DEPTH*'h2)) + 'h3)-1:0] network__release_handle_in;
    wire[READ_PORTS*64'hE-1:0] network__release_length_in;
    wire[2-1:0] network__tx_valid_in;
    wire[64'h2*LANE_WIDTH-1:0] network__tx_data_in;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__tx_keep_in;
    wire[2-1:0] network__tx_sop_in;
    wire[2-1:0] network__tx_eop_in;
    wire[2-1:0] network__tx_ready_out;
    wire[2-1:0] network__tx_almost_full_out;
    wire network__tx_valid_out;
    wire[64'h2*LANE_WIDTH-1:0] network__tx_data_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__tx_keep_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__tx_sop_out;
    wire[64'h2*(LANE_WIDTH/'h8)-1:0] network__tx_eop_out;
    wire network__tx_ready_in;
    wire network__protocol_error_out;
    wire network__storage_full_out;
    Network #(
        LANE_WIDTH
,       READ_PORTS
,       BANK_DEPTH
,       RX_FIFO_DEPTH
,       TX_FIFO_WORDS
,       ENABLE_RAW
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
,       .release_valid_in(network__release_valid_in)
,       .release_handle_in(network__release_handle_in)
,       .release_length_in(network__release_length_in)
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
    wire rx_stream__valid_in[1];
    wire[LANE_WIDTH-1:0] rx_stream__data_in[1];
    wire[LANE_WIDTH/'h8-1:0] rx_stream__keep_in[1];
    wire rx_stream__sop_in[1];
    wire rx_stream__eop_in[1];
    wire rx_stream__ready_out[1];
    wire rx_stream__valid_out[1];
    wire[L2_WIDTH-1:0] rx_stream__data_out[1];
    wire[L2_WIDTH/'h8-1:0] rx_stream__keep_out[1];
    wire rx_stream__sop_out[1];
    wire rx_stream__eop_out[1];
    wire rx_stream__ready_in[1];
    generate
    for (__i=0; __i < 1; __i = __i + 1) begin
        PacketStream #(
        LANE_WIDTH
,       L2_WIDTH
        ) rx_stream (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(rx_stream__valid_in[__i])
        ,           .data_in(rx_stream__data_in[__i])
        ,           .keep_in(rx_stream__keep_in[__i])
        ,           .sop_in(rx_stream__sop_in[__i])
        ,           .eop_in(rx_stream__eop_in[__i])
        ,           .ready_out(rx_stream__ready_out[__i])
        ,           .valid_out(rx_stream__valid_out[__i])
        ,           .data_out(rx_stream__data_out[__i])
        ,           .keep_out(rx_stream__keep_out[__i])
        ,           .sop_out(rx_stream__sop_out[__i])
        ,           .eop_out(rx_stream__eop_out[__i])
        ,           .ready_in(rx_stream__ready_in[__i])
        );
    end
    endgenerate
    wire tx_stream__valid_in[2];
    wire[L2_WIDTH-1:0] tx_stream__data_in[2];
    wire[L2_WIDTH/'h8-1:0] tx_stream__keep_in[2];
    wire tx_stream__sop_in[2];
    wire tx_stream__eop_in[2];
    wire tx_stream__ready_out[2];
    wire tx_stream__valid_out[2];
    wire[LANE_WIDTH-1:0] tx_stream__data_out[2];
    wire[LANE_WIDTH/'h8-1:0] tx_stream__keep_out[2];
    wire tx_stream__sop_out[2];
    wire tx_stream__eop_out[2];
    wire tx_stream__ready_in[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        PacketStream #(
        L2_WIDTH
,       LANE_WIDTH
        ) tx_stream (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .valid_in(tx_stream__valid_in[__i])
        ,           .data_in(tx_stream__data_in[__i])
        ,           .keep_in(tx_stream__keep_in[__i])
        ,           .sop_in(tx_stream__sop_in[__i])
        ,           .eop_in(tx_stream__eop_in[__i])
        ,           .ready_out(tx_stream__ready_out[__i])
        ,           .valid_out(tx_stream__valid_out[__i])
        ,           .data_out(tx_stream__data_out[__i])
        ,           .keep_out(tx_stream__keep_out[__i])
        ,           .sop_out(tx_stream__sop_out[__i])
        ,           .eop_out(tx_stream__eop_out[__i])
        ,           .ready_in(tx_stream__ready_in[__i])
        );
    end
    endgenerate

    // tmp variables
    logic read_active_reg_tmp[1];
    logic[HANDLE_BITS-1:0] read_handle_reg_tmp[1];
    logic[14-1:0] read_length_reg_tmp[1];
    logic[14-1:0] read_remaining_reg_tmp[1];
    logic[LOGICAL_ROW_BITS-1:0] read_word_reg_tmp[1];
    logic[6-1:0] meta_bytes_reg_tmp[1][8];
    logic meta_sop_reg_tmp[1][8];
    logic meta_eop_reg_tmp[1][8];
    logic[HANDLE_BITS-1:0] meta_handle_reg_tmp[1][8];
    logic[14-1:0] meta_length_reg_tmp[1][8];
    logic[3-1:0] meta_head_reg_tmp[1];
    logic[3-1:0] meta_tail_reg_tmp[1];
    logic[4-1:0] meta_count_reg_tmp[1];
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
            network_read_ready_comb[port] = (unsigned'(32'(meta_count_reg[port])) != 'h0) && rx_stream__ready_out[port];
        end
    end

    always_comb begin : network_release_valid_comb_func  // network_release_valid_comb_func
        logic[31:0] port;
        logic[31:0] head;
        network_release_valid_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            head=unsigned'(32'(meta_head_reg[port]));
            network_release_valid_comb[port] = (network__read_valid_out[port] && network_read_ready_comb[port]) && meta_eop_reg[port][head];
        end
    end

    always_comb begin : network_release_handle_comb_func  // network_release_handle_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        network_release_handle_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < HANDLE_BITS;_bit=_bit+1) begin
                network_release_handle_comb[(port*HANDLE_BITS) + _bit] = meta_handle_reg[port][unsigned'(32'(meta_head_reg[port]))][_bit];
            end
        end
    end

    always_comb begin : network_release_length_comb_func  // network_release_length_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        network_release_length_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < FRAME_LENGTH_BITS;_bit=_bit+1) begin
                network_release_length_comb[(port*FRAME_LENGTH_BITS) + _bit] = meta_length_reg[port][unsigned'(32'(meta_head_reg[port]))][_bit];
            end
        end
    end

    always_comb begin : l2_read_command_ready_comb_func  // l2_read_command_ready_comb_func
        logic[31:0] port;
        l2_read_command_ready_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_read_command_ready_comb[port] = !read_active_reg[port] && (unsigned'(32'(meta_count_reg[port])) == 'h0);
        end
    end

    always_comb begin : l2_rx_valid_comb_func  // l2_rx_valid_comb_func
        logic[31:0] port;
        l2_rx_valid_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_valid_comb[port] = rx_stream__valid_out[port];
        end
    end

    always_comb begin : l2_rx_data_comb_func  // l2_rx_data_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        l2_rx_data_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < L2_WIDTH;_bit=_bit+1) begin
                l2_rx_data_comb[(port*L2_WIDTH) + _bit] = rx_stream__data_out[port][_bit];
            end
        end
    end

    always_comb begin : l2_rx_keep_comb_func  // l2_rx_keep_comb_func
        logic[31:0] port;
        logic[31:0] _byte;
        l2_rx_keep_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_byte='h0;_byte < L2_BYTES;_byte=_byte+1) begin
                l2_rx_keep_comb[(port*L2_BYTES) + _byte] = rx_stream__keep_out[port][_byte];
            end
        end
    end

    always_comb begin : l2_rx_sop_comb_func  // l2_rx_sop_comb_func
        logic[31:0] port;
        l2_rx_sop_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_sop_comb[port] = rx_stream__sop_out[port];
        end
    end

    always_comb begin : l2_rx_eop_comb_func  // l2_rx_eop_comb_func
        logic[31:0] port;
        l2_rx_eop_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            l2_rx_eop_comb[port] = rx_stream__eop_out[port];
        end
    end

    always_comb begin : l2_tx_ready_comb_func  // l2_tx_ready_comb_func
        logic[31:0] stream;
        l2_tx_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            l2_tx_ready_comb[stream] = tx_stream__ready_out[stream];
        end
    end

    always_comb begin : network_tx_valid_comb_func  // network_tx_valid_comb_func
        logic[31:0] stream;
        network_tx_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_valid_comb[stream] = tx_stream__valid_out[stream];
        end
    end

    always_comb begin : network_tx_data_comb_func  // network_tx_data_comb_func
        logic[31:0] stream;
        logic[31:0] _bit;
        network_tx_data_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                network_tx_data_comb[(stream*LANE_WIDTH) + _bit] = tx_stream__data_out[stream][_bit];
            end
        end
    end

    always_comb begin : network_tx_keep_comb_func  // network_tx_keep_comb_func
        logic[31:0] stream;
        logic[31:0] _byte;
        network_tx_keep_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                network_tx_keep_comb[(stream*LANE_BYTES) + _byte] = tx_stream__keep_out[stream][_byte];
            end
        end
    end

    always_comb begin : network_tx_sop_comb_func  // network_tx_sop_comb_func
        logic[31:0] stream;
        network_tx_sop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_sop_comb[stream] = tx_stream__sop_out[stream];
        end
    end

    always_comb begin : network_tx_eop_comb_func  // network_tx_eop_comb_func
        logic[31:0] stream;
        network_tx_eop_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            network_tx_eop_comb[stream] = tx_stream__eop_out[stream];
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

    generate  // _assign
        assign network__valid_in = net_rx_valid_in;
        assign network__data_in = net_rx_data_in;
        assign network__keep_in = net_rx_keep_in;
        assign network__sop_in = net_rx_sop_in;
        assign network__eop_in = net_rx_eop_in;
        assign network__raw_in = net_rx_raw_in;
        assign network__descriptor_ready_in = !descriptor_valid_reg || ((l2_descriptor_ready_in && (unsigned'(32'(descriptor_word_reg)) == 'h4)));
        assign network__read_valid_in = network_read_valid_comb;
        assign network__read_handle_in = network_read_handle_comb;
        assign network__read_word_in = network_read_word_comb;
        assign network__read_ready_in = network_read_ready_comb;
        assign network__release_valid_in = network_release_valid_comb;
        assign network__release_handle_in = network_release_handle_comb;
        assign network__release_length_in = network_release_length_comb;
        assign network__tx_valid_in = network_tx_valid_comb;
        assign network__tx_data_in = network_tx_data_comb;
        assign network__tx_keep_in = network_tx_keep_comb;
        assign network__tx_sop_in = network_tx_sop_comb;
        assign network__tx_eop_in = network_tx_eop_comb;
        assign network__tx_ready_in = net_tx_ready_in;
        assign rx_stream__valid_in['h0] = network__read_valid_out['h0] && (unsigned'(32'(meta_count_reg['h0])) != 'h0);
        assign rx_stream__data_in['h0] = rx_input_data_0_comb;
        assign rx_stream__keep_in['h0] = rx_input_keep_0_comb;
        assign rx_stream__sop_in['h0] = meta_sop_reg['h0][unsigned'(32'(meta_head_reg['h0]))];
        assign rx_stream__eop_in['h0] = meta_eop_reg['h0][unsigned'(32'(meta_head_reg['h0]))];
        assign rx_stream__ready_in['h0] = l2_rx_ready_in['h0];
        assign tx_stream__valid_in['h0] = l2_tx_valid_in['h0];
        assign tx_stream__data_in['h0] = l2_tx_data_in['h0*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream__keep_in['h0] = l2_tx_keep_in['h0*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream__sop_in['h0] = l2_tx_sop_in['h0];
        assign tx_stream__eop_in['h0] = l2_tx_eop_in['h0];
        assign tx_stream__ready_in['h0] = network__tx_ready_out['h0];
        assign tx_stream__valid_in['h1] = l2_tx_valid_in['h1];
        assign tx_stream__data_in['h1] = l2_tx_data_in['h1*L2_WIDTH +:(0 + L2_WIDTH) - 'h1 - 0 + 1];
        assign tx_stream__keep_in['h1] = l2_tx_keep_in['h1*L2_BYTES +:(0 + L2_BYTES) - 'h1 - 0 + 1];
        assign tx_stream__sop_in['h1] = l2_tx_sop_in['h1];
        assign tx_stream__eop_in['h1] = l2_tx_eop_in['h1];
        assign tx_stream__ready_in['h1] = network__tx_ready_out['h1];
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
            command_fire=l2_rx_read_valid_in[port] && l2_read_command_ready_comb[port];
            if (command_fire) begin
                command = read_command_0_comb;
                read_handle_reg_tmp[port] = command['h0 +:HANDLE_BITS - 'h1 - 'h0 + 1];
                read_length_reg_tmp[port] = command[HANDLE_BITS +:READ_COMMAND_BITS - 'h1 - HANDLE_BITS + 1];
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
                meta_handle_reg_tmp[port][tail] = read_handle_reg[port];
                meta_length_reg_tmp[port][tail] = read_length_reg[port];
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
        if (descriptor_valid_reg && l2_descriptor_ready_in) begin
            if (unsigned'(32'(descriptor_word_reg)) == 'h4) begin
                descriptor_valid_reg_tmp = unsigned'(1'h0);
                descriptor_word_reg_tmp = 'h0;
            end
            else begin
                descriptor_word_reg_tmp = descriptor_word_reg + 'h1;
            end
        end
        if (network__descriptor_valid_out && network__descriptor_ready_in) begin
            descriptor_hold_reg_tmp = network__descriptor_data_out.raw;
            descriptor_word_reg_tmp = 'h0;
            descriptor_valid_reg_tmp = unsigned'(1'h1);
        end
        if (reset) begin
            for (port='h0;port < READ_PORTS;port=port+1) begin
                read_active_reg_tmp[port] = '0;
                read_handle_reg_tmp[port] = '0;
                read_length_reg_tmp[port] = '0;
                read_remaining_reg_tmp[port] = '0;
                read_word_reg_tmp[port] = '0;
                meta_head_reg_tmp[port] = '0;
                meta_tail_reg_tmp[port] = '0;
                meta_count_reg_tmp[port] = '0;
                for (slot='h0;slot < READ_META_DEPTH;slot=slot+1) begin
                    meta_bytes_reg_tmp[port][slot] = '0;
                    meta_sop_reg_tmp[port][slot] = '0;
                    meta_eop_reg_tmp[port][slot] = '0;
                    meta_handle_reg_tmp[port][slot] = '0;
                    meta_length_reg_tmp[port][slot] = '0;
                end
            end
            descriptor_hold_reg_tmp = '0;
            descriptor_word_reg_tmp = '0;
            descriptor_valid_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clk (input logic reset);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        read_active_reg_tmp = read_active_reg;
        read_handle_reg_tmp = read_handle_reg;
        read_length_reg_tmp = read_length_reg;
        read_remaining_reg_tmp = read_remaining_reg;
        read_word_reg_tmp = read_word_reg;
        meta_bytes_reg_tmp = meta_bytes_reg;
        meta_sop_reg_tmp = meta_sop_reg;
        meta_eop_reg_tmp = meta_eop_reg;
        meta_handle_reg_tmp = meta_handle_reg;
        meta_length_reg_tmp = meta_length_reg;
        meta_head_reg_tmp = meta_head_reg;
        meta_tail_reg_tmp = meta_tail_reg;
        meta_count_reg_tmp = meta_count_reg;
        descriptor_hold_reg_tmp = descriptor_hold_reg;
        descriptor_word_reg_tmp = descriptor_word_reg;
        descriptor_valid_reg_tmp = descriptor_valid_reg;

        _work_net_clk(reset);

        read_active_reg <= read_active_reg_tmp;
        read_handle_reg <= read_handle_reg_tmp;
        read_length_reg <= read_length_reg_tmp;
        read_remaining_reg <= read_remaining_reg_tmp;
        read_word_reg <= read_word_reg_tmp;
        meta_bytes_reg <= meta_bytes_reg_tmp;
        meta_sop_reg <= meta_sop_reg_tmp;
        meta_eop_reg <= meta_eop_reg_tmp;
        meta_handle_reg <= meta_handle_reg_tmp;
        meta_length_reg <= meta_length_reg_tmp;
        meta_head_reg <= meta_head_reg_tmp;
        meta_tail_reg <= meta_tail_reg_tmp;
        meta_count_reg <= meta_count_reg_tmp;
        descriptor_hold_reg <= descriptor_hold_reg_tmp;
        descriptor_word_reg <= descriptor_word_reg_tmp;
        descriptor_valid_reg <= descriptor_valid_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
