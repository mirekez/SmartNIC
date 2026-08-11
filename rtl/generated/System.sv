`default_nettype none

import Predef_pkg::*;


module System #(
    parameter QUEUES = 'h8
,   parameter QUEUE_DEPTH = 'h100
 )
 (
    input wire system_clock
,   input wire l2_clock
,   input wire reset
,   input wire[QUEUES-1:0] l2_rx_valid_in
,   input wire[QUEUES*DATA_WIDTH-1:0] l2_rx_data_in
,   input wire[QUEUES*DATA_BYTES-1:0] l2_rx_keep_in
,   input wire[QUEUES-1:0] l2_rx_sop_in
,   input wire[QUEUES-1:0] l2_rx_eop_in
,   output wire[QUEUES-1:0] l2_rx_ready_out
,   output wire[QUEUES-1:0] l2_tx_valid_out
,   output wire[QUEUES*DATA_WIDTH-1:0] l2_tx_data_out
,   output wire[QUEUES*DATA_BYTES-1:0] l2_tx_keep_out
,   output wire[QUEUES-1:0] l2_tx_sop_out
,   output wire[QUEUES-1:0] l2_tx_eop_out
,   input wire[QUEUES-1:0] l2_tx_ready_in
,   input wire host_control__awvalid_in
,   output wire host_control__awready_out
,   input wire[32-1:0] host_control__awaddr_in
,   input wire[4-1:0] host_control__awid_in
,   input wire host_control__wvalid_in
,   output wire host_control__wready_out
,   input wire[256-1:0] host_control__wdata_in
,   input wire[256/'h8-1:0] host_control__wstrb_in
,   input wire host_control__wlast_in
,   output wire host_control__bvalid_out
,   input wire host_control__bready_in
,   output wire[4-1:0] host_control__bid_out
,   input wire host_control__arvalid_in
,   output wire host_control__arready_out
,   input wire[32-1:0] host_control__araddr_in
,   input wire[4-1:0] host_control__arid_in
,   output wire host_control__rvalid_out
,   input wire host_control__rready_in
,   output wire[256-1:0] host_control__rdata_out
,   output wire host_control__rlast_out
,   output wire[4-1:0] host_control__rid_out
,   output wire host_dma__awvalid_out
,   input wire host_dma__awready_in
,   output wire[64-1:0] host_dma__awaddr_out
,   output wire[4-1:0] host_dma__awid_out
,   output wire host_dma__wvalid_out
,   input wire host_dma__wready_in
,   output wire[256-1:0] host_dma__wdata_out
,   output wire[256/'h8-1:0] host_dma__wstrb_out
,   output wire host_dma__wlast_out
,   input wire host_dma__bvalid_in
,   output wire host_dma__bready_out
,   input wire[4-1:0] host_dma__bid_in
,   output wire host_dma__arvalid_out
,   input wire host_dma__arready_in
,   output wire[64-1:0] host_dma__araddr_out
,   output wire[4-1:0] host_dma__arid_out
,   input wire host_dma__rvalid_in
,   output wire host_dma__rready_out
,   input wire[256-1:0] host_dma__rdata_in
,   input wire host_dma__rlast_in
,   input wire[4-1:0] host_dma__rid_in
,   output wire[QUEUES-1:0] rx_queue_empty_out
,   output wire[QUEUES-1:0] tx_queue_empty_out
,   output wire protocol_error_out
);
    parameter  DATA_WIDTH = 64'h100;
    parameter  DATA_BYTES = 64'h20;
    parameter  STREAM_BITS = 64'h122;


    // regs and combs
    logic[290-1:0] rx_pack_comb[QUEUES];
    logic[QUEUES-1:0] l2_rx_ready_comb;
    logic[QUEUES-1:0] l2_tx_valid_comb;
    logic[QUEUES*DATA_WIDTH-1:0] l2_tx_data_comb;
    logic[QUEUES*DATA_BYTES-1:0] l2_tx_keep_comb;
    logic[QUEUES-1:0] l2_tx_sop_comb;
    logic[QUEUES-1:0] l2_tx_eop_comb;
    logic[QUEUES-1:0] rx_empty_comb;
    logic[QUEUES-1:0] tx_empty_comb;
    logic[QUEUES-1:0] tx_full_comb;
    logic[QUEUES*'h10-1:0] rx_length_comb;
    logic[QUEUES*'h10-1:0] rx_count_comb;
    logic[QUEUES*'h10-1:0] tx_count_comb;
    logic selected_rx_valid_comb;
    logic[256-1:0] selected_rx_data_comb;
    logic[32-1:0] selected_rx_keep_comb;
    logic selected_rx_sop_comb;
    logic selected_rx_eop_comb;
    logic protocol_error_comb;

    // members
    genvar __i;
    wire controller__host_control__awvalid_in;
    wire controller__host_control__awready_out;
    wire[32-1:0] controller__host_control__awaddr_in;
    wire[4-1:0] controller__host_control__awid_in;
    wire controller__host_control__wvalid_in;
    wire controller__host_control__wready_out;
    wire[256-1:0] controller__host_control__wdata_in;
    wire[256/'h8-1:0] controller__host_control__wstrb_in;
    wire controller__host_control__wlast_in;
    wire controller__host_control__bvalid_out;
    wire controller__host_control__bready_in;
    wire[4-1:0] controller__host_control__bid_out;
    wire controller__host_control__arvalid_in;
    wire controller__host_control__arready_out;
    wire[32-1:0] controller__host_control__araddr_in;
    wire[4-1:0] controller__host_control__arid_in;
    wire controller__host_control__rvalid_out;
    wire controller__host_control__rready_in;
    wire[256-1:0] controller__host_control__rdata_out;
    wire controller__host_control__rlast_out;
    wire[4-1:0] controller__host_control__rid_out;
    wire[QUEUES-1:0] controller__rx_empty_in;
    wire[QUEUES*'h10-1:0] controller__rx_packet_length_in;
    wire[QUEUES-1:0] controller__tx_full_in;
    wire[QUEUES*'h10-1:0] controller__rx_packet_count_in;
    wire[QUEUES*'h10-1:0] controller__tx_packet_count_in;
    wire controller__dma_command_valid_out;
    wire controller__dma_command_ready_in;
    wire controller__dma_command_direction_out;
    wire[3-1:0] controller__dma_command_queue_out;
    wire[64-1:0] controller__dma_command_address_out;
    wire[16-1:0] controller__dma_command_length_out;
    wire controller__dma_command_sop_out;
    wire controller__dma_command_eop_out;
    wire controller__dma_completion_valid_in;
    wire[3-1:0] controller__dma_completion_queue_in;
    wire controller__dma_completion_direction_in;
    wire[QUEUES-1:0] controller__rx_queue_empty_out;
    wire[$clog2('h400)-1:0] controller__rx_consumer_out;
    wire[$clog2('h400)-1:0] controller__tx_consumer_out;
    wire controller__protocol_error_out;
    Controller #(
        QUEUES
,       'h400
,       'h100
    ) controller (
        .system_clock(system_clock)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .host_control__awvalid_in(controller__host_control__awvalid_in)
,       .host_control__awready_out(controller__host_control__awready_out)
,       .host_control__awaddr_in(controller__host_control__awaddr_in)
,       .host_control__awid_in(controller__host_control__awid_in)
,       .host_control__wvalid_in(controller__host_control__wvalid_in)
,       .host_control__wready_out(controller__host_control__wready_out)
,       .host_control__wdata_in(controller__host_control__wdata_in)
,       .host_control__wstrb_in(controller__host_control__wstrb_in)
,       .host_control__wlast_in(controller__host_control__wlast_in)
,       .host_control__bvalid_out(controller__host_control__bvalid_out)
,       .host_control__bready_in(controller__host_control__bready_in)
,       .host_control__bid_out(controller__host_control__bid_out)
,       .host_control__arvalid_in(controller__host_control__arvalid_in)
,       .host_control__arready_out(controller__host_control__arready_out)
,       .host_control__araddr_in(controller__host_control__araddr_in)
,       .host_control__arid_in(controller__host_control__arid_in)
,       .host_control__rvalid_out(controller__host_control__rvalid_out)
,       .host_control__rready_in(controller__host_control__rready_in)
,       .host_control__rdata_out(controller__host_control__rdata_out)
,       .host_control__rlast_out(controller__host_control__rlast_out)
,       .host_control__rid_out(controller__host_control__rid_out)
,       .rx_empty_in(controller__rx_empty_in)
,       .rx_packet_length_in(controller__rx_packet_length_in)
,       .tx_full_in(controller__tx_full_in)
,       .rx_packet_count_in(controller__rx_packet_count_in)
,       .tx_packet_count_in(controller__tx_packet_count_in)
,       .dma_command_valid_out(controller__dma_command_valid_out)
,       .dma_command_ready_in(controller__dma_command_ready_in)
,       .dma_command_direction_out(controller__dma_command_direction_out)
,       .dma_command_queue_out(controller__dma_command_queue_out)
,       .dma_command_address_out(controller__dma_command_address_out)
,       .dma_command_length_out(controller__dma_command_length_out)
,       .dma_command_sop_out(controller__dma_command_sop_out)
,       .dma_command_eop_out(controller__dma_command_eop_out)
,       .dma_completion_valid_in(controller__dma_completion_valid_in)
,       .dma_completion_queue_in(controller__dma_completion_queue_in)
,       .dma_completion_direction_in(controller__dma_completion_direction_in)
,       .rx_queue_empty_out(controller__rx_queue_empty_out)
,       .rx_consumer_out(controller__rx_consumer_out)
,       .tx_consumer_out(controller__tx_consumer_out)
,       .protocol_error_out(controller__protocol_error_out)
    );
    wire master_dma__command_valid_in;
    wire master_dma__command_ready_out;
    wire master_dma__command_direction_in;
    wire[3-1:0] master_dma__command_queue_in;
    wire[64-1:0] master_dma__command_address_in;
    wire[16-1:0] master_dma__command_length_in;
    wire master_dma__command_sop_in;
    wire master_dma__command_eop_in;
    wire master_dma__queue_input_valid_in;
    wire[256-1:0] master_dma__queue_input_data_in;
    wire[256/'h8-1:0] master_dma__queue_input_keep_in;
    wire master_dma__queue_input_sop_in;
    wire master_dma__queue_input_eop_in;
    wire master_dma__queue_input_ready_out;
    wire master_dma__queue_output_valid_out;
    wire[256-1:0] master_dma__queue_output_data_out;
    wire[256/'h8-1:0] master_dma__queue_output_keep_out;
    wire master_dma__queue_output_sop_out;
    wire master_dma__queue_output_eop_out;
    wire master_dma__queue_output_ready_in;
    wire master_dma__host__awvalid_out;
    wire master_dma__host__awready_in;
    wire[64-1:0] master_dma__host__awaddr_out;
    wire[4-1:0] master_dma__host__awid_out;
    wire master_dma__host__wvalid_out;
    wire master_dma__host__wready_in;
    wire[256-1:0] master_dma__host__wdata_out;
    wire[256/'h8-1:0] master_dma__host__wstrb_out;
    wire master_dma__host__wlast_out;
    wire master_dma__host__bvalid_in;
    wire master_dma__host__bready_out;
    wire[4-1:0] master_dma__host__bid_in;
    wire master_dma__host__arvalid_out;
    wire master_dma__host__arready_in;
    wire[64-1:0] master_dma__host__araddr_out;
    wire[4-1:0] master_dma__host__arid_out;
    wire master_dma__host__rvalid_in;
    wire master_dma__host__rready_out;
    wire[256-1:0] master_dma__host__rdata_in;
    wire master_dma__host__rlast_in;
    wire[4-1:0] master_dma__host__rid_in;
    wire master_dma__busy_out;
    wire master_dma__completion_valid_out;
    wire[3-1:0] master_dma__active_queue_out;
    wire[3-1:0] master_dma__completion_queue_out;
    wire master_dma__completion_direction_out;
    wire[32-1:0] master_dma__completed_count_out;
    wire master_dma__protocol_error_out;
    MasterDMA #(
        64
,       256
,       4
,       16
    ) master_dma (
        .system_clock(system_clock)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .command_valid_in(master_dma__command_valid_in)
,       .command_ready_out(master_dma__command_ready_out)
,       .command_direction_in(master_dma__command_direction_in)
,       .command_queue_in(master_dma__command_queue_in)
,       .command_address_in(master_dma__command_address_in)
,       .command_length_in(master_dma__command_length_in)
,       .command_sop_in(master_dma__command_sop_in)
,       .command_eop_in(master_dma__command_eop_in)
,       .queue_input_valid_in(master_dma__queue_input_valid_in)
,       .queue_input_data_in(master_dma__queue_input_data_in)
,       .queue_input_keep_in(master_dma__queue_input_keep_in)
,       .queue_input_sop_in(master_dma__queue_input_sop_in)
,       .queue_input_eop_in(master_dma__queue_input_eop_in)
,       .queue_input_ready_out(master_dma__queue_input_ready_out)
,       .queue_output_valid_out(master_dma__queue_output_valid_out)
,       .queue_output_data_out(master_dma__queue_output_data_out)
,       .queue_output_keep_out(master_dma__queue_output_keep_out)
,       .queue_output_sop_out(master_dma__queue_output_sop_out)
,       .queue_output_eop_out(master_dma__queue_output_eop_out)
,       .queue_output_ready_in(master_dma__queue_output_ready_in)
,       .host__awvalid_out(master_dma__host__awvalid_out)
,       .host__awready_in(master_dma__host__awready_in)
,       .host__awaddr_out(master_dma__host__awaddr_out)
,       .host__awid_out(master_dma__host__awid_out)
,       .host__wvalid_out(master_dma__host__wvalid_out)
,       .host__wready_in(master_dma__host__wready_in)
,       .host__wdata_out(master_dma__host__wdata_out)
,       .host__wstrb_out(master_dma__host__wstrb_out)
,       .host__wlast_out(master_dma__host__wlast_out)
,       .host__bvalid_in(master_dma__host__bvalid_in)
,       .host__bready_out(master_dma__host__bready_out)
,       .host__bid_in(master_dma__host__bid_in)
,       .host__arvalid_out(master_dma__host__arvalid_out)
,       .host__arready_in(master_dma__host__arready_in)
,       .host__araddr_out(master_dma__host__araddr_out)
,       .host__arid_out(master_dma__host__arid_out)
,       .host__rvalid_in(master_dma__host__rvalid_in)
,       .host__rready_out(master_dma__host__rready_out)
,       .host__rdata_in(master_dma__host__rdata_in)
,       .host__rlast_in(master_dma__host__rlast_in)
,       .host__rid_in(master_dma__host__rid_in)
,       .busy_out(master_dma__busy_out)
,       .completion_valid_out(master_dma__completion_valid_out)
,       .active_queue_out(master_dma__active_queue_out)
,       .completion_queue_out(master_dma__completion_queue_out)
,       .completion_direction_out(master_dma__completion_direction_out)
,       .completed_count_out(master_dma__completed_count_out)
,       .protocol_error_out(master_dma__protocol_error_out)
    );
    wire rx_queue__write_valid_in[QUEUES];
    wire[256-1:0] rx_queue__write_data_in[QUEUES];
    wire[32-1:0] rx_queue__write_keep_in[QUEUES];
    wire rx_queue__write_sop_in[QUEUES];
    wire rx_queue__write_eop_in[QUEUES];
    wire rx_queue__write_ready_out[QUEUES];
    wire rx_queue__read_valid_out[QUEUES];
    wire[256-1:0] rx_queue__read_data_out[QUEUES];
    wire[32-1:0] rx_queue__read_keep_out[QUEUES];
    wire rx_queue__read_sop_out[QUEUES];
    wire rx_queue__read_eop_out[QUEUES];
    wire rx_queue__read_ready_in[QUEUES];
    wire rx_queue__empty_out[QUEUES];
    wire rx_queue__full_out[QUEUES];
    wire[16-1:0] rx_queue__packet_length_out[QUEUES];
    wire[$clog2(QUEUE_DEPTH + 'h1)-1:0] rx_queue__packet_count_out[QUEUES];
    wire rx_queue__protocol_error_out[QUEUES];
    wire rx_queue__clear_in[QUEUES];
    generate
    for (__i=0; __i < QUEUES; __i = __i + 1) begin
        RxQueue #(
        QUEUE_DEPTH
        ) rx_queue (
            .system_clock(system_clock)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .write_valid_in(rx_queue__write_valid_in[__i])
        ,           .write_data_in(rx_queue__write_data_in[__i])
        ,           .write_keep_in(rx_queue__write_keep_in[__i])
        ,           .write_sop_in(rx_queue__write_sop_in[__i])
        ,           .write_eop_in(rx_queue__write_eop_in[__i])
        ,           .write_ready_out(rx_queue__write_ready_out[__i])
        ,           .read_valid_out(rx_queue__read_valid_out[__i])
        ,           .read_data_out(rx_queue__read_data_out[__i])
        ,           .read_keep_out(rx_queue__read_keep_out[__i])
        ,           .read_sop_out(rx_queue__read_sop_out[__i])
        ,           .read_eop_out(rx_queue__read_eop_out[__i])
        ,           .read_ready_in(rx_queue__read_ready_in[__i])
        ,           .empty_out(rx_queue__empty_out[__i])
        ,           .full_out(rx_queue__full_out[__i])
        ,           .packet_length_out(rx_queue__packet_length_out[__i])
        ,           .packet_count_out(rx_queue__packet_count_out[__i])
        ,           .protocol_error_out(rx_queue__protocol_error_out[__i])
        ,           .clear_in(rx_queue__clear_in[__i])
        );
    end
    endgenerate
    wire tx_queue__write_valid_in[QUEUES];
    wire[256-1:0] tx_queue__write_data_in[QUEUES];
    wire[32-1:0] tx_queue__write_keep_in[QUEUES];
    wire tx_queue__write_sop_in[QUEUES];
    wire tx_queue__write_eop_in[QUEUES];
    wire tx_queue__write_ready_out[QUEUES];
    wire tx_queue__read_valid_out[QUEUES];
    wire[256-1:0] tx_queue__read_data_out[QUEUES];
    wire[32-1:0] tx_queue__read_keep_out[QUEUES];
    wire tx_queue__read_sop_out[QUEUES];
    wire tx_queue__read_eop_out[QUEUES];
    wire tx_queue__read_ready_in[QUEUES];
    wire tx_queue__empty_out[QUEUES];
    wire tx_queue__full_out[QUEUES];
    wire[16-1:0] tx_queue__packet_length_out[QUEUES];
    wire[$clog2(QUEUE_DEPTH + 'h1)-1:0] tx_queue__packet_count_out[QUEUES];
    wire tx_queue__protocol_error_out[QUEUES];
    wire tx_queue__clear_in[QUEUES];
    generate
    for (__i=0; __i < QUEUES; __i = __i + 1) begin
        TxQueue #(
        QUEUE_DEPTH
        ) tx_queue (
            .system_clock(system_clock)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .write_valid_in(tx_queue__write_valid_in[__i])
        ,           .write_data_in(tx_queue__write_data_in[__i])
        ,           .write_keep_in(tx_queue__write_keep_in[__i])
        ,           .write_sop_in(tx_queue__write_sop_in[__i])
        ,           .write_eop_in(tx_queue__write_eop_in[__i])
        ,           .write_ready_out(tx_queue__write_ready_out[__i])
        ,           .read_valid_out(tx_queue__read_valid_out[__i])
        ,           .read_data_out(tx_queue__read_data_out[__i])
        ,           .read_keep_out(tx_queue__read_keep_out[__i])
        ,           .read_sop_out(tx_queue__read_sop_out[__i])
        ,           .read_eop_out(tx_queue__read_eop_out[__i])
        ,           .read_ready_in(tx_queue__read_ready_in[__i])
        ,           .empty_out(tx_queue__empty_out[__i])
        ,           .full_out(tx_queue__full_out[__i])
        ,           .packet_length_out(tx_queue__packet_length_out[__i])
        ,           .packet_count_out(tx_queue__packet_count_out[__i])
        ,           .protocol_error_out(tx_queue__protocol_error_out[__i])
        ,           .clear_in(tx_queue__clear_in[__i])
        );
    end
    endgenerate
    wire rx_cdc__write_valid_in[QUEUES];
    wire[290-1:0] rx_cdc__write_data_in[QUEUES];
    wire rx_cdc__write_ready_out[QUEUES];
    wire rx_cdc__read_ready_in[QUEUES];
    wire rx_cdc__read_valid_out[QUEUES];
    wire[290-1:0] rx_cdc__read_data_out[QUEUES];
    generate
    for (__i=0; __i < QUEUES; __i = __i + 1) begin
        AsyncFifoNetToL2 #(
        290
,       16
        ) rx_cdc (
            .system_clock(system_clock)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .write_valid_in(rx_cdc__write_valid_in[__i])
        ,           .write_data_in(rx_cdc__write_data_in[__i])
        ,           .write_ready_out(rx_cdc__write_ready_out[__i])
        ,           .read_ready_in(rx_cdc__read_ready_in[__i])
        ,           .read_valid_out(rx_cdc__read_valid_out[__i])
        ,           .read_data_out(rx_cdc__read_data_out[__i])
        );
    end
    endgenerate
    wire tx_cdc__write_valid_in[QUEUES];
    wire[290-1:0] tx_cdc__write_data_in[QUEUES];
    wire tx_cdc__write_ready_out[QUEUES];
    wire tx_cdc__read_ready_in[QUEUES];
    wire tx_cdc__read_valid_out[QUEUES];
    wire[290-1:0] tx_cdc__read_data_out[QUEUES];
    generate
    for (__i=0; __i < QUEUES; __i = __i + 1) begin
        AsyncFifoL2ToNet #(
        290
,       16
        ) tx_cdc (
            .system_clock(system_clock)
        ,           .l2_clock(l2_clock)
        ,           .reset(reset)
        ,           .write_valid_in(tx_cdc__write_valid_in[__i])
        ,           .write_data_in(tx_cdc__write_data_in[__i])
        ,           .write_ready_out(tx_cdc__write_ready_out[__i])
        ,           .read_ready_in(tx_cdc__read_ready_in[__i])
        ,           .read_valid_out(tx_cdc__read_valid_out[__i])
        ,           .read_data_out(tx_cdc__read_data_out[__i])
        );
    end
    endgenerate

    // tmp variables


    always_comb begin : rx_pack_comb_func  // rx_pack_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            rx_pack_comb[queue] = 'h0;
            for (_bit='h0;_bit < DATA_WIDTH;_bit=_bit+1) begin
                rx_pack_comb[queue][_bit] = l2_rx_data_in[(queue*DATA_WIDTH) + _bit];
            end
            for (_bit='h0;_bit < DATA_BYTES;_bit=_bit+1) begin
                rx_pack_comb[queue][DATA_WIDTH + _bit] = l2_rx_keep_in[(queue*DATA_BYTES) + _bit];
            end
            rx_pack_comb[queue][DATA_WIDTH + DATA_BYTES] = l2_rx_sop_in[queue];
            rx_pack_comb[queue][(DATA_WIDTH + DATA_BYTES) + 'h1] = l2_rx_eop_in[queue];
        end
    end

    always_comb begin : l2_rx_ready_comb_func  // l2_rx_ready_comb_func
        logic[31:0] queue;
        l2_rx_ready_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            l2_rx_ready_comb[queue] = rx_cdc__write_ready_out[queue];
        end
    end

    always_comb begin : l2_tx_valid_comb_func  // l2_tx_valid_comb_func
        logic[31:0] queue;
        l2_tx_valid_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            l2_tx_valid_comb[queue] = tx_cdc__read_valid_out[queue];
        end
    end

    always_comb begin : l2_tx_data_comb_func  // l2_tx_data_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        l2_tx_data_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            for (_bit='h0;_bit < DATA_WIDTH;_bit=_bit+1) begin
                l2_tx_data_comb[(queue*DATA_WIDTH) + _bit] = tx_cdc__read_data_out[queue][_bit];
            end
        end
    end

    always_comb begin : l2_tx_keep_comb_func  // l2_tx_keep_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        l2_tx_keep_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            for (_bit='h0;_bit < DATA_BYTES;_bit=_bit+1) begin
                l2_tx_keep_comb[(queue*DATA_BYTES) + _bit] = tx_cdc__read_data_out[queue][DATA_WIDTH + _bit];
            end
        end
    end

    always_comb begin : l2_tx_sop_comb_func  // l2_tx_sop_comb_func
        logic[31:0] queue;
        l2_tx_sop_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            l2_tx_sop_comb[queue] = tx_cdc__read_data_out[queue][DATA_WIDTH + DATA_BYTES];
        end
    end

    always_comb begin : l2_tx_eop_comb_func  // l2_tx_eop_comb_func
        logic[31:0] queue;
        l2_tx_eop_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            l2_tx_eop_comb[queue] = tx_cdc__read_data_out[queue][(DATA_WIDTH + DATA_BYTES) + 'h1];
        end
    end

    always_comb begin : rx_empty_comb_func  // rx_empty_comb_func
        logic[31:0] queue;
        rx_empty_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            rx_empty_comb[queue] = rx_queue__empty_out[queue];
        end
    end

    always_comb begin : tx_empty_comb_func  // tx_empty_comb_func
        logic[31:0] queue;
        tx_empty_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            tx_empty_comb[queue] = tx_queue__empty_out[queue];
        end
    end

    always_comb begin : tx_full_comb_func  // tx_full_comb_func
        logic[31:0] queue;
        tx_full_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            tx_full_comb[queue] = tx_queue__full_out[queue];
        end
    end

    always_comb begin : rx_length_comb_func  // rx_length_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        rx_length_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            for (_bit='h0;_bit < 'h10;_bit=_bit+1) begin
                rx_length_comb[(queue*'h10) + _bit] = rx_queue__packet_length_out[queue][_bit];
            end
        end
    end

    always_comb begin : rx_count_comb_func  // rx_count_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        rx_count_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            for (_bit='h0;_bit < 'h10;_bit=_bit+1) begin
                if (_bit < $clog2((QUEUE_DEPTH + 'h1))) begin
                    rx_count_comb[(queue*'h10) + _bit] = rx_queue__packet_count_out[queue][_bit];
                end
            end
        end
    end

    always_comb begin : tx_count_comb_func  // tx_count_comb_func
        logic[31:0] queue;
        logic[31:0] _bit;
        tx_count_comb = 'h0;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            for (_bit='h0;_bit < 'h10;_bit=_bit+1) begin
                if (_bit < $clog2((QUEUE_DEPTH + 'h1))) begin
                    tx_count_comb[(queue*'h10) + _bit] = tx_queue__packet_count_out[queue][_bit];
                end
            end
        end
    end

    always_comb begin : protocol_error_comb_func  // protocol_error_comb_func
        logic[31:0] queue;
        protocol_error_comb=controller__protocol_error_out || master_dma__protocol_error_out;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
            protocol_error_comb=(protocol_error_comb || rx_queue__protocol_error_out[queue]) || tx_queue__protocol_error_out[queue];
        end
    end

    always_comb begin : selected_rx_valid_comb_func  // selected_rx_valid_comb_func
        selected_rx_valid_comb=rx_queue__read_valid_out[unsigned'(32'(master_dma__active_queue_out))];
    end

    always_comb begin : selected_rx_data_comb_func  // selected_rx_data_comb_func
        selected_rx_data_comb = rx_queue__read_data_out[unsigned'(32'(master_dma__active_queue_out))];
    end

    always_comb begin : selected_rx_keep_comb_func  // selected_rx_keep_comb_func
        selected_rx_keep_comb = rx_queue__read_keep_out[unsigned'(32'(master_dma__active_queue_out))];
    end

    always_comb begin : selected_rx_sop_comb_func  // selected_rx_sop_comb_func
        selected_rx_sop_comb=rx_queue__read_sop_out[unsigned'(32'(master_dma__active_queue_out))];
    end

    always_comb begin : selected_rx_eop_comb_func  // selected_rx_eop_comb_func
        selected_rx_eop_comb=rx_queue__read_eop_out[unsigned'(32'(master_dma__active_queue_out))];
    end

    generate  // _assign
        genvar gqueue;
        for (gqueue='h0;gqueue < QUEUES;gqueue=gqueue+1) begin
            assign rx_cdc__write_valid_in[gqueue] = l2_rx_valid_in[gqueue];
            assign rx_cdc__write_data_in[gqueue] = rx_pack_comb[gqueue];
            assign tx_cdc__read_ready_in[gqueue] = l2_tx_ready_in[gqueue];
            assign rx_queue__write_valid_in[gqueue] = rx_cdc__read_valid_out[gqueue];
            assign rx_queue__write_data_in[gqueue] = rx_cdc__read_data_out[gqueue]['h0 +:256];
            assign rx_queue__write_keep_in[gqueue] = rx_cdc__read_data_out[gqueue]['h100 +:32];
            assign rx_queue__write_sop_in[gqueue] = rx_cdc__read_data_out[gqueue]['h120];
            assign rx_queue__write_eop_in[gqueue] = rx_cdc__read_data_out[gqueue]['h121];
            assign rx_queue__read_ready_in[gqueue] = master_dma__queue_input_ready_out && (unsigned'(32'(master_dma__active_queue_out)) == gqueue);
            assign rx_queue__clear_in[gqueue] = 0;
            assign rx_cdc__read_ready_in[gqueue] = rx_queue__write_ready_out[gqueue];
            assign tx_queue__write_valid_in[gqueue] = master_dma__queue_output_valid_out && (unsigned'(32'(master_dma__active_queue_out)) == gqueue);
            assign tx_queue__write_data_in[gqueue] = master_dma__queue_output_data_out;
            assign tx_queue__write_keep_in[gqueue] = master_dma__queue_output_keep_out;
            assign tx_queue__write_sop_in[gqueue] = master_dma__queue_output_sop_out;
            assign tx_queue__write_eop_in[gqueue] = master_dma__queue_output_eop_out;
            assign tx_queue__read_ready_in[gqueue] = tx_cdc__write_ready_out[gqueue];
            assign tx_queue__clear_in[gqueue] = 0;
            assign tx_cdc__write_valid_in[gqueue] = tx_queue__read_valid_out[gqueue];
            assign tx_cdc__write_data_in[gqueue] = {unsigned'(1'(unsigned'(1'(tx_queue__read_eop_out[gqueue])))), unsigned'(1'(unsigned'(1'(tx_queue__read_sop_out[gqueue])))), tx_queue__read_keep_out[gqueue], tx_queue__read_data_out[gqueue]};
        end
        assign controller__rx_empty_in = rx_empty_comb;
        assign controller__rx_packet_length_in = rx_length_comb;
        assign controller__tx_full_in = tx_full_comb;
        assign controller__rx_packet_count_in = rx_count_comb;
        assign controller__tx_packet_count_in = tx_count_comb;
        assign controller__dma_command_ready_in = master_dma__command_ready_out;
        assign controller__dma_completion_valid_in = master_dma__completion_valid_out;
        assign controller__dma_completion_queue_in = master_dma__completion_queue_out;
        assign controller__dma_completion_direction_in = master_dma__completion_direction_out;
        assign master_dma__command_valid_in = controller__dma_command_valid_out;
        assign master_dma__command_direction_in = controller__dma_command_direction_out;
        assign master_dma__command_queue_in = controller__dma_command_queue_out;
        assign master_dma__command_address_in = controller__dma_command_address_out;
        assign master_dma__command_length_in = controller__dma_command_length_out;
        assign master_dma__command_sop_in = controller__dma_command_sop_out;
        assign master_dma__command_eop_in = controller__dma_command_eop_out;
        assign master_dma__queue_input_valid_in = selected_rx_valid_comb;
        assign master_dma__queue_input_data_in = selected_rx_data_comb;
        assign master_dma__queue_input_keep_in = selected_rx_keep_comb;
        assign master_dma__queue_input_sop_in = selected_rx_sop_comb;
        assign master_dma__queue_input_eop_in = selected_rx_eop_comb;
        assign master_dma__queue_output_ready_in = tx_queue__write_ready_out[unsigned'(32'(master_dma__active_queue_out))];
        assign controller__host_control__awvalid_in = host_control__awvalid_in;
        assign controller__host_control__awaddr_in = host_control__awaddr_in;
        assign controller__host_control__awid_in = host_control__awid_in;
        assign controller__host_control__wvalid_in = host_control__wvalid_in;
        assign controller__host_control__wdata_in = host_control__wdata_in;
        assign controller__host_control__wstrb_in = host_control__wstrb_in;
        assign controller__host_control__wlast_in = host_control__wlast_in;
        assign controller__host_control__bready_in = host_control__bready_in;
        assign controller__host_control__arvalid_in = host_control__arvalid_in;
        assign controller__host_control__araddr_in = host_control__araddr_in;
        assign controller__host_control__arid_in = host_control__arid_in;
        assign controller__host_control__rready_in = host_control__rready_in;
        assign host_control__awready_out = controller__host_control__awready_out;
        assign host_control__wready_out = controller__host_control__wready_out;
        assign host_control__bvalid_out = controller__host_control__bvalid_out;
        assign host_control__bid_out = controller__host_control__bid_out;
        assign host_control__arready_out = controller__host_control__arready_out;
        assign host_control__rvalid_out = controller__host_control__rvalid_out;
        assign host_control__rdata_out = controller__host_control__rdata_out;
        assign host_control__rlast_out = controller__host_control__rlast_out;
        assign host_control__rid_out = controller__host_control__rid_out;
        assign host_dma__awvalid_out = master_dma__host__awvalid_out;
        assign host_dma__awaddr_out = master_dma__host__awaddr_out;
        assign host_dma__awid_out = master_dma__host__awid_out;
        assign host_dma__wvalid_out = master_dma__host__wvalid_out;
        assign host_dma__wdata_out = master_dma__host__wdata_out;
        assign host_dma__wstrb_out = master_dma__host__wstrb_out;
        assign host_dma__wlast_out = master_dma__host__wlast_out;
        assign host_dma__bready_out = master_dma__host__bready_out;
        assign host_dma__arvalid_out = master_dma__host__arvalid_out;
        assign host_dma__araddr_out = master_dma__host__araddr_out;
        assign host_dma__arid_out = master_dma__host__arid_out;
        assign host_dma__rready_out = master_dma__host__rready_out;
        assign master_dma__host__awready_in = host_dma__awready_in;
        assign master_dma__host__wready_in = host_dma__wready_in;
        assign master_dma__host__bvalid_in = host_dma__bvalid_in;
        assign master_dma__host__bid_in = host_dma__bid_in;
        assign master_dma__host__arready_in = host_dma__arready_in;
        assign master_dma__host__rvalid_in = host_dma__rvalid_in;
        assign master_dma__host__rdata_in = host_dma__rdata_in;
        assign master_dma__host__rlast_in = host_dma__rlast_in;
        assign master_dma__host__rid_in = host_dma__rid_in;
        assign l2_rx_ready_out = l2_rx_ready_comb;
        assign l2_tx_valid_out = l2_tx_valid_comb;
        assign l2_tx_data_out = l2_tx_data_comb;
        assign l2_tx_keep_out = l2_tx_keep_comb;
        assign l2_tx_sop_out = l2_tx_sop_comb;
        assign l2_tx_eop_out = l2_tx_eop_comb;
        assign rx_queue_empty_out = rx_empty_comb;
        assign tx_queue_empty_out = tx_empty_comb;
        assign protocol_error_out = protocol_error_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] queue;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
        logic[31:0] queue;
        for (queue='h0;queue < QUEUES;queue=queue+1) begin
        end
    end
    endtask

    always_ff @(posedge system_clock) begin

        _work(reset);

    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
