`default_nettype none

import Predef_pkg::*;
import PacketDMA17_14_64_32_4_256_31_32_64_Command_pkg::*;
import PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::*;
import PacketDmaState_pkg::*;
import PacketDmaError_pkg::*;
import PacketDmaOperation_pkg::*;
import PacketDmaPrefetchState_pkg::*;
import PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::*;
import PacketDMA_Command_pkg::*;
import PacketDMA_Register_pkg::*;
import PacketDMA_BackingState_pkg::*;


module PacketDMA #(
    parameter HANDLE_BITS = 'h11
,   parameter FRAME_LENGTH_BITS = 'hE
,   parameter CMD_DEPTH = 'h8
,   parameter AXI_ADDR_WIDTH = 'h20
,   parameter AXI_ID_WIDTH = 'h4
,   parameter AXI_DATA_WIDTH = 'h100
,   parameter BACKING_ADDR_WIDTH = 'h1F
,   parameter BACKING_DEPTH = 'h40
,   parameter CLEAR_DEPTH = 'h200
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire mmio__awvalid_in
,   output wire mmio__awready_out
,   input wire[32-1:0] mmio__awaddr_in
,   input wire[4-1:0] mmio__awid_in
,   input wire mmio__wvalid_in
,   output wire mmio__wready_out
,   input wire[256-1:0] mmio__wdata_in
,   input wire[256/'h8-1:0] mmio__wstrb_in
,   input wire mmio__wlast_in
,   output wire mmio__bvalid_out
,   input wire mmio__bready_in
,   output wire[4-1:0] mmio__bid_out
,   input wire mmio__arvalid_in
,   output wire mmio__arready_out
,   input wire[32-1:0] mmio__araddr_in
,   input wire[4-1:0] mmio__arid_in
,   output wire mmio__rvalid_out
,   input wire mmio__rready_in
,   output wire[256-1:0] mmio__rdata_out
,   output wire mmio__rlast_out
,   output wire[4-1:0] mmio__rid_out
,   output wire l2_dma__awvalid_out
,   input wire l2_dma__awready_in
,   output wire[32-1:0] l2_dma__awaddr_out
,   output wire[4-1:0] l2_dma__awid_out
,   output wire l2_dma__wvalid_out
,   input wire l2_dma__wready_in
,   output wire[256-1:0] l2_dma__wdata_out
,   output wire[256/'h8-1:0] l2_dma__wstrb_out
,   output wire l2_dma__wlast_out
,   input wire l2_dma__bvalid_in
,   output wire l2_dma__bready_out
,   input wire[4-1:0] l2_dma__bid_in
,   output wire l2_dma__arvalid_out
,   input wire l2_dma__arready_in
,   output wire[32-1:0] l2_dma__araddr_out
,   output wire[4-1:0] l2_dma__arid_out
,   input wire l2_dma__rvalid_in
,   output wire l2_dma__rready_out
,   input wire[256-1:0] l2_dma__rdata_in
,   input wire l2_dma__rlast_in
,   input wire[4-1:0] l2_dma__rid_in
,   output wire backing_dma__awvalid_out
,   input wire backing_dma__awready_in
,   output wire[31-1:0] backing_dma__awaddr_out
,   output wire[4-1:0] backing_dma__awid_out
,   output wire backing_dma__wvalid_out
,   input wire backing_dma__wready_in
,   output wire[256-1:0] backing_dma__wdata_out
,   output wire[256/'h8-1:0] backing_dma__wstrb_out
,   output wire backing_dma__wlast_out
,   input wire backing_dma__bvalid_in
,   output wire backing_dma__bready_out
,   input wire[4-1:0] backing_dma__bid_in
,   output wire backing_dma__arvalid_out
,   input wire backing_dma__arready_in
,   output wire[31-1:0] backing_dma__araddr_out
,   output wire[4-1:0] backing_dma__arid_out
,   input wire backing_dma__rvalid_in
,   output wire backing_dma__rready_out
,   input wire[256-1:0] backing_dma__rdata_in
,   input wire backing_dma__rlast_in
,   input wire[4-1:0] backing_dma__rid_in
,   output wire l2_line_valid_out
,   output wire[AXI_ADDR_WIDTH-1:0] l2_line_addr_out
,   output wire[AXI_DATA_WIDTH-1:0] l2_line_data_out
,   output wire[AXI_BYTES-1:0] l2_line_keep_out
,   output wire l2_line_eop_out
,   input wire l2_line_ready_in
,   output wire rx_read_valid_out
,   output wire[HANDLE_BITS-1:0] rx_read_handle_out
,   output wire[FRAME_LENGTH_BITS-1:0] rx_read_length_out
,   input wire rx_read_ready_in
,   input wire rx_valid_in
,   input wire[AXI_DATA_WIDTH-1:0] rx_data_in
,   input wire[AXI_BYTES-1:0] rx_keep_in
,   input wire rx_sop_in
,   input wire rx_eop_in
,   output wire rx_ready_out
,   input wire system_rx_valid_in
,   input wire[AXI_DATA_WIDTH-1:0] system_rx_data_in
,   input wire[AXI_BYTES-1:0] system_rx_keep_in
,   input wire system_rx_sop_in
,   input wire system_rx_eop_in
,   output wire system_rx_ready_out
,   output wire system_tx_valid_out
,   output wire[AXI_DATA_WIDTH-1:0] system_tx_data_out
,   output wire[AXI_BYTES-1:0] system_tx_keep_out
,   output wire system_tx_sop_out
,   output wire system_tx_eop_out
,   input wire system_tx_ready_in
,   output wire network_tx_valid_out
,   output wire[AXI_DATA_WIDTH-1:0] network_tx_data_out
,   output wire[AXI_BYTES-1:0] network_tx_keep_out
,   output wire network_tx_sop_out
,   output wire network_tx_eop_out
,   input wire network_tx_ready_in
,   output wire[8-1:0] network_tx_port_out
,   output wire busy_out
,   output wire command_ready_out
,   output wire descriptor_command_ready_out
,   input wire descriptor_command_valid_in
,   input wire[HANDLE_BITS-1:0] descriptor_command_handle_in
,   input wire[FRAME_LENGTH_BITS-1:0] descriptor_command_length_in
,   input wire descriptor_command_system_in
,   input wire descriptor_command_cache_in
,   input wire descriptor_command_network_in
,   input wire[8-1:0] descriptor_command_network_port_in
,   input wire[32-1:0] descriptor_command_destination_in
,   output wire[32-1:0] completed_count_out
,   output wire[32-1:0] cache_completed_count_out
,   output wire[32-1:0] command_completed_count_out
,   output wire[32-1:0] clear_completed_count_out
,   output wire[BACKING_COUNT_BITS-1:0] backing_pending_count_out
,   output wire[32-1:0] backing_completed_beat_count_out
,   output wire[2-1:0] last_operation_out
,   output wire protocol_error_out
,   output wire[4-1:0] protocol_error_reason_out
);
    localparam  AXI_BYTES = AXI_DATA_WIDTH/'h8;
    localparam  CMD_PTR_BITS = (CMD_DEPTH<='h1) ? ('h1) : ($clog2(CMD_DEPTH));
    localparam  CMD_COUNT_BITS = $clog2(CMD_DEPTH + 'h1);
    localparam  BACKING_PTR_BITS = (BACKING_DEPTH<='h1) ? ('h1) : ($clog2(BACKING_DEPTH));
    localparam  BACKING_COUNT_BITS = $clog2(BACKING_DEPTH + 'h1);
    localparam  CLEAR_PTR_BITS = (CLEAR_DEPTH<='h1) ? ('h1) : ($clog2(CLEAR_DEPTH));
    localparam  CLEAR_COUNT_BITS = $clog2(CLEAR_DEPTH + 'h1);
    localparam  COMMAND_PUSH = 'h1;
    localparam  FLAG_OPERATION_MASK = 'h3;
    localparam  FLAG_CACHE_ALLOCATE = 'h4;
    localparam  FLAG_NETWORK_DISCARD = 'h8;
    localparam  FLAG_NETWORK_SYSTEM = 'h10;
    localparam  FLAG_RING_SOURCE = 'h20;
    localparam  FLAG_CLEAR_SOURCE_AFTER_TX = 'h40;
    localparam  FLAG_NETWORK_FORWARD = 'h80;
    localparam  STATUS_BUSY = 'h1;
    localparam  STATUS_CMD_READY = 'h2;
    localparam  STATUS_ERROR = 'h4;


    // regs and combs
    reg[CMD_PTR_BITS-1:0] command_head_reg;
    reg[CMD_PTR_BITS-1:0] command_tail_reg;
    reg[CMD_COUNT_BITS-1:0] command_count_reg;
    reg command_write_pending_reg;
    reg[HANDLE_BITS-1:0] command_write_handle_reg;
    reg[FRAME_LENGTH_BITS-1:0] command_write_length_reg;
    reg[32-1:0] command_write_source_reg;
    reg[32-1:0] command_write_destination_reg;
    reg[8-1:0] command_write_flags_reg;
    reg[8-1:0] command_write_network_port_reg;
    reg[HANDLE_BITS-1:0] stage_handle_reg;
    reg[FRAME_LENGTH_BITS-1:0] stage_length_reg;
    reg[32-1:0] stage_source_reg;
    reg[32-1:0] stage_destination_reg;
    reg[8-1:0] stage_flags_reg;
    reg[8-1:0] stage_network_port_reg;
    reg stage_command_armed_reg;
    reg[8-1:0] state_reg;
    reg[2-1:0] operation_reg;
    reg[8-1:0] active_flags_reg;
    reg[8-1:0] active_network_port_reg;
    reg[AXI_ADDR_WIDTH-1:0] source_reg;
    reg[AXI_ADDR_WIDTH-1:0] source_base_reg;
    reg[AXI_ADDR_WIDTH-1:0] destination_reg;
    reg[FRAME_LENGTH_BITS-1:0] remaining_reg;
    reg[AXI_DATA_WIDTH-1:0] beat_data_reg;
    reg[AXI_BYTES-1:0] beat_keep_reg;
    reg beat_sop_reg;
    reg beat_eop_reg;
    reg first_beat_reg;
    reg[32-1:0] completed_reg;
    reg[32-1:0] cache_completed_reg;
    reg[32-1:0] command_completed_reg;
    reg[32-1:0] command_issued_reg;
    reg[8-1:0] command_lock_reg;
    reg[32-1:0] clear_completed_reg;
    reg[BACKING_ADDR_WIDTH-1:0] clear_address_reg;
    reg clear_notify_armed_reg;
    reg[4-1:0] cache_invalidate_count_reg;
    reg[2-1:0] last_operation_reg;
    reg protocol_error_reg;
    reg[4-1:0] protocol_error_reason_reg;
    reg[2-1:0] prefetch_state_reg;
    reg[HANDLE_BITS-1:0] prefetch_handle_reg;
    reg[FRAME_LENGTH_BITS-1:0] prefetch_length_reg;
    reg[AXI_ADDR_WIDTH-1:0] prefetch_destination_reg;
    reg[FRAME_LENGTH_BITS-1:0] prefetch_remaining_reg;
    reg prefetch_first_reg;
    reg[AXI_ADDR_WIDTH-1:0] write_addr_reg;
    reg[AXI_ID_WIDTH-1:0] write_id_reg;
    reg write_addr_valid_reg;
    reg write_response_valid_reg;
    reg write_aw_seen_reg;
    reg[AXI_ADDR_WIDTH-1:0] write_aw_seen_addr_reg;
    reg[AXI_ID_WIDTH-1:0] write_aw_seen_id_reg;
    reg[AXI_ID_WIDTH-1:0] read_id_reg;
    reg[AXI_ADDR_WIDTH-1:0] read_addr_reg;
    reg read_pending_reg;
    reg[AXI_DATA_WIDTH-1:0] read_data_reg;
    reg read_valid_reg;
    reg[BACKING_PTR_BITS-1:0] backing_head_reg;
    reg[BACKING_PTR_BITS-1:0] backing_tail_reg;
    reg[BACKING_COUNT_BITS-1:0] backing_count_reg;
    reg[2-1:0] backing_state_reg;
    reg[32-1:0] backing_completed_reg;
    reg[CLEAR_PTR_BITS-1:0] post_clear_head_reg;
    reg[CLEAR_PTR_BITS-1:0] post_clear_tail_reg;
    reg[CLEAR_COUNT_BITS-1:0] post_clear_count_reg;
    logic[HANDLE_BITS-1:0] current_handle_comb;
    logic[FRAME_LENGTH_BITS-1:0] current_length_comb;
    logic[AXI_BYTES-1:0] output_keep_comb;
    logic backing_memory_write_comb;
    logic[BACKING_ADDR_WIDTH-1:0] backing_address_write_data_comb;
    logic[AXI_DATA_WIDTH-1:0] backing_data_write_data_comb;
    logic[AXI_BYTES-1:0] backing_keep_write_data_comb;
    logic[1-1:0] backing_clear_write_data_comb;
    logic post_clear_memory_write_comb;
    logic rx_l2_line_selected_comb;
;
    logic clear_l2_line_selected_comb;
;

    // members
    wire[$clog2(CMD_DEPTH)-1:0] command_handle_mem__write_addr_in;
    wire command_handle_mem__write_in;
    wire[HANDLE_BITS-1:0] command_handle_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_handle_mem__read_addr_in;
    wire[HANDLE_BITS-1:0] command_handle_mem__read_data_out;
    AsyncReadRam #(
        HANDLE_BITS
,       CMD_DEPTH
    ) command_handle_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_handle_mem__write_addr_in)
,       .write_in(command_handle_mem__write_in)
,       .write_data_in(command_handle_mem__write_data_in)
,       .read_addr_in(command_handle_mem__read_addr_in)
,       .read_data_out(command_handle_mem__read_data_out)
    );
    wire[$clog2(CMD_DEPTH)-1:0] command_length_mem__write_addr_in;
    wire command_length_mem__write_in;
    wire[FRAME_LENGTH_BITS-1:0] command_length_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_length_mem__read_addr_in;
    wire[FRAME_LENGTH_BITS-1:0] command_length_mem__read_data_out;
    AsyncReadRam #(
        FRAME_LENGTH_BITS
,       CMD_DEPTH
    ) command_length_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_length_mem__write_addr_in)
,       .write_in(command_length_mem__write_in)
,       .write_data_in(command_length_mem__write_data_in)
,       .read_addr_in(command_length_mem__read_addr_in)
,       .read_data_out(command_length_mem__read_data_out)
    );
    wire[$clog2(CMD_DEPTH)-1:0] command_source_mem__write_addr_in;
    wire command_source_mem__write_in;
    wire['h20-1:0] command_source_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_source_mem__read_addr_in;
    wire['h20-1:0] command_source_mem__read_data_out;
    AsyncReadRam #(
        'h20
,       CMD_DEPTH
    ) command_source_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_source_mem__write_addr_in)
,       .write_in(command_source_mem__write_in)
,       .write_data_in(command_source_mem__write_data_in)
,       .read_addr_in(command_source_mem__read_addr_in)
,       .read_data_out(command_source_mem__read_data_out)
    );
    wire[$clog2(CMD_DEPTH)-1:0] command_destination_mem__write_addr_in;
    wire command_destination_mem__write_in;
    wire['h20-1:0] command_destination_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_destination_mem__read_addr_in;
    wire['h20-1:0] command_destination_mem__read_data_out;
    AsyncReadRam #(
        'h20
,       CMD_DEPTH
    ) command_destination_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_destination_mem__write_addr_in)
,       .write_in(command_destination_mem__write_in)
,       .write_data_in(command_destination_mem__write_data_in)
,       .read_addr_in(command_destination_mem__read_addr_in)
,       .read_data_out(command_destination_mem__read_data_out)
    );
    wire[$clog2(CMD_DEPTH)-1:0] command_flags_mem__write_addr_in;
    wire command_flags_mem__write_in;
    wire['h8-1:0] command_flags_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_flags_mem__read_addr_in;
    wire['h8-1:0] command_flags_mem__read_data_out;
    AsyncReadRam #(
        'h8
,       CMD_DEPTH
    ) command_flags_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_flags_mem__write_addr_in)
,       .write_in(command_flags_mem__write_in)
,       .write_data_in(command_flags_mem__write_data_in)
,       .read_addr_in(command_flags_mem__read_addr_in)
,       .read_data_out(command_flags_mem__read_data_out)
    );
    wire[$clog2(CMD_DEPTH)-1:0] command_network_port_mem__write_addr_in;
    wire command_network_port_mem__write_in;
    wire['h8-1:0] command_network_port_mem__write_data_in;
    wire[$clog2(CMD_DEPTH)-1:0] command_network_port_mem__read_addr_in;
    wire['h8-1:0] command_network_port_mem__read_data_out;
    AsyncReadRam #(
        'h8
,       CMD_DEPTH
    ) command_network_port_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(command_network_port_mem__write_addr_in)
,       .write_in(command_network_port_mem__write_in)
,       .write_data_in(command_network_port_mem__write_data_in)
,       .read_addr_in(command_network_port_mem__read_addr_in)
,       .read_data_out(command_network_port_mem__read_data_out)
    );
    wire[$clog2(BACKING_DEPTH)-1:0] backing_address_mem__write_addr_in;
    wire backing_address_mem__write_in;
    wire[BACKING_ADDR_WIDTH-1:0] backing_address_mem__write_data_in;
    wire[$clog2(BACKING_DEPTH)-1:0] backing_address_mem__read_addr_in;
    wire[BACKING_ADDR_WIDTH-1:0] backing_address_mem__read_data_out;
    AsyncReadRam #(
        BACKING_ADDR_WIDTH
,       BACKING_DEPTH
    ) backing_address_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(backing_address_mem__write_addr_in)
,       .write_in(backing_address_mem__write_in)
,       .write_data_in(backing_address_mem__write_data_in)
,       .read_addr_in(backing_address_mem__read_addr_in)
,       .read_data_out(backing_address_mem__read_data_out)
    );
    wire[$clog2(BACKING_DEPTH)-1:0] backing_data_mem__write_addr_in;
    wire backing_data_mem__write_in;
    wire[AXI_DATA_WIDTH-1:0] backing_data_mem__write_data_in;
    wire[$clog2(BACKING_DEPTH)-1:0] backing_data_mem__read_addr_in;
    wire[AXI_DATA_WIDTH-1:0] backing_data_mem__read_data_out;
    AsyncReadRam #(
        AXI_DATA_WIDTH
,       BACKING_DEPTH
    ) backing_data_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(backing_data_mem__write_addr_in)
,       .write_in(backing_data_mem__write_in)
,       .write_data_in(backing_data_mem__write_data_in)
,       .read_addr_in(backing_data_mem__read_addr_in)
,       .read_data_out(backing_data_mem__read_data_out)
    );
    wire[$clog2(BACKING_DEPTH)-1:0] backing_keep_mem__write_addr_in;
    wire backing_keep_mem__write_in;
    wire[AXI_BYTES-1:0] backing_keep_mem__write_data_in;
    wire[$clog2(BACKING_DEPTH)-1:0] backing_keep_mem__read_addr_in;
    wire[AXI_BYTES-1:0] backing_keep_mem__read_data_out;
    AsyncReadRam #(
        AXI_BYTES
,       BACKING_DEPTH
    ) backing_keep_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(backing_keep_mem__write_addr_in)
,       .write_in(backing_keep_mem__write_in)
,       .write_data_in(backing_keep_mem__write_data_in)
,       .read_addr_in(backing_keep_mem__read_addr_in)
,       .read_data_out(backing_keep_mem__read_data_out)
    );
    wire[$clog2(BACKING_DEPTH)-1:0] backing_clear_mem__write_addr_in;
    wire backing_clear_mem__write_in;
    wire['h1-1:0] backing_clear_mem__write_data_in;
    wire[$clog2(BACKING_DEPTH)-1:0] backing_clear_mem__read_addr_in;
    wire['h1-1:0] backing_clear_mem__read_data_out;
    AsyncReadRam #(
        'h1
,       BACKING_DEPTH
    ) backing_clear_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(backing_clear_mem__write_addr_in)
,       .write_in(backing_clear_mem__write_in)
,       .write_data_in(backing_clear_mem__write_data_in)
,       .read_addr_in(backing_clear_mem__read_addr_in)
,       .read_data_out(backing_clear_mem__read_data_out)
    );
    wire[$clog2(CLEAR_DEPTH)-1:0] post_clear_mem__write_addr_in;
    wire post_clear_mem__write_in;
    wire[BACKING_ADDR_WIDTH-1:0] post_clear_mem__write_data_in;
    wire[$clog2(CLEAR_DEPTH)-1:0] post_clear_mem__read_addr_in;
    wire[BACKING_ADDR_WIDTH-1:0] post_clear_mem__read_data_out;
    AsyncReadRam #(
        BACKING_ADDR_WIDTH
,       CLEAR_DEPTH
    ) post_clear_mem (
        .clk(clk)
,       .l2_clock(l2_clock)
,       .reset(reset)
,       .write_addr_in(post_clear_mem__write_addr_in)
,       .write_in(post_clear_mem__write_in)
,       .write_data_in(post_clear_mem__write_data_in)
,       .read_addr_in(post_clear_mem__read_addr_in)
,       .read_data_out(post_clear_mem__read_data_out)
    );

    // tmp variables
    logic[CMD_PTR_BITS-1:0] command_head_reg_tmp;
    logic[CMD_PTR_BITS-1:0] command_tail_reg_tmp;
    logic[CMD_COUNT_BITS-1:0] command_count_reg_tmp;
    logic command_write_pending_reg_tmp;
    logic[HANDLE_BITS-1:0] command_write_handle_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] command_write_length_reg_tmp;
    logic[32-1:0] command_write_source_reg_tmp;
    logic[32-1:0] command_write_destination_reg_tmp;
    logic[8-1:0] command_write_flags_reg_tmp;
    logic[8-1:0] command_write_network_port_reg_tmp;
    logic[HANDLE_BITS-1:0] stage_handle_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] stage_length_reg_tmp;
    logic[32-1:0] stage_source_reg_tmp;
    logic[32-1:0] stage_destination_reg_tmp;
    logic[8-1:0] stage_flags_reg_tmp;
    logic[8-1:0] stage_network_port_reg_tmp;
    logic stage_command_armed_reg_tmp;
    logic[8-1:0] state_reg_tmp;
    logic[2-1:0] operation_reg_tmp;
    logic[8-1:0] active_flags_reg_tmp;
    logic[8-1:0] active_network_port_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] source_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] source_base_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] destination_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] remaining_reg_tmp;
    logic[AXI_DATA_WIDTH-1:0] beat_data_reg_tmp;
    logic[AXI_BYTES-1:0] beat_keep_reg_tmp;
    logic beat_sop_reg_tmp;
    logic beat_eop_reg_tmp;
    logic first_beat_reg_tmp;
    logic[32-1:0] completed_reg_tmp;
    logic[32-1:0] cache_completed_reg_tmp;
    logic[32-1:0] command_completed_reg_tmp;
    logic[32-1:0] command_issued_reg_tmp;
    logic[8-1:0] command_lock_reg_tmp;
    logic[32-1:0] clear_completed_reg_tmp;
    logic[BACKING_ADDR_WIDTH-1:0] clear_address_reg_tmp;
    logic clear_notify_armed_reg_tmp;
    logic[4-1:0] cache_invalidate_count_reg_tmp;
    logic[2-1:0] last_operation_reg_tmp;
    logic protocol_error_reg_tmp;
    logic[4-1:0] protocol_error_reason_reg_tmp;
    logic[2-1:0] prefetch_state_reg_tmp;
    logic[HANDLE_BITS-1:0] prefetch_handle_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] prefetch_length_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] prefetch_destination_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] prefetch_remaining_reg_tmp;
    logic prefetch_first_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] write_addr_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] write_id_reg_tmp;
    logic write_addr_valid_reg_tmp;
    logic write_response_valid_reg_tmp;
    logic write_aw_seen_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] write_aw_seen_addr_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] write_aw_seen_id_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] read_id_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] read_addr_reg_tmp;
    logic read_pending_reg_tmp;
    logic[AXI_DATA_WIDTH-1:0] read_data_reg_tmp;
    logic read_valid_reg_tmp;
    logic[BACKING_PTR_BITS-1:0] backing_head_reg_tmp;
    logic[BACKING_PTR_BITS-1:0] backing_tail_reg_tmp;
    logic[BACKING_COUNT_BITS-1:0] backing_count_reg_tmp;
    logic[2-1:0] backing_state_reg_tmp;
    logic[32-1:0] backing_completed_reg_tmp;
    logic[CLEAR_PTR_BITS-1:0] post_clear_head_reg_tmp;
    logic[CLEAR_PTR_BITS-1:0] post_clear_tail_reg_tmp;
    logic[CLEAR_COUNT_BITS-1:0] post_clear_count_reg_tmp;


    function PacketDMA17_14_64_32_4_256_31_32_64_Command current_command ();
        PacketDMA17_14_64_32_4_256_31_32_64_Command command;
        command = 0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            command.handle = unsigned'(32'(command_handle_mem__read_data_out));
            command.length = unsigned'(32'(command_length_mem__read_data_out));
            command.source = unsigned'(32'(unsigned'(32'(command_source_mem__read_data_out))));
            command.destination = unsigned'(32'(unsigned'(32'(command_destination_mem__read_data_out))));
            command.flags = unsigned'(8'(unsigned'(32'(command_flags_mem__read_data_out))));
            command.network_port = unsigned'(32'(command_network_port_mem__read_data_out));
        end
        return command;
    endfunction

    always_comb begin : current_handle_comb_func  // current_handle_comb_func
        current_handle_comb = 'h0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            current_handle_comb = unsigned'(32'(command_handle_mem__read_data_out));
        end
    end

    always_comb begin : current_length_comb_func  // current_length_comb_func
        current_length_comb = 'h0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            current_length_comb = unsigned'(32'(command_length_mem__read_data_out));
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[31:0] _byte;
        output_keep_comb = 'h0;
        for (_byte='h0;_byte < AXI_BYTES;_byte=_byte+1) begin
            output_keep_comb[_byte] = _byte < unsigned'(32'(remaining_reg));
        end
    end

    function logic[31:0] register_value (input logic[31:0] address);
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_RX_HANDLE) begin
            return unsigned'(32'(stage_handle_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_LENGTH) begin
            return unsigned'(32'(stage_length_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_DESTINATION) begin
            return unsigned'(32'(stage_destination_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_SOURCE) begin
            return unsigned'(32'(stage_source_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_FLAGS) begin
            return unsigned'(32'(stage_flags_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_NETWORK_PORT) begin
            return unsigned'(32'(stage_network_port_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_STATUS) begin
            return (((((unsigned'(32'(state_reg)) != PacketDmaState_pkg::PACKET_DMA_IDLE)) ? (STATUS_BUSY) : ('h0)) | (((((unsigned'(32'(command_count_reg)) < CMD_DEPTH) && !command_write_pending_reg))) ? (STATUS_CMD_READY) : ('h0))) | ((protocol_error_reg) ? (STATUS_ERROR) : ('h0))) | ((unsigned'(32'(command_count_reg)) <<< 'h8));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMPLETED) begin
            return unsigned'(32'(completed_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CACHE_COMPLETED) begin
            return unsigned'(32'(cache_completed_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND_COMPLETED) begin
            return unsigned'(32'(command_completed_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND_ISSUED) begin
            return unsigned'(32'(command_issued_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND_LOCK) begin
            return unsigned'(32'(command_lock_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_COMPLETED) begin
            return unsigned'(32'(clear_completed_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_ADDRESS) begin
            return unsigned'(32'(clear_address_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_STATUS) begin
            return (((unsigned'(32'(backing_count_reg)) < (BACKING_DEPTH - 'h1))) ? ('h1) : ('h0)) | ((unsigned'(32'(backing_count_reg)) <<< 'h8));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_BACKING_COMPLETED) begin
            return unsigned'(32'(backing_completed_reg));
        end
        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_LAST_OPERATION) begin
            return unsigned'(32'(last_operation_reg));
        end
        return 'h0;
    endfunction

    function logic[256-1:0] register_read_value (input logic[31:0] address);
        logic[256-1:0] data;
        logic[31:0] index;
        logic[31:0] lane;
        logic[31:0] value;
        data = 'h0;
        lane = address & ((AXI_BYTES - 'h1));
        value = register_value(address & ~'h3);
        for (index='h0;index < 'h20;index=index+1) begin
            data[(lane*'h8) + index] = ((value >>> index)) & 'h1;
        end
        return data;
    endfunction

    function logic[31:0] write_value ();
        logic[31:0] value;
        logic[31:0] index;
        logic[31:0] lane;
        value = 'h0;
        lane = unsigned'(32'(write_addr_reg)) & ((AXI_BYTES - 'h1));
        for (index='h0;index < 'h20;index=index+1) begin
            if (mmio__wdata_in[(lane*'h8) + index]) begin
                value|='h1 <<< index;
            end
        end
        return value;
    endfunction

    function logic[31:0] beat_bytes ();
        logic[31:0] count;
        logic[31:0] index;
        logic gap;
        count = 'h0;
        gap = 0;
        for (index='h0;index < AXI_BYTES;index=index+1) begin
            if (beat_keep_reg[index]) begin
                if (gap) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_KEEP_GAP;
                end
                count=count+1;
            end
            else begin
                gap=1;
            end
        end
        return count;
    endfunction

    function logic[31:0] input_bytes (input logic[32-1:0] keep);
        logic[31:0] count;
        logic[31:0] index;
        logic gap;
        count = 'h0;
        gap = 0;
        for (index='h0;index < AXI_BYTES;index=index+1) begin
            if (keep[index]) begin
                if (gap) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_KEEP_GAP;
                end
                count=count+1;
            end
            else begin
                gap=1;
            end
        end
        return count;
    endfunction

    function logic output_ready ();
        if (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_SYSTEM) begin
            return system_tx_ready_in;
        end
        return network_tx_ready_in;
    endfunction

    always_comb begin : rx_l2_line_selected_comb_func  // rx_l2_line_selected_comb_func
        rx_l2_line_selected_comb=((((unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_STREAM)) || ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_CACHE_ALLOCATE)) != 'h0))))) && rx_valid_in;
    end

    always_comb begin : clear_l2_line_selected_comb_func  // clear_l2_line_selected_comb_func
        clear_l2_line_selected_comb=(unsigned'(32'(post_clear_count_reg)) != 'h0) && !rx_l2_line_selected_comb;
    end

    function logic backing_stream_write ();
        return l2_line_valid_out && l2_line_ready_in;
    endfunction

    function logic backing_clear_write ();
        return (((((mmio__wvalid_in && mmio__wready_out) && ((((unsigned'(32'(write_addr_reg)) & ~'h3)) == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_NOTIFY))) && (write_value() != 'h0)) && clear_notify_armed_reg) && (unsigned'(32'(backing_count_reg)) < BACKING_DEPTH)) && !backing_stream_write();
    endfunction

    function logic backing_memory_write ();
        return backing_stream_write() || backing_clear_write();
    endfunction

    function logic post_clear_memory_write ();
        return (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_POST_TX_CLEAR) && (unsigned'(32'(post_clear_count_reg)) < CLEAR_DEPTH);
    endfunction

    always_comb begin : backing_memory_write_comb_func  // backing_memory_write_comb_func
        backing_memory_write_comb=backing_memory_write();
    end

    always_comb begin : backing_address_write_data_comb_func  // backing_address_write_data_comb_func
        backing_address_write_data_comb = (backing_stream_write()) ? (l2_line_addr_out) : (clear_address_reg);
    end

    always_comb begin : backing_data_write_data_comb_func  // backing_data_write_data_comb_func
        backing_data_write_data_comb = (backing_stream_write()) ? (l2_line_data_out) : ('h0);
    end

    always_comb begin : backing_keep_write_data_comb_func  // backing_keep_write_data_comb_func
        backing_keep_write_data_comb = (backing_stream_write()) ? (l2_line_keep_out) : (-'h1);
    end

    always_comb begin : backing_clear_write_data_comb_func  // backing_clear_write_data_comb_func
        backing_clear_write_data_comb = (backing_stream_write()) ? (clear_l2_line_selected_comb) : (1);
    end

    always_comb begin : post_clear_memory_write_comb_func  // post_clear_memory_write_comb_func
        post_clear_memory_write_comb=post_clear_memory_write();
    end

    generate  // _assign
        assign command_handle_mem__write_addr_in = command_tail_reg;
        assign command_handle_mem__write_in = command_write_pending_reg;
        assign command_handle_mem__write_data_in = command_write_handle_reg;
        assign command_handle_mem__read_addr_in = command_head_reg;
        assign command_length_mem__write_addr_in = command_tail_reg;
        assign command_length_mem__write_in = command_write_pending_reg;
        assign command_length_mem__write_data_in = command_write_length_reg;
        assign command_length_mem__read_addr_in = command_head_reg;
        assign command_source_mem__write_addr_in = command_tail_reg;
        assign command_source_mem__write_in = command_write_pending_reg;
        assign command_source_mem__write_data_in = command_write_source_reg;
        assign command_source_mem__read_addr_in = command_head_reg;
        assign command_destination_mem__write_addr_in = command_tail_reg;
        assign command_destination_mem__write_in = command_write_pending_reg;
        assign command_destination_mem__write_data_in = command_write_destination_reg;
        assign command_destination_mem__read_addr_in = command_head_reg;
        assign command_flags_mem__write_addr_in = command_tail_reg;
        assign command_flags_mem__write_in = command_write_pending_reg;
        assign command_flags_mem__write_data_in = command_write_flags_reg;
        assign command_flags_mem__read_addr_in = command_head_reg;
        assign command_network_port_mem__write_addr_in = command_tail_reg;
        assign command_network_port_mem__write_in = command_write_pending_reg;
        assign command_network_port_mem__write_data_in = command_write_network_port_reg;
        assign command_network_port_mem__read_addr_in = command_head_reg;
        assign backing_address_mem__write_addr_in = backing_tail_reg;
        assign backing_address_mem__write_in = backing_memory_write_comb;
        assign backing_address_mem__write_data_in = backing_address_write_data_comb;
        assign backing_address_mem__read_addr_in = backing_head_reg;
        assign backing_data_mem__write_addr_in = backing_tail_reg;
        assign backing_data_mem__write_in = backing_memory_write_comb;
        assign backing_data_mem__write_data_in = backing_data_write_data_comb;
        assign backing_data_mem__read_addr_in = backing_head_reg;
        assign backing_keep_mem__write_addr_in = backing_tail_reg;
        assign backing_keep_mem__write_in = backing_memory_write_comb;
        assign backing_keep_mem__write_data_in = backing_keep_write_data_comb;
        assign backing_keep_mem__read_addr_in = backing_head_reg;
        assign backing_clear_mem__write_addr_in = backing_tail_reg;
        assign backing_clear_mem__write_in = backing_memory_write_comb;
        assign backing_clear_mem__write_data_in = backing_clear_write_data_comb;
        assign backing_clear_mem__read_addr_in = backing_head_reg;
        assign post_clear_mem__write_addr_in = post_clear_tail_reg;
        assign post_clear_mem__write_in = post_clear_memory_write_comb;
        assign post_clear_mem__write_data_in = (source_base_reg & ~((AXI_BYTES - 'h1)));
        assign post_clear_mem__read_addr_in = post_clear_head_reg;
        assign mmio__awready_out = (!write_addr_valid_reg && !write_response_valid_reg) && (((!write_aw_seen_reg || (mmio__awaddr_in != write_aw_seen_addr_reg)) || (mmio__awid_in != write_aw_seen_id_reg)));
        assign mmio__wready_out = ((write_addr_valid_reg && !write_response_valid_reg) && ((((((unsigned'(32'(write_addr_reg)) & ~'h3)) != PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND)) || (((unsigned'(32'(command_count_reg)) < CMD_DEPTH) && !command_write_pending_reg))))) && ((((((unsigned'(32'(write_addr_reg)) & ~'h3)) != PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_NOTIFY)) || (((unsigned'(32'(backing_count_reg)) < BACKING_DEPTH) && !((l2_line_valid_out && l2_line_ready_in))))));
        assign mmio__bvalid_out = write_response_valid_reg;
        assign mmio__bid_out = write_id_reg;
        assign mmio__arready_out = !read_pending_reg && !read_valid_reg;
        assign mmio__rvalid_out = read_valid_reg;
        assign mmio__rdata_out = read_data_reg;
        assign mmio__rlast_out = read_valid_reg;
        assign mmio__rid_out = read_id_reg;
        assign l2_dma__awvalid_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_ADDRESS;
        assign l2_dma__awaddr_out = destination_reg;
        assign l2_dma__awid_out = unsigned'(AXI_ID_WIDTH'(unsigned'(AXI_ID_WIDTH'('h0))));
        assign l2_dma__wvalid_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_DATA;
        assign l2_dma__wdata_out = beat_data_reg;
        assign l2_dma__wstrb_out = beat_keep_reg;
        assign l2_dma__wlast_out = 1;
        assign l2_dma__bready_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_RESPONSE;
        assign l2_dma__arvalid_out = (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) && !(((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0)));
        assign l2_dma__araddr_out = source_reg;
        assign l2_dma__arid_out = unsigned'(AXI_ID_WIDTH'(unsigned'(AXI_ID_WIDTH'('h0))));
        assign l2_dma__rready_out = (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA) && !(((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0)));
        assign l2_line_valid_out = ((unsigned'(32'(backing_count_reg)) < BACKING_DEPTH) && !(((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) || (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA))) && !(((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0)))))) && ((rx_l2_line_selected_comb || clear_l2_line_selected_comb));
        assign l2_line_addr_out = (clear_l2_line_selected_comb) ? (unsigned'(AXI_ADDR_WIDTH'(unsigned'(AXI_ADDR_WIDTH'(unsigned'(32'(post_clear_mem__read_data_out))))))) : (((unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_STREAM) ? (unsigned'(AXI_ADDR_WIDTH'(unsigned'(AXI_ADDR_WIDTH'(prefetch_destination_reg))))) : (unsigned'(AXI_ADDR_WIDTH'(unsigned'(AXI_ADDR_WIDTH'(destination_reg)))))));
        assign l2_line_data_out = (clear_l2_line_selected_comb) ? ('h0) : (rx_data_in);
        assign l2_line_keep_out = (clear_l2_line_selected_comb) ? (-'h1) : (rx_keep_in);
        assign l2_line_eop_out = (l2_line_valid_out && l2_line_ready_in) && ((clear_l2_line_selected_comb || ((rx_eop_in && (unsigned'(32'(cache_invalidate_count_reg)) == 'h0)))));
        assign rx_read_valid_out = (unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_ISSUE) || (((unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE) && (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_ISSUE_NETWORK_READ)));
        assign rx_read_handle_out = (unsigned'(32'(prefetch_state_reg)) != PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE) ? (unsigned'(HANDLE_BITS'(unsigned'(HANDLE_BITS'(prefetch_handle_reg))))) : (unsigned'(HANDLE_BITS'(unsigned'(HANDLE_BITS'(current_handle_comb)))));
        assign rx_read_length_out = (unsigned'(32'(prefetch_state_reg)) != PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE) ? (unsigned'(FRAME_LENGTH_BITS'(unsigned'(FRAME_LENGTH_BITS'(prefetch_length_reg))))) : (unsigned'(FRAME_LENGTH_BITS'(unsigned'(FRAME_LENGTH_BITS'(current_length_comb)))));
        assign rx_ready_out = (unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_STREAM) ? (((l2_line_ready_in && (unsigned'(32'(backing_count_reg)) < BACKING_DEPTH)) && !(((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) || (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA))) && !(((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0))))))) : ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((((unsigned'(32'(active_flags_reg)) & FLAG_CACHE_ALLOCATE)) != 'h0)) ? (((l2_line_ready_in && (unsigned'(32'(backing_count_reg)) < BACKING_DEPTH)))) : (((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0)) ? (system_tx_ready_in) : (((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0)) ? (network_tx_ready_in) : (1))))));
        assign system_rx_ready_out = (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_SYSTEM_CPU);
        assign system_tx_valid_out = (((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_SYSTEM))) || (((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0)) && rx_valid_in));
        assign network_tx_valid_out = (((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK))) || (((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0)) && rx_valid_in));
        assign system_tx_data_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_data_in) : (beat_data_reg);
        assign network_tx_data_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0))) ? (rx_data_in) : (beat_data_reg);
        assign system_tx_keep_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_keep_in) : (beat_keep_reg);
        assign network_tx_keep_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0))) ? (rx_keep_in) : (beat_keep_reg);
        assign system_tx_sop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_sop_in) : (beat_sop_reg);
        assign network_tx_sop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0))) ? (rx_sop_in) : (beat_sop_reg);
        assign system_tx_eop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_eop_in) : (beat_eop_reg);
        assign network_tx_eop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0))) ? (rx_eop_in) : (beat_eop_reg);
        assign network_tx_port_out = active_network_port_reg;
        assign busy_out = ((unsigned'(32'(state_reg)) != PacketDmaState_pkg::PACKET_DMA_IDLE) || (unsigned'(32'(command_count_reg)) != 'h0)) || command_write_pending_reg;
        assign command_ready_out = (unsigned'(32'(command_count_reg)) < CMD_DEPTH) && !command_write_pending_reg;
        assign descriptor_command_ready_out = (descriptor_command_cache_in) ? (unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE) : (((unsigned'(32'(command_count_reg)) < CMD_DEPTH) && !command_write_pending_reg));
        assign completed_count_out = completed_reg;
        assign cache_completed_count_out = cache_completed_reg;
        assign command_completed_count_out = command_completed_reg;
        assign clear_completed_count_out = clear_completed_reg;
        assign last_operation_out = last_operation_reg;
        assign protocol_error_out = protocol_error_reg;
        assign protocol_error_reason_out = protocol_error_reason_reg;
        assign backing_pending_count_out = backing_count_reg;
        assign backing_completed_beat_count_out = backing_completed_reg;
        assign backing_dma__awvalid_out = (unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_ADDRESS) && (unsigned'(32'(backing_count_reg)) != 'h0);
        assign backing_dma__awaddr_out = unsigned'(BACKING_ADDR_WIDTH'(unsigned'(BACKING_ADDR_WIDTH'(unsigned'(32'(backing_address_mem__read_data_out))))));
        assign backing_dma__awid_out = unsigned'(AXI_ID_WIDTH'(unsigned'(AXI_ID_WIDTH'('h0))));
        assign backing_dma__wvalid_out = (((unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_ADDRESS) || (unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_DATA))) && (unsigned'(32'(backing_count_reg)) != 'h0);
        assign backing_dma__wdata_out = backing_data_mem__read_data_out;
        assign backing_dma__wstrb_out = backing_keep_mem__read_data_out;
        assign backing_dma__wlast_out = 1;
        assign backing_dma__bready_out = unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_RESPONSE;
        assign backing_dma__arvalid_out = ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK)) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0);
        assign backing_dma__araddr_out = unsigned'(BACKING_ADDR_WIDTH'(unsigned'(BACKING_ADDR_WIDTH'(source_reg))));
        assign backing_dma__arid_out = unsigned'(AXI_ID_WIDTH'(unsigned'(AXI_ID_WIDTH'('h0))));
        assign backing_dma__rready_out = ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK)) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0);
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] address;
        logic[31:0] value;
        logic[31:0] count;
        logic[31:0] bytes;
        logic push;
        logic pop;
        logic descriptor_push;
        logic input_valid;
        logic input_sop;
        logic input_eop;
        logic backing_push;
        logic backing_pop;
        logic[31:0] backing_count;
        logic[31:0] post_clear_count;
        logic[256-1:0] input_data;
        logic[32-1:0] input_keep;
        PacketDMA17_14_64_32_4_256_31_32_64_Command command;
        PacketDMA17_14_64_32_4_256_31_32_64_Command staged;
        count=unsigned'(32'(command_count_reg));
        if (command_write_pending_reg) begin
            command_tail_reg_tmp = ((unsigned'(32'(command_tail_reg)) + 'h1)) & ((CMD_DEPTH - 'h1));
            command_issued_reg_tmp = command_issued_reg + 'h1;
            command_write_pending_reg_tmp = unsigned'(1'(0));
            count=count+1;
        end
        push=0;
        pop=0;
        descriptor_push=0;
        command = current_command();
        backing_count=unsigned'(32'(backing_count_reg));
        backing_push=l2_line_valid_out && l2_line_ready_in;
        backing_pop=0;
        post_clear_count=unsigned'(32'(post_clear_count_reg));
        if (backing_push) begin
            backing_tail_reg_tmp = ((unsigned'(32'(backing_tail_reg)) + 'h1)) & ((BACKING_DEPTH - 'h1));
            backing_count=backing_count+1;
            if (clear_l2_line_selected_comb) begin
                post_clear_head_reg_tmp = ((unsigned'(32'(post_clear_head_reg)) + 'h1)) & ((CLEAR_DEPTH - 'h1));
                --post_clear_count;
            end
        end
        if ((unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_IDLE) && (backing_count != 'h0)) begin
            backing_state_reg_tmp = PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_ADDRESS;
        end
        else begin
            if (((unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_ADDRESS) && backing_dma__awvalid_out) && backing_dma__awready_in) begin
                backing_state_reg_tmp = (backing_dma__wvalid_out && backing_dma__wready_in) ? (PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_RESPONSE) : (PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_DATA);
            end
            else begin
                if (((unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_DATA) && backing_dma__wvalid_out) && backing_dma__wready_in) begin
                    backing_state_reg_tmp = PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_RESPONSE;
                end
                else begin
                    if (((unsigned'(32'(backing_state_reg)) == PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_RESPONSE) && backing_dma__bvalid_in) && backing_dma__bready_out) begin
                        backing_state_reg_tmp = (backing_count > 'h1) ? (PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_ADDRESS) : (PacketDMA17_14_64_32_4_256_31_32_64_BackingState_pkg::BACKING_IDLE);
                        backing_head_reg_tmp = ((unsigned'(32'(backing_head_reg)) + 'h1)) & ((BACKING_DEPTH - 'h1));
                        backing_pop=1;
                        backing_completed_reg_tmp = backing_completed_reg + 'h1;
                        if (backing_clear_mem__read_data_out) begin
                            clear_completed_reg_tmp = clear_completed_reg + 'h1;
                        end
                    end
                end
            end
        end
        if (backing_pop) begin
            --backing_count;
        end
        backing_count_reg_tmp = backing_count;
        if ((descriptor_command_valid_in && descriptor_command_cache_in) && descriptor_command_ready_out) begin
            prefetch_handle_reg_tmp = descriptor_command_handle_in;
            prefetch_length_reg_tmp = descriptor_command_length_in;
            prefetch_destination_reg_tmp = descriptor_command_destination_in;
            prefetch_remaining_reg_tmp = descriptor_command_length_in;
            prefetch_first_reg_tmp = unsigned'(1'(1));
            prefetch_state_reg_tmp = PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_ISSUE;
        end
        else begin
            if ((unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_ISSUE) && rx_read_ready_in) begin
                prefetch_state_reg_tmp = PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_STREAM;
            end
            else begin
                if ((((unsigned'(32'(prefetch_state_reg)) == PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_STREAM) && rx_l2_line_selected_comb) && l2_line_valid_out) && l2_line_ready_in) begin
                    bytes=input_bytes(rx_keep_in);
                    if (prefetch_first_reg != rx_sop_in) begin
                        protocol_error_reg_tmp = unsigned'(1'(1));
                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_SOP;
                    end
                    if ((bytes == 'h0) || (bytes > unsigned'(32'(prefetch_remaining_reg)))) begin
                        protocol_error_reg_tmp = unsigned'(1'(1));
                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_BEAT_LENGTH;
                    end
                    if (rx_eop_in) begin
                        if (bytes != unsigned'(32'(prefetch_remaining_reg))) begin
                            protocol_error_reg_tmp = unsigned'(1'(1));
                            protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_EOP_LENGTH;
                        end
                        completed_reg_tmp = completed_reg + 'h1;
                        cache_completed_reg_tmp = cache_completed_reg + 'h1;
                        if (unsigned'(32'(cache_invalidate_count_reg)) == 'h0) begin
                            cache_invalidate_count_reg_tmp = 'h9;
                        end
                        else begin
                            cache_invalidate_count_reg_tmp = cache_invalidate_count_reg - 'h1;
                        end
                        prefetch_state_reg_tmp = PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE;
                    end
                    else begin
                        if ((bytes != AXI_BYTES) || bytes>=unsigned'(32'(prefetch_remaining_reg))) begin
                            protocol_error_reg_tmp = unsigned'(1'(1));
                            protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_NON_EOP_LENGTH;
                        end
                        prefetch_destination_reg_tmp = prefetch_destination_reg + AXI_BYTES;
                        prefetch_remaining_reg_tmp = prefetch_remaining_reg - bytes;
                        prefetch_first_reg_tmp = unsigned'(1'(0));
                    end
                end
            end
        end
        if (mmio__awvalid_in && mmio__awready_out) begin
            write_addr_reg_tmp = mmio__awaddr_in;
            write_id_reg_tmp = mmio__awid_in;
            write_addr_valid_reg_tmp = unsigned'(1'(1));
            write_aw_seen_reg_tmp = unsigned'(1'(1));
            write_aw_seen_addr_reg_tmp = mmio__awaddr_in;
            write_aw_seen_id_reg_tmp = mmio__awid_in;
        end
        if (!mmio__awvalid_in) begin
            write_aw_seen_reg_tmp = unsigned'(1'(0));
        end
        if (mmio__wvalid_in && mmio__wready_out) begin
            address=unsigned'(32'(write_addr_reg)) & ~'h3;
            value=write_value();
            if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_RX_HANDLE) begin
                stage_handle_reg_tmp = value;
                stage_command_armed_reg_tmp = unsigned'(1'(1));
            end
            else begin
                if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_LENGTH) begin
                    stage_length_reg_tmp = value;
                    stage_command_armed_reg_tmp = unsigned'(1'(1));
                end
                else begin
                    if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_SOURCE) begin
                        stage_source_reg_tmp = unsigned'(32'(value));
                        stage_command_armed_reg_tmp = unsigned'(1'(1));
                    end
                    else begin
                        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_DESTINATION) begin
                            stage_destination_reg_tmp = unsigned'(32'(value));
                            stage_command_armed_reg_tmp = unsigned'(1'(1));
                        end
                        else begin
                            if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_FLAGS) begin
                                stage_flags_reg_tmp = unsigned'(8'(value));
                                stage_command_armed_reg_tmp = unsigned'(1'(1));
                            end
                            else begin
                                if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_NETWORK_PORT) begin
                                    stage_network_port_reg_tmp = value;
                                    stage_command_armed_reg_tmp = unsigned'(1'(1));
                                end
                                else begin
                                    if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND_LOCK) begin
                                        if (((value == 'h0) || (unsigned'(32'(command_lock_reg)) == 'h0)) || (unsigned'(32'(command_lock_reg)) == ((value & 'hFF)))) begin
                                            command_lock_reg_tmp = value & 'hFF;
                                        end
                                    end
                                    else begin
                                        if (address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_ADDRESS) begin
                                            clear_address_reg_tmp = value & ~((AXI_BYTES - 'h1));
                                            clear_notify_armed_reg_tmp = unsigned'(1'(1));
                                        end
                                        else begin
                                            if (((address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_CLEAR_NOTIFY) && (value != 'h0)) && clear_notify_armed_reg) begin
                                                if ((backing_count < BACKING_DEPTH) && !backing_push) begin
                                                    backing_tail_reg_tmp = ((unsigned'(32'(backing_tail_reg)) + 'h1)) & ((BACKING_DEPTH - 'h1));
                                                    backing_count=backing_count+1;
                                                    backing_count_reg_tmp = backing_count;
                                                    clear_notify_armed_reg_tmp = unsigned'(1'(0));
                                                end
                                                else begin
                                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_COMMAND_QUEUE_FULL;
                                                end
                                            end
                                            else begin
                                                if (((address == PacketDMA17_14_64_32_4_256_31_32_64_Register_pkg::REG_COMMAND) && (((value & COMMAND_PUSH)) != 'h0)) && stage_command_armed_reg) begin
                                                    push=count < CMD_DEPTH;
                                                    if (!push) begin
                                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_COMMAND_QUEUE_FULL;
                                                    end
                                                    else begin
                                                        if (unsigned'(32'(stage_length_reg)) == 'h0) begin
                                                            protocol_error_reg_tmp = unsigned'(1'(1));
                                                            protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_ZERO_LENGTH;
                                                            push=0;
                                                        end
                                                        else begin
                                                            if (((((((unsigned'(32'(stage_flags_reg)) & ~(((((((FLAG_OPERATION_MASK | FLAG_CACHE_ALLOCATE) | FLAG_NETWORK_DISCARD) | FLAG_NETWORK_SYSTEM) | FLAG_RING_SOURCE) | FLAG_CLEAR_SOURCE_AFTER_TX) | FLAG_NETWORK_FORWARD)))) != 'h0) || (((((unsigned'(32'(stage_flags_reg)) & (((FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM) | FLAG_NETWORK_FORWARD)))) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) != PacketDmaOperation_pkg::DMA_NETWORK_CPU)))) || ((((((((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_DISCARD)) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) || (((((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_DISCARD)) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0)))) || (((((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0)))))) || (((((unsigned'(32'(stage_flags_reg)) & FLAG_RING_SOURCE)) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) != PacketDmaOperation_pkg::DMA_CPU_NETWORK)))) || (((((unsigned'(32'(stage_flags_reg)) & FLAG_CLEAR_SOURCE_AFTER_TX)) != 'h0) && (((((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) != PacketDmaOperation_pkg::DMA_CPU_NETWORK) || (((unsigned'(32'(stage_flags_reg)) & FLAG_RING_SOURCE)) == 'h0)))))) begin
                                                                protocol_error_reg_tmp = unsigned'(1'(1));
                                                                protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_FLAGS;
                                                                push=0;
                                                            end
                                                        end
                                                    end
                                                    if ((push && ((((((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) || (((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_SYSTEM_CPU))))) && (((unsigned'(32'(stage_destination_reg)) & ((AXI_BYTES - 'h1)))) != 'h0)) begin
                                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_DESTINATION_ALIGNMENT;
                                                        push=0;
                                                    end
                                                    if ((push && ((((((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_CPU_SYSTEM) || (((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK))))) && (((unsigned'(32'(stage_source_reg)) & ((AXI_BYTES - 'h1)))) != 'h0)) begin
                                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_SOURCE_ALIGNMENT;
                                                        push=0;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            write_addr_valid_reg_tmp = unsigned'(1'(0));
            write_response_valid_reg_tmp = unsigned'(1'(1));
        end
        if (write_response_valid_reg && mmio__bready_in) begin
            write_response_valid_reg_tmp = unsigned'(1'(0));
        end
        if (mmio__arvalid_in && mmio__arready_out) begin
            read_id_reg_tmp = mmio__arid_in;
            read_addr_reg_tmp = mmio__araddr_in;
            read_pending_reg_tmp = unsigned'(1'(1));
        end
        if (read_pending_reg && !read_valid_reg) begin
            read_data_reg_tmp = register_read_value(unsigned'(32'(read_addr_reg)));
            read_valid_reg_tmp = unsigned'(1'(1));
            read_pending_reg_tmp = unsigned'(1'(0));
        end
        if (read_valid_reg && mmio__rready_in) begin
            read_valid_reg_tmp = unsigned'(1'(0));
        end
        if ((((descriptor_command_valid_in && !descriptor_command_cache_in) && (count < CMD_DEPTH)) && !push) && !command_write_pending_reg) begin
            staged = 0;
            staged.handle = descriptor_command_handle_in;
            staged.length = descriptor_command_length_in;
            staged.destination = descriptor_command_destination_in;
            staged.flags = unsigned'(8'(PacketDmaOperation_pkg::DMA_NETWORK_CPU | ((descriptor_command_cache_in) ? (FLAG_CACHE_ALLOCATE) : (((descriptor_command_network_in) ? (FLAG_NETWORK_FORWARD) : (((descriptor_command_system_in) ? (FLAG_NETWORK_SYSTEM) : (FLAG_NETWORK_DISCARD))))))));
            staged.network_port = descriptor_command_network_port_in;
            push=1;
            descriptor_push=1;
        end
        if (push) begin
            if (!descriptor_push) begin
                staged = 0;
                staged.handle = stage_handle_reg;
                staged.length = stage_length_reg;
                staged.source = stage_source_reg;
                staged.destination = stage_destination_reg;
                staged.flags = stage_flags_reg;
                staged.network_port = stage_network_port_reg;
                stage_command_armed_reg_tmp = unsigned'(1'(0));
            end
            command_write_handle_reg_tmp = staged.handle;
            command_write_length_reg_tmp = staged.length;
            command_write_source_reg_tmp = staged.source;
            command_write_destination_reg_tmp = staged.destination;
            command_write_flags_reg_tmp = staged.flags;
            command_write_network_port_reg_tmp = unsigned'(8'(unsigned'(8'(staged.network_port))));
            command_write_pending_reg_tmp = unsigned'(1'(1));
        end
        if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_IDLE) && (unsigned'(32'(command_count_reg)) != 'h0)) begin
            operation_reg_tmp = unsigned'(32'(command.flags)) & FLAG_OPERATION_MASK;
            active_flags_reg_tmp = command.flags;
            active_network_port_reg_tmp = command.network_port;
            source_reg_tmp = command.source;
            source_base_reg_tmp = command.source;
            destination_reg_tmp = command.destination;
            remaining_reg_tmp = command.length;
            first_beat_reg_tmp = unsigned'(1'(1));
            if ((((unsigned'(32'(command.flags)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) && (unsigned'(32'(prefetch_state_reg)) != PacketDmaPrefetchState_pkg::PACKET_DMA_PREFETCH_IDLE)) begin
            end
            else begin
                if (((unsigned'(32'(command.flags)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) begin
                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_ISSUE_NETWORK_READ));
                end
                else begin
                    if (((unsigned'(32'(command.flags)) & FLAG_OPERATION_MASK)) == PacketDmaOperation_pkg::DMA_SYSTEM_CPU) begin
                        state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT));
                    end
                    else begin
                        state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS));
                    end
                end
            end
        end
        else begin
            if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_ISSUE_NETWORK_READ) && rx_read_ready_in) begin
                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT));
            end
            else begin
                if (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) begin
                    input_valid=(unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) ? (rx_valid_in) : (system_rx_valid_in);
                    input_data = (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) ? (rx_data_in) : (system_rx_data_in);
                    input_keep = (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) ? (rx_keep_in) : (system_rx_keep_in);
                    input_sop=(unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) ? (rx_sop_in) : (system_rx_sop_in);
                    input_eop=(unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) ? (rx_eop_in) : (system_rx_eop_in);
                    if ((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) && (((unsigned'(32'(active_flags_reg)) & (((FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM) | FLAG_NETWORK_FORWARD)))) != 'h0)) begin
                        if (input_valid && (((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0)) ? (system_tx_ready_in) : ((((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_FORWARD)) != 'h0)) ? (network_tx_ready_in) : (1))))) begin
                            bytes=input_bytes(input_keep);
                            if (first_beat_reg != input_sop) begin
                                protocol_error_reg_tmp = unsigned'(1'(1));
                                protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_SOP;
                            end
                            if ((bytes == 'h0) || (bytes > unsigned'(32'(remaining_reg)))) begin
                                protocol_error_reg_tmp = unsigned'(1'(1));
                                protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_BEAT_LENGTH;
                            end
                            if (input_eop) begin
                                if (bytes != unsigned'(32'(remaining_reg))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_EOP_LENGTH;
                                end
                                completed_reg_tmp = completed_reg + 'h1;
                                command_completed_reg_tmp = command_completed_reg + 'h1;
                                last_operation_reg_tmp = operation_reg;
                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                pop=count != 'h0;
                            end
                            else begin
                                if ((bytes != AXI_BYTES) || bytes>=unsigned'(32'(remaining_reg))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_NON_EOP_LENGTH;
                                end
                                remaining_reg_tmp = remaining_reg - bytes;
                                first_beat_reg_tmp = unsigned'(1'(0));
                            end
                        end
                    end
                    else begin
                        if ((((input_valid && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_CACHE_ALLOCATE)) != 'h0)) && l2_line_valid_out) && l2_line_ready_in) begin
                            bytes=input_bytes(input_keep);
                            if (first_beat_reg != input_sop) begin
                                protocol_error_reg_tmp = unsigned'(1'(1));
                                protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_SOP;
                            end
                            if ((bytes == 'h0) || (bytes > unsigned'(32'(remaining_reg)))) begin
                                protocol_error_reg_tmp = unsigned'(1'(1));
                                protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_BEAT_LENGTH;
                            end
                            if (input_eop) begin
                                if (bytes != unsigned'(32'(remaining_reg))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_EOP_LENGTH;
                                end
                                completed_reg_tmp = completed_reg + 'h1;
                                command_completed_reg_tmp = command_completed_reg + 'h1;
                                cache_completed_reg_tmp = cache_completed_reg + 'h1;
                                if (unsigned'(32'(cache_invalidate_count_reg)) == 'h0) begin
                                    cache_invalidate_count_reg_tmp = 'h9;
                                end
                                else begin
                                    cache_invalidate_count_reg_tmp = cache_invalidate_count_reg - 'h1;
                                end
                                last_operation_reg_tmp = operation_reg;
                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                pop=count != 'h0;
                            end
                            else begin
                                if ((bytes != AXI_BYTES) || bytes>=unsigned'(32'(remaining_reg))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_NON_EOP_LENGTH;
                                end
                                destination_reg_tmp = destination_reg + AXI_BYTES;
                                remaining_reg_tmp = remaining_reg - bytes;
                                first_beat_reg_tmp = unsigned'(1'(0));
                            end
                        end
                        else begin
                            if (input_valid && (((unsigned'(32'(operation_reg)) != PacketDmaOperation_pkg::DMA_NETWORK_CPU) || (((unsigned'(32'(active_flags_reg)) & FLAG_CACHE_ALLOCATE)) == 'h0)))) begin
                                beat_data_reg_tmp = input_data;
                                beat_keep_reg_tmp = input_keep;
                                beat_sop_reg_tmp = unsigned'(1'(input_sop));
                                beat_eop_reg_tmp = unsigned'(1'(input_eop));
                                if (first_beat_reg != input_sop) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_SOP;
                                end
                                first_beat_reg_tmp = unsigned'(1'(0));
                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WRITE_ADDRESS));
                            end
                        end
                    end
                end
                else begin
                    if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_ADDRESS) && l2_dma__awready_in) begin
                        state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WRITE_DATA));
                    end
                    else begin
                        if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_DATA) && l2_dma__wready_in) begin
                            state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WRITE_RESPONSE));
                        end
                        else begin
                            if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WRITE_RESPONSE) && l2_dma__bvalid_in) begin
                                bytes=beat_bytes();
                                if ((bytes == 'h0) || (bytes > unsigned'(32'(remaining_reg)))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                    protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_BEAT_LENGTH;
                                end
                                if (beat_eop_reg) begin
                                    if (bytes != unsigned'(32'(remaining_reg))) begin
                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_EOP_LENGTH;
                                    end
                                    completed_reg_tmp = completed_reg + 'h1;
                                    command_completed_reg_tmp = command_completed_reg + 'h1;
                                    last_operation_reg_tmp = operation_reg;
                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                    pop=count != 'h0;
                                end
                                else begin
                                    if ((bytes != AXI_BYTES) || bytes>=unsigned'(32'(remaining_reg))) begin
                                        protocol_error_reg_tmp = unsigned'(1'(1));
                                        protocol_error_reason_reg_tmp = PacketDmaError_pkg::PACKET_DMA_ERROR_NON_EOP_LENGTH;
                                    end
                                    destination_reg_tmp = destination_reg + AXI_BYTES;
                                    remaining_reg_tmp = remaining_reg - bytes;
                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT));
                                end
                            end
                            else begin
                                if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) && (((((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0)))) ? (backing_dma__arready_in) : (l2_dma__arready_in))) begin
                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_READ_DATA));
                                end
                                else begin
                                    if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA) && (((((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0)))) ? (backing_dma__rvalid_in) : (l2_dma__rvalid_in))) begin
                                        beat_data_reg_tmp = (((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK) && (((unsigned'(32'(active_flags_reg)) & FLAG_RING_SOURCE)) != 'h0))) ? (backing_dma__rdata_in) : (l2_dma__rdata_in);
                                        beat_keep_reg_tmp = output_keep_comb;
                                        beat_sop_reg_tmp = first_beat_reg;
                                        beat_eop_reg_tmp = unsigned'(1'(remaining_reg<=AXI_BYTES));
                                        state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT));
                                    end
                                    else begin
                                        if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && output_ready()) begin
                                            if (remaining_reg<=AXI_BYTES) begin
                                                if (((unsigned'(32'(active_flags_reg)) & FLAG_CLEAR_SOURCE_AFTER_TX)) != 'h0) begin
                                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_POST_TX_CLEAR));
                                                end
                                                else begin
                                                    completed_reg_tmp = completed_reg + 'h1;
                                                    command_completed_reg_tmp = command_completed_reg + 'h1;
                                                    last_operation_reg_tmp = operation_reg;
                                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                                    pop=count != 'h0;
                                                end
                                            end
                                            else begin
                                                source_reg_tmp = source_reg + AXI_BYTES;
                                                remaining_reg_tmp = remaining_reg - AXI_BYTES;
                                                first_beat_reg_tmp = unsigned'(1'(0));
                                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS));
                                            end
                                        end
                                        else begin
                                            if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_POST_TX_CLEAR) && (post_clear_count < CLEAR_DEPTH)) begin
                                                post_clear_tail_reg_tmp = ((unsigned'(32'(post_clear_tail_reg)) + 'h1)) & ((CLEAR_DEPTH - 'h1));
                                                post_clear_count=post_clear_count+1;
                                                completed_reg_tmp = completed_reg + 'h1;
                                                command_completed_reg_tmp = command_completed_reg + 'h1;
                                                last_operation_reg_tmp = operation_reg;
                                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                                pop=count != 'h0;
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        post_clear_count_reg_tmp = post_clear_count;
        if (pop) begin
            command_head_reg_tmp = ((unsigned'(32'(command_head_reg)) + 'h1)) & ((CMD_DEPTH - 'h1));
            --count;
        end
        command_count_reg_tmp = count;
        if (reset) begin
            command_head_reg_tmp = '0;
            command_tail_reg_tmp = '0;
            command_count_reg_tmp = '0;
            command_write_pending_reg_tmp = '0;
            stage_handle_reg_tmp = '0;
            stage_length_reg_tmp = '0;
            stage_source_reg_tmp = '0;
            stage_destination_reg_tmp = '0;
            stage_flags_reg_tmp = '0;
            stage_network_port_reg_tmp = '0;
            stage_command_armed_reg_tmp = '0;
            state_reg_tmp = '0;
            operation_reg_tmp = '0;
            active_flags_reg_tmp = '0;
            active_network_port_reg_tmp = '0;
            source_reg_tmp = '0;
            source_base_reg_tmp = '0;
            destination_reg_tmp = '0;
            remaining_reg_tmp = '0;
            beat_data_reg_tmp = '0;
            beat_keep_reg_tmp = '0;
            beat_sop_reg_tmp = '0;
            beat_eop_reg_tmp = '0;
            first_beat_reg_tmp = '0;
            completed_reg_tmp = '0;
            cache_completed_reg_tmp = '0;
            command_completed_reg_tmp = '0;
            command_issued_reg_tmp = '0;
            command_lock_reg_tmp = '0;
            clear_completed_reg_tmp = '0;
            clear_address_reg_tmp = '0;
            clear_notify_armed_reg_tmp = '0;
            cache_invalidate_count_reg_tmp = unsigned'(4'h9);
            last_operation_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            protocol_error_reason_reg_tmp = '0;
            prefetch_state_reg_tmp = '0;
            prefetch_handle_reg_tmp = '0;
            prefetch_length_reg_tmp = '0;
            prefetch_destination_reg_tmp = '0;
            prefetch_remaining_reg_tmp = '0;
            prefetch_first_reg_tmp = '0;
            write_addr_reg_tmp = '0;
            write_id_reg_tmp = '0;
            write_addr_valid_reg_tmp = '0;
            write_response_valid_reg_tmp = '0;
            write_aw_seen_reg_tmp = '0;
            write_aw_seen_addr_reg_tmp = '0;
            write_aw_seen_id_reg_tmp = '0;
            read_id_reg_tmp = '0;
            read_addr_reg_tmp = '0;
            read_pending_reg_tmp = '0;
            read_data_reg_tmp = '0;
            read_valid_reg_tmp = '0;
            backing_head_reg_tmp = '0;
            backing_tail_reg_tmp = '0;
            backing_count_reg_tmp = '0;
            backing_state_reg_tmp = '0;
            backing_completed_reg_tmp = '0;
            post_clear_head_reg_tmp = '0;
            post_clear_tail_reg_tmp = '0;
            post_clear_count_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        command_head_reg_tmp = command_head_reg;
        command_tail_reg_tmp = command_tail_reg;
        command_count_reg_tmp = command_count_reg;
        command_write_pending_reg_tmp = command_write_pending_reg;
        command_write_handle_reg_tmp = command_write_handle_reg;
        command_write_length_reg_tmp = command_write_length_reg;
        command_write_source_reg_tmp = command_write_source_reg;
        command_write_destination_reg_tmp = command_write_destination_reg;
        command_write_flags_reg_tmp = command_write_flags_reg;
        command_write_network_port_reg_tmp = command_write_network_port_reg;
        stage_handle_reg_tmp = stage_handle_reg;
        stage_length_reg_tmp = stage_length_reg;
        stage_source_reg_tmp = stage_source_reg;
        stage_destination_reg_tmp = stage_destination_reg;
        stage_flags_reg_tmp = stage_flags_reg;
        stage_network_port_reg_tmp = stage_network_port_reg;
        stage_command_armed_reg_tmp = stage_command_armed_reg;
        state_reg_tmp = state_reg;
        operation_reg_tmp = operation_reg;
        active_flags_reg_tmp = active_flags_reg;
        active_network_port_reg_tmp = active_network_port_reg;
        source_reg_tmp = source_reg;
        source_base_reg_tmp = source_base_reg;
        destination_reg_tmp = destination_reg;
        remaining_reg_tmp = remaining_reg;
        beat_data_reg_tmp = beat_data_reg;
        beat_keep_reg_tmp = beat_keep_reg;
        beat_sop_reg_tmp = beat_sop_reg;
        beat_eop_reg_tmp = beat_eop_reg;
        first_beat_reg_tmp = first_beat_reg;
        completed_reg_tmp = completed_reg;
        cache_completed_reg_tmp = cache_completed_reg;
        command_completed_reg_tmp = command_completed_reg;
        command_issued_reg_tmp = command_issued_reg;
        command_lock_reg_tmp = command_lock_reg;
        clear_completed_reg_tmp = clear_completed_reg;
        clear_address_reg_tmp = clear_address_reg;
        clear_notify_armed_reg_tmp = clear_notify_armed_reg;
        cache_invalidate_count_reg_tmp = cache_invalidate_count_reg;
        last_operation_reg_tmp = last_operation_reg;
        protocol_error_reg_tmp = protocol_error_reg;
        protocol_error_reason_reg_tmp = protocol_error_reason_reg;
        prefetch_state_reg_tmp = prefetch_state_reg;
        prefetch_handle_reg_tmp = prefetch_handle_reg;
        prefetch_length_reg_tmp = prefetch_length_reg;
        prefetch_destination_reg_tmp = prefetch_destination_reg;
        prefetch_remaining_reg_tmp = prefetch_remaining_reg;
        prefetch_first_reg_tmp = prefetch_first_reg;
        write_addr_reg_tmp = write_addr_reg;
        write_id_reg_tmp = write_id_reg;
        write_addr_valid_reg_tmp = write_addr_valid_reg;
        write_response_valid_reg_tmp = write_response_valid_reg;
        write_aw_seen_reg_tmp = write_aw_seen_reg;
        write_aw_seen_addr_reg_tmp = write_aw_seen_addr_reg;
        write_aw_seen_id_reg_tmp = write_aw_seen_id_reg;
        read_id_reg_tmp = read_id_reg;
        read_addr_reg_tmp = read_addr_reg;
        read_pending_reg_tmp = read_pending_reg;
        read_data_reg_tmp = read_data_reg;
        read_valid_reg_tmp = read_valid_reg;
        backing_head_reg_tmp = backing_head_reg;
        backing_tail_reg_tmp = backing_tail_reg;
        backing_count_reg_tmp = backing_count_reg;
        backing_state_reg_tmp = backing_state_reg;
        backing_completed_reg_tmp = backing_completed_reg;
        post_clear_head_reg_tmp = post_clear_head_reg;
        post_clear_tail_reg_tmp = post_clear_tail_reg;
        post_clear_count_reg_tmp = post_clear_count_reg;

        _work(reset);

        command_head_reg <= command_head_reg_tmp;
        command_tail_reg <= command_tail_reg_tmp;
        command_count_reg <= command_count_reg_tmp;
        command_write_pending_reg <= command_write_pending_reg_tmp;
        command_write_handle_reg <= command_write_handle_reg_tmp;
        command_write_length_reg <= command_write_length_reg_tmp;
        command_write_source_reg <= command_write_source_reg_tmp;
        command_write_destination_reg <= command_write_destination_reg_tmp;
        command_write_flags_reg <= command_write_flags_reg_tmp;
        command_write_network_port_reg <= command_write_network_port_reg_tmp;
        stage_handle_reg <= stage_handle_reg_tmp;
        stage_length_reg <= stage_length_reg_tmp;
        stage_source_reg <= stage_source_reg_tmp;
        stage_destination_reg <= stage_destination_reg_tmp;
        stage_flags_reg <= stage_flags_reg_tmp;
        stage_network_port_reg <= stage_network_port_reg_tmp;
        stage_command_armed_reg <= stage_command_armed_reg_tmp;
        state_reg <= state_reg_tmp;
        operation_reg <= operation_reg_tmp;
        active_flags_reg <= active_flags_reg_tmp;
        active_network_port_reg <= active_network_port_reg_tmp;
        source_reg <= source_reg_tmp;
        source_base_reg <= source_base_reg_tmp;
        destination_reg <= destination_reg_tmp;
        remaining_reg <= remaining_reg_tmp;
        beat_data_reg <= beat_data_reg_tmp;
        beat_keep_reg <= beat_keep_reg_tmp;
        beat_sop_reg <= beat_sop_reg_tmp;
        beat_eop_reg <= beat_eop_reg_tmp;
        first_beat_reg <= first_beat_reg_tmp;
        completed_reg <= completed_reg_tmp;
        cache_completed_reg <= cache_completed_reg_tmp;
        command_completed_reg <= command_completed_reg_tmp;
        command_issued_reg <= command_issued_reg_tmp;
        command_lock_reg <= command_lock_reg_tmp;
        clear_completed_reg <= clear_completed_reg_tmp;
        clear_address_reg <= clear_address_reg_tmp;
        clear_notify_armed_reg <= clear_notify_armed_reg_tmp;
        cache_invalidate_count_reg <= cache_invalidate_count_reg_tmp;
        last_operation_reg <= last_operation_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
        protocol_error_reason_reg <= protocol_error_reason_reg_tmp;
        prefetch_state_reg <= prefetch_state_reg_tmp;
        prefetch_handle_reg <= prefetch_handle_reg_tmp;
        prefetch_length_reg <= prefetch_length_reg_tmp;
        prefetch_destination_reg <= prefetch_destination_reg_tmp;
        prefetch_remaining_reg <= prefetch_remaining_reg_tmp;
        prefetch_first_reg <= prefetch_first_reg_tmp;
        write_addr_reg <= write_addr_reg_tmp;
        write_id_reg <= write_id_reg_tmp;
        write_addr_valid_reg <= write_addr_valid_reg_tmp;
        write_response_valid_reg <= write_response_valid_reg_tmp;
        write_aw_seen_reg <= write_aw_seen_reg_tmp;
        write_aw_seen_addr_reg <= write_aw_seen_addr_reg_tmp;
        write_aw_seen_id_reg <= write_aw_seen_id_reg_tmp;
        read_id_reg <= read_id_reg_tmp;
        read_addr_reg <= read_addr_reg_tmp;
        read_pending_reg <= read_pending_reg_tmp;
        read_data_reg <= read_data_reg_tmp;
        read_valid_reg <= read_valid_reg_tmp;
        backing_head_reg <= backing_head_reg_tmp;
        backing_tail_reg <= backing_tail_reg_tmp;
        backing_count_reg <= backing_count_reg_tmp;
        backing_state_reg <= backing_state_reg_tmp;
        backing_completed_reg <= backing_completed_reg_tmp;
        post_clear_head_reg <= post_clear_head_reg_tmp;
        post_clear_tail_reg <= post_clear_tail_reg_tmp;
        post_clear_count_reg <= post_clear_count_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
