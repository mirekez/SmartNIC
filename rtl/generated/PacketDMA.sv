`default_nettype none

import Predef_pkg::*;
import PacketDMA_Command_pkg::*;
import PacketDMA_Register_pkg::*;
import PacketDmaState_pkg::*;
import PacketDmaError_pkg::*;
import PacketDmaOperation_pkg::*;


module PacketDMA #(
    parameter HANDLE_BITS = 'h10
,   parameter FRAME_LENGTH_BITS = 'hE
,   parameter CMD_DEPTH = 'h8
,   parameter AXI_ADDR_WIDTH = 'h20
,   parameter AXI_ID_WIDTH = 'h4
,   parameter AXI_DATA_WIDTH = 'h100
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
,   output wire busy_out
,   output wire command_ready_out
,   input wire descriptor_command_valid_in
,   input wire[HANDLE_BITS-1:0] descriptor_command_handle_in
,   input wire[FRAME_LENGTH_BITS-1:0] descriptor_command_length_in
,   input wire descriptor_command_system_in
,   output wire[32-1:0] completed_count_out
,   output wire[2-1:0] last_operation_out
,   output wire protocol_error_out
,   output wire[4-1:0] protocol_error_reason_out
);
    localparam  AXI_BYTES = AXI_DATA_WIDTH/'h8;
    localparam  CMD_PTR_BITS = (CMD_DEPTH<='h1) ? ('h1) : ($clog2(CMD_DEPTH));
    localparam  CMD_COUNT_BITS = $clog2(CMD_DEPTH + 'h1);
    localparam  COMMAND_PUSH = 'h1;
    localparam  FLAG_OPERATION_MASK = 'h3;
    localparam  FLAG_CACHE_ALLOCATE = 'h4;
    localparam  FLAG_NETWORK_DISCARD = 'h8;
    localparam  FLAG_NETWORK_SYSTEM = 'h10;
    localparam  STATUS_BUSY = 'h1;
    localparam  STATUS_CMD_READY = 'h2;
    localparam  STATUS_ERROR = 'h4;


    // regs and combs
    PacketDMA_Command command_reg[CMD_DEPTH];
    reg[CMD_PTR_BITS-1:0] command_head_reg;
    reg[CMD_PTR_BITS-1:0] command_tail_reg;
    reg[CMD_COUNT_BITS-1:0] command_count_reg;
    reg[HANDLE_BITS-1:0] stage_handle_reg;
    reg[FRAME_LENGTH_BITS-1:0] stage_length_reg;
    reg[32-1:0] stage_source_reg;
    reg[32-1:0] stage_destination_reg;
    reg[8-1:0] stage_flags_reg;
    reg[8-1:0] state_reg;
    reg[2-1:0] operation_reg;
    reg[8-1:0] active_flags_reg;
    reg[AXI_ADDR_WIDTH-1:0] source_reg;
    reg[AXI_ADDR_WIDTH-1:0] destination_reg;
    reg[FRAME_LENGTH_BITS-1:0] remaining_reg;
    reg[AXI_DATA_WIDTH-1:0] beat_data_reg;
    reg[AXI_BYTES-1:0] beat_keep_reg;
    reg beat_sop_reg;
    reg beat_eop_reg;
    reg first_beat_reg;
    reg[32-1:0] completed_reg;
    reg[2-1:0] last_operation_reg;
    reg protocol_error_reg;
    reg[4-1:0] protocol_error_reason_reg;
    reg[AXI_ADDR_WIDTH-1:0] write_addr_reg;
    reg[AXI_ID_WIDTH-1:0] write_id_reg;
    reg write_addr_valid_reg;
    reg write_response_valid_reg;
    reg[AXI_ID_WIDTH-1:0] read_id_reg;
    reg[AXI_DATA_WIDTH-1:0] read_data_reg;
    reg read_valid_reg;
    logic[HANDLE_BITS-1:0] current_handle_comb;
    logic[FRAME_LENGTH_BITS-1:0] current_length_comb;
    logic[AXI_BYTES-1:0] output_keep_comb;

    // members

    // tmp variables
    PacketDMA_Command command_reg_tmp[CMD_DEPTH];
    logic[CMD_PTR_BITS-1:0] command_head_reg_tmp;
    logic[CMD_PTR_BITS-1:0] command_tail_reg_tmp;
    logic[CMD_COUNT_BITS-1:0] command_count_reg_tmp;
    logic[HANDLE_BITS-1:0] stage_handle_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] stage_length_reg_tmp;
    logic[32-1:0] stage_source_reg_tmp;
    logic[32-1:0] stage_destination_reg_tmp;
    logic[8-1:0] stage_flags_reg_tmp;
    logic[8-1:0] state_reg_tmp;
    logic[2-1:0] operation_reg_tmp;
    logic[8-1:0] active_flags_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] source_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] destination_reg_tmp;
    logic[FRAME_LENGTH_BITS-1:0] remaining_reg_tmp;
    logic[AXI_DATA_WIDTH-1:0] beat_data_reg_tmp;
    logic[AXI_BYTES-1:0] beat_keep_reg_tmp;
    logic beat_sop_reg_tmp;
    logic beat_eop_reg_tmp;
    logic first_beat_reg_tmp;
    logic[32-1:0] completed_reg_tmp;
    logic[2-1:0] last_operation_reg_tmp;
    logic protocol_error_reg_tmp;
    logic[4-1:0] protocol_error_reason_reg_tmp;
    logic[AXI_ADDR_WIDTH-1:0] write_addr_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] write_id_reg_tmp;
    logic write_addr_valid_reg_tmp;
    logic write_response_valid_reg_tmp;
    logic[AXI_ID_WIDTH-1:0] read_id_reg_tmp;
    logic[AXI_DATA_WIDTH-1:0] read_data_reg_tmp;
    logic read_valid_reg_tmp;


    function PacketDMA_Command current_command ();
        PacketDMA_Command command;
        command = 0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            command = command_reg[unsigned'(32'(command_head_reg))];
        end
        return command;
    endfunction

    always_comb begin : current_handle_comb_func  // current_handle_comb_func
        current_handle_comb = 'h0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            current_handle_comb = command_reg[unsigned'(32'(command_head_reg))].handle;
        end
    end

    always_comb begin : current_length_comb_func  // current_length_comb_func
        current_length_comb = 'h0;
        if (unsigned'(32'(command_count_reg)) != 'h0) begin
            current_length_comb = command_reg[unsigned'(32'(command_head_reg))].length;
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
        if (address == PacketDMA_Register_pkg::REG_RX_HANDLE) begin
            return unsigned'(32'(stage_handle_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_LENGTH) begin
            return unsigned'(32'(stage_length_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_DESTINATION) begin
            return unsigned'(32'(stage_destination_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_SOURCE) begin
            return unsigned'(32'(stage_source_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_FLAGS) begin
            return unsigned'(32'(stage_flags_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_STATUS) begin
            return (((((unsigned'(32'(state_reg)) != PacketDmaState_pkg::PACKET_DMA_IDLE)) ? (STATUS_BUSY) : ('h0)) | (((unsigned'(32'(command_count_reg)) < CMD_DEPTH)) ? (STATUS_CMD_READY) : ('h0))) | ((protocol_error_reg) ? (STATUS_ERROR) : ('h0))) | ((unsigned'(32'(command_count_reg)) <<< 'h8));
        end
        if (address == PacketDMA_Register_pkg::REG_COMPLETED) begin
            return unsigned'(32'(completed_reg));
        end
        if (address == PacketDMA_Register_pkg::REG_LAST_OPERATION) begin
            return unsigned'(32'(last_operation_reg));
        end
        return 'h0;
    endfunction

    function logic[256-1:0] register_read_value ();
        logic[256-1:0] data;
        logic[31:0] index;
        logic[31:0] address;
        logic[31:0] lane;
        logic[31:0] value;
        data = 'h0;
        address = unsigned'(32'(mmio__araddr_in));
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

    generate  // _assign
        assign mmio__awready_out = !write_addr_valid_reg && !write_response_valid_reg;
        assign mmio__wready_out = write_addr_valid_reg && !write_response_valid_reg;
        assign mmio__bvalid_out = write_response_valid_reg;
        assign mmio__bid_out = write_id_reg;
        assign mmio__arready_out = !read_valid_reg;
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
        assign l2_dma__arvalid_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS;
        assign l2_dma__araddr_out = source_reg;
        assign l2_dma__arid_out = unsigned'(AXI_ID_WIDTH'(unsigned'(AXI_ID_WIDTH'('h0))));
        assign l2_dma__rready_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA;
        assign rx_read_valid_out = unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_ISSUE_NETWORK_READ;
        assign rx_read_handle_out = current_handle_comb;
        assign rx_read_length_out = current_length_comb;
        assign rx_ready_out = ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) == 'h0) || system_tx_ready_in));
        assign system_rx_ready_out = (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_SYSTEM_CPU);
        assign system_tx_valid_out = (((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_SYSTEM))) || (((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0)) && rx_valid_in));
        assign network_tx_valid_out = (unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_CPU_NETWORK);
        assign system_tx_data_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_data_in) : (beat_data_reg);
        assign network_tx_data_out = beat_data_reg;
        assign system_tx_keep_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_keep_in) : (beat_keep_reg);
        assign network_tx_keep_out = beat_keep_reg;
        assign system_tx_sop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_sop_in) : (beat_sop_reg);
        assign network_tx_sop_out = beat_sop_reg;
        assign system_tx_eop_out = ((((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_WAIT_INPUT) && (unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU)) && (((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0))) ? (rx_eop_in) : (beat_eop_reg);
        assign network_tx_eop_out = beat_eop_reg;
        assign busy_out = (unsigned'(32'(state_reg)) != PacketDmaState_pkg::PACKET_DMA_IDLE) || (unsigned'(32'(command_count_reg)) != 'h0);
        assign command_ready_out = unsigned'(32'(command_count_reg)) < CMD_DEPTH;
        assign completed_count_out = completed_reg;
        assign last_operation_out = last_operation_reg;
        assign protocol_error_out = protocol_error_reg;
        assign protocol_error_reason_out = protocol_error_reason_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] slot;
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
        logic[256-1:0] input_data;
        logic[32-1:0] input_keep;
        PacketDMA_Command command;
        PacketDMA_Command staged;
        count=unsigned'(32'(command_count_reg));
        push=0;
        pop=0;
        descriptor_push=0;
        command = current_command();
        if (mmio__awvalid_in && mmio__awready_out) begin
            write_addr_reg_tmp = mmio__awaddr_in;
            write_id_reg_tmp = mmio__awid_in;
            write_addr_valid_reg_tmp = unsigned'(1'(1));
        end
        if (mmio__wvalid_in && mmio__wready_out) begin
            address=unsigned'(32'(write_addr_reg)) & ~'h3;
            value=write_value();
            if (address == PacketDMA_Register_pkg::REG_RX_HANDLE) begin
                stage_handle_reg_tmp = value;
            end
            else begin
                if (address == PacketDMA_Register_pkg::REG_LENGTH) begin
                    stage_length_reg_tmp = value;
                end
                else begin
                    if (address == PacketDMA_Register_pkg::REG_SOURCE) begin
                        stage_source_reg_tmp = unsigned'(32'(value));
                    end
                    else begin
                        if (address == PacketDMA_Register_pkg::REG_DESTINATION) begin
                            stage_destination_reg_tmp = unsigned'(32'(value));
                        end
                        else begin
                            if (address == PacketDMA_Register_pkg::REG_FLAGS) begin
                                stage_flags_reg_tmp = unsigned'(8'(value));
                            end
                            else begin
                                if ((address == PacketDMA_Register_pkg::REG_COMMAND) && (((value & COMMAND_PUSH)) != 'h0)) begin
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
                                            if (((((unsigned'(32'(stage_flags_reg)) & ~((((FLAG_OPERATION_MASK | FLAG_CACHE_ALLOCATE) | FLAG_NETWORK_DISCARD) | FLAG_NETWORK_SYSTEM)))) != 'h0) || (((((unsigned'(32'(stage_flags_reg)) & ((FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)))) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_OPERATION_MASK)) != PacketDmaOperation_pkg::DMA_NETWORK_CPU)))) || (((((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_DISCARD)) != 'h0) && (((unsigned'(32'(stage_flags_reg)) & FLAG_NETWORK_SYSTEM)) != 'h0)))) begin
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
            write_addr_valid_reg_tmp = unsigned'(1'(0));
            write_response_valid_reg_tmp = unsigned'(1'(1));
        end
        if (write_response_valid_reg && mmio__bready_in) begin
            write_response_valid_reg_tmp = unsigned'(1'(0));
        end
        if (mmio__arvalid_in && mmio__arready_out) begin
            read_id_reg_tmp = mmio__arid_in;
            read_data_reg_tmp = register_read_value();
            read_valid_reg_tmp = unsigned'(1'(1));
        end
        if (read_valid_reg && mmio__rready_in) begin
            read_valid_reg_tmp = unsigned'(1'(0));
        end
        if ((descriptor_command_valid_in && (count < CMD_DEPTH)) && !push) begin
            staged = 0;
            staged.handle = descriptor_command_handle_in;
            staged.length = descriptor_command_length_in;
            staged.destination = unsigned'(32'h0);
            staged.flags = unsigned'(8'(PacketDmaOperation_pkg::DMA_NETWORK_CPU | ((descriptor_command_system_in) ? (FLAG_NETWORK_SYSTEM) : (FLAG_NETWORK_DISCARD))));
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
            end
            command_reg_tmp[unsigned'(32'(command_tail_reg))] = staged;
            command_tail_reg_tmp = ((unsigned'(32'(command_tail_reg)) + 'h1)) & ((CMD_DEPTH - 'h1));
            count=count+1;
        end
        if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_IDLE) && (count != 'h0)) begin
            if ((unsigned'(32'(command_count_reg)) == 'h0) && push) begin
                command = staged;
            end
            operation_reg_tmp = unsigned'(32'(command.flags)) & FLAG_OPERATION_MASK;
            active_flags_reg_tmp = command.flags;
            source_reg_tmp = command.source;
            destination_reg_tmp = command.destination;
            remaining_reg_tmp = command.length;
            first_beat_reg_tmp = unsigned'(1'(1));
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
                    if ((unsigned'(32'(operation_reg)) == PacketDmaOperation_pkg::DMA_NETWORK_CPU) && (((unsigned'(32'(active_flags_reg)) & ((FLAG_NETWORK_DISCARD | FLAG_NETWORK_SYSTEM)))) != 'h0)) begin
                        if (input_valid && (((((unsigned'(32'(active_flags_reg)) & FLAG_NETWORK_SYSTEM)) == 'h0) || system_tx_ready_in))) begin
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
                        if (input_valid) begin
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
                                if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS) && l2_dma__arready_in) begin
                                    state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_READ_DATA));
                                end
                                else begin
                                    if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_READ_DATA) && l2_dma__rvalid_in) begin
                                        beat_data_reg_tmp = l2_dma__rdata_in;
                                        beat_keep_reg_tmp = output_keep_comb;
                                        beat_sop_reg_tmp = first_beat_reg;
                                        beat_eop_reg_tmp = unsigned'(1'(remaining_reg<=AXI_BYTES));
                                        state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT));
                                    end
                                    else begin
                                        if ((unsigned'(32'(state_reg)) == PacketDmaState_pkg::PACKET_DMA_SEND_OUTPUT) && output_ready()) begin
                                            if (remaining_reg<=AXI_BYTES) begin
                                                completed_reg_tmp = completed_reg + 'h1;
                                                last_operation_reg_tmp = operation_reg;
                                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_IDLE));
                                                pop=count != 'h0;
                                            end
                                            else begin
                                                source_reg_tmp = source_reg + AXI_BYTES;
                                                remaining_reg_tmp = remaining_reg - AXI_BYTES;
                                                first_beat_reg_tmp = unsigned'(1'(0));
                                                state_reg_tmp = unsigned'(8'(PacketDmaState_pkg::PACKET_DMA_READ_ADDRESS));
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
        if (pop) begin
            command_head_reg_tmp = ((unsigned'(32'(command_head_reg)) + 'h1)) & ((CMD_DEPTH - 'h1));
            --count;
        end
        command_count_reg_tmp = count;
        if (reset) begin
            command_head_reg_tmp = '0;
            command_tail_reg_tmp = '0;
            command_count_reg_tmp = '0;
            stage_handle_reg_tmp = '0;
            stage_length_reg_tmp = '0;
            stage_source_reg_tmp = '0;
            stage_destination_reg_tmp = '0;
            stage_flags_reg_tmp = '0;
            state_reg_tmp = '0;
            operation_reg_tmp = '0;
            active_flags_reg_tmp = '0;
            source_reg_tmp = '0;
            destination_reg_tmp = '0;
            remaining_reg_tmp = '0;
            beat_data_reg_tmp = '0;
            beat_keep_reg_tmp = '0;
            beat_sop_reg_tmp = '0;
            beat_eop_reg_tmp = '0;
            first_beat_reg_tmp = '0;
            completed_reg_tmp = '0;
            last_operation_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            protocol_error_reason_reg_tmp = '0;
            write_addr_reg_tmp = '0;
            write_id_reg_tmp = '0;
            write_addr_valid_reg_tmp = '0;
            write_response_valid_reg_tmp = '0;
            read_id_reg_tmp = '0;
            read_data_reg_tmp = '0;
            read_valid_reg_tmp = '0;
            for (slot='h0;slot < CMD_DEPTH;slot=slot+1) begin
                command_reg_tmp[slot] = '0;
            end
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        command_reg_tmp = command_reg;
        command_head_reg_tmp = command_head_reg;
        command_tail_reg_tmp = command_tail_reg;
        command_count_reg_tmp = command_count_reg;
        stage_handle_reg_tmp = stage_handle_reg;
        stage_length_reg_tmp = stage_length_reg;
        stage_source_reg_tmp = stage_source_reg;
        stage_destination_reg_tmp = stage_destination_reg;
        stage_flags_reg_tmp = stage_flags_reg;
        state_reg_tmp = state_reg;
        operation_reg_tmp = operation_reg;
        active_flags_reg_tmp = active_flags_reg;
        source_reg_tmp = source_reg;
        destination_reg_tmp = destination_reg;
        remaining_reg_tmp = remaining_reg;
        beat_data_reg_tmp = beat_data_reg;
        beat_keep_reg_tmp = beat_keep_reg;
        beat_sop_reg_tmp = beat_sop_reg;
        beat_eop_reg_tmp = beat_eop_reg;
        first_beat_reg_tmp = first_beat_reg;
        completed_reg_tmp = completed_reg;
        last_operation_reg_tmp = last_operation_reg;
        protocol_error_reg_tmp = protocol_error_reg;
        protocol_error_reason_reg_tmp = protocol_error_reason_reg;
        write_addr_reg_tmp = write_addr_reg;
        write_id_reg_tmp = write_id_reg;
        write_addr_valid_reg_tmp = write_addr_valid_reg;
        write_response_valid_reg_tmp = write_response_valid_reg;
        read_id_reg_tmp = read_id_reg;
        read_data_reg_tmp = read_data_reg;
        read_valid_reg_tmp = read_valid_reg;

        _work(reset);

        command_reg <= command_reg_tmp;
        command_head_reg <= command_head_reg_tmp;
        command_tail_reg <= command_tail_reg_tmp;
        command_count_reg <= command_count_reg_tmp;
        stage_handle_reg <= stage_handle_reg_tmp;
        stage_length_reg <= stage_length_reg_tmp;
        stage_source_reg <= stage_source_reg_tmp;
        stage_destination_reg <= stage_destination_reg_tmp;
        stage_flags_reg <= stage_flags_reg_tmp;
        state_reg <= state_reg_tmp;
        operation_reg <= operation_reg_tmp;
        active_flags_reg <= active_flags_reg_tmp;
        source_reg <= source_reg_tmp;
        destination_reg <= destination_reg_tmp;
        remaining_reg <= remaining_reg_tmp;
        beat_data_reg <= beat_data_reg_tmp;
        beat_keep_reg <= beat_keep_reg_tmp;
        beat_sop_reg <= beat_sop_reg_tmp;
        beat_eop_reg <= beat_eop_reg_tmp;
        first_beat_reg <= first_beat_reg_tmp;
        completed_reg <= completed_reg_tmp;
        last_operation_reg <= last_operation_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
        protocol_error_reason_reg <= protocol_error_reason_reg_tmp;
        write_addr_reg <= write_addr_reg_tmp;
        write_id_reg <= write_id_reg_tmp;
        write_addr_valid_reg <= write_addr_valid_reg_tmp;
        write_response_valid_reg <= write_response_valid_reg_tmp;
        read_id_reg <= read_id_reg_tmp;
        read_data_reg <= read_data_reg_tmp;
        read_valid_reg <= read_valid_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
