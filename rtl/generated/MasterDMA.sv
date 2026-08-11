`default_nettype none

import Predef_pkg::*;
import MasterDmaState_pkg::*;
import MasterDmaDirection_pkg::*;


module MasterDMA #(
    parameter ADDR_WIDTH = 'h40
,   parameter DATA_WIDTH = 'h100
,   parameter ID_WIDTH = 'h4
,   parameter LENGTH_BITS = 'h10
 )
 (
    input wire system_clock
,   input wire l2_clock
,   input wire reset
,   input wire command_valid_in
,   output wire command_ready_out
,   input wire command_direction_in
,   input wire[3-1:0] command_queue_in
,   input wire[ADDR_WIDTH-1:0] command_address_in
,   input wire[LENGTH_BITS-1:0] command_length_in
,   input wire command_sop_in
,   input wire command_eop_in
,   input wire queue_input_valid_in
,   input wire[DATA_WIDTH-1:0] queue_input_data_in
,   input wire[DATA_BYTES-1:0] queue_input_keep_in
,   input wire queue_input_sop_in
,   input wire queue_input_eop_in
,   output wire queue_input_ready_out
,   output wire queue_output_valid_out
,   output wire[DATA_WIDTH-1:0] queue_output_data_out
,   output wire[DATA_BYTES-1:0] queue_output_keep_out
,   output wire queue_output_sop_out
,   output wire queue_output_eop_out
,   input wire queue_output_ready_in
,   output wire host__awvalid_out
,   input wire host__awready_in
,   output wire[64-1:0] host__awaddr_out
,   output wire[4-1:0] host__awid_out
,   output wire host__wvalid_out
,   input wire host__wready_in
,   output wire[256-1:0] host__wdata_out
,   output wire[256/'h8-1:0] host__wstrb_out
,   output wire host__wlast_out
,   input wire host__bvalid_in
,   output wire host__bready_out
,   input wire[4-1:0] host__bid_in
,   output wire host__arvalid_out
,   input wire host__arready_in
,   output wire[64-1:0] host__araddr_out
,   output wire[4-1:0] host__arid_out
,   input wire host__rvalid_in
,   output wire host__rready_out
,   input wire[256-1:0] host__rdata_in
,   input wire host__rlast_in
,   input wire[4-1:0] host__rid_in
,   output wire busy_out
,   output wire completion_valid_out
,   output wire[3-1:0] active_queue_out
,   output wire[3-1:0] completion_queue_out
,   output wire completion_direction_out
,   output wire[32-1:0] completed_count_out
,   output wire protocol_error_out
);
    parameter  DATA_BYTES = DATA_WIDTH/'h8;


    // regs and combs
    reg[8-1:0] state_reg;
    reg direction_reg;
    reg[3-1:0] queue_reg;
    reg[ADDR_WIDTH-1:0] address_reg;
    reg[LENGTH_BITS-1:0] remaining_reg;
    reg command_sop_reg;
    reg command_eop_reg;
    reg first_beat_reg;
    reg[DATA_WIDTH-1:0] beat_data_reg;
    reg[DATA_BYTES-1:0] beat_keep_reg;
    reg beat_sop_reg;
    reg beat_eop_reg;
    reg completion_valid_reg;
    reg[3-1:0] completion_queue_reg;
    reg completion_direction_reg;
    reg[32-1:0] completed_reg;
    reg protocol_error_reg;
    logic[DATA_BYTES-1:0] read_keep_comb;

    // members

    // tmp variables
    logic[8-1:0] state_reg_tmp;
    logic direction_reg_tmp;
    logic[3-1:0] queue_reg_tmp;
    logic[ADDR_WIDTH-1:0] address_reg_tmp;
    logic[LENGTH_BITS-1:0] remaining_reg_tmp;
    logic command_sop_reg_tmp;
    logic command_eop_reg_tmp;
    logic first_beat_reg_tmp;
    logic[DATA_WIDTH-1:0] beat_data_reg_tmp;
    logic[DATA_BYTES-1:0] beat_keep_reg_tmp;
    logic beat_sop_reg_tmp;
    logic beat_eop_reg_tmp;
    logic completion_valid_reg_tmp;
    logic[3-1:0] completion_queue_reg_tmp;
    logic completion_direction_reg_tmp;
    logic[32-1:0] completed_reg_tmp;
    logic protocol_error_reg_tmp;


    always_comb begin : read_keep_comb_func  // read_keep_comb_func
        logic[31:0] _byte;
        read_keep_comb = 'h0;
        for (_byte='h0;_byte < DATA_BYTES;_byte=_byte+1) begin
            read_keep_comb[_byte] = _byte < unsigned'(32'(remaining_reg));
        end
    end

    function logic[31:0] kept_bytes (input logic[32-1:0] keep);
        logic[31:0] _byte;
        logic[31:0] count;
        logic gap;
        count='h0;
        gap=0;
        for (_byte='h0;_byte < DATA_BYTES;_byte=_byte+1) begin
            if (keep[_byte]) begin
                if (gap) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                end
                count=count+1;
            end
            else begin
                gap=1;
            end
        end
        return count;
    endfunction

    task complete_command ();
    begin: complete_command
        completion_valid_reg_tmp = unsigned'(1'(1));
        completion_queue_reg_tmp = queue_reg;
        completion_direction_reg_tmp = direction_reg;
        completed_reg_tmp = completed_reg + 'h1;
        state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_IDLE));
    end
    endtask

    generate  // _assign
        assign command_ready_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_IDLE;
        assign queue_input_ready_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WAIT_QUEUE;
        assign queue_output_valid_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_SEND_QUEUE;
        assign queue_output_data_out = beat_data_reg;
        assign queue_output_keep_out = beat_keep_reg;
        assign queue_output_sop_out = beat_sop_reg;
        assign queue_output_eop_out = beat_eop_reg;
        assign host__awvalid_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_ADDRESS;
        assign host__awaddr_out = address_reg;
        assign host__awid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
        assign host__wvalid_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_DATA;
        assign host__wdata_out = beat_data_reg;
        assign host__wstrb_out = beat_keep_reg;
        assign host__wlast_out = 1;
        assign host__bready_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_RESPONSE;
        assign host__arvalid_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_READ_ADDRESS;
        assign host__araddr_out = address_reg;
        assign host__arid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'('h0))));
        assign host__rready_out = unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_READ_DATA;
        assign busy_out = unsigned'(32'(state_reg)) != MasterDmaState_pkg::MASTER_DMA_IDLE;
        assign completion_valid_out = completion_valid_reg;
        assign active_queue_out = queue_reg;
        assign completion_queue_out = completion_queue_reg;
        assign completion_direction_out = completion_direction_reg;
        assign completed_count_out = completed_reg;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] bytes;
        completion_valid_reg_tmp = unsigned'(1'(0));
        if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_IDLE) && command_valid_in) begin
            direction_reg_tmp = unsigned'(1'(command_direction_in));
            queue_reg_tmp = command_queue_in;
            address_reg_tmp = command_address_in;
            remaining_reg_tmp = command_length_in;
            command_sop_reg_tmp = unsigned'(1'(command_sop_in));
            command_eop_reg_tmp = unsigned'(1'(command_eop_in));
            first_beat_reg_tmp = unsigned'(1'(1));
            if (((unsigned'(32'(command_length_in)) == 'h0) || (((unsigned'(64'(command_address_in)) & 'h3)) != 'h0)) || (((unsigned'(32'(command_length_in)) & 'h3)) != 'h0)) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            else begin
                if (command_direction_in == MasterDmaDirection_pkg::MASTER_DMA_QUEUE_TO_HOST) begin
                    state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_WAIT_QUEUE));
                end
                else begin
                    state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_READ_ADDRESS));
                end
            end
        end
        else begin
            if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WAIT_QUEUE) && queue_input_valid_in) begin
                beat_data_reg_tmp = queue_input_data_in;
                beat_keep_reg_tmp = queue_input_keep_in;
                beat_sop_reg_tmp = unsigned'(1'(queue_input_sop_in));
                beat_eop_reg_tmp = unsigned'(1'(queue_input_eop_in));
                if (first_beat_reg != queue_input_sop_in) begin
                    protocol_error_reg_tmp = unsigned'(1'(1));
                end
                state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_WRITE_ADDRESS));
            end
            else begin
                if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_ADDRESS) && host__awready_in) begin
                    state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_WRITE_DATA));
                end
                else begin
                    if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_DATA) && host__wready_in) begin
                        state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_WRITE_RESPONSE));
                    end
                    else begin
                        if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_WRITE_RESPONSE) && host__bvalid_in) begin
                            bytes=kept_bytes(beat_keep_reg);
                            if ((bytes == 'h0) || (bytes > unsigned'(32'(remaining_reg)))) begin
                                protocol_error_reg_tmp = unsigned'(1'(1));
                            end
                            if (beat_eop_reg) begin
                                if (bytes != unsigned'(32'(remaining_reg))) begin
                                    protocol_error_reg_tmp = unsigned'(1'(1));
                                end
                                complete_command();
                            end
                            else begin
                                address_reg_tmp = address_reg + bytes;
                                remaining_reg_tmp = remaining_reg - bytes;
                                first_beat_reg_tmp = unsigned'(1'(0));
                                state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_WAIT_QUEUE));
                            end
                        end
                        else begin
                            if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_READ_ADDRESS) && host__arready_in) begin
                                state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_READ_DATA));
                            end
                            else begin
                                if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_READ_DATA) && host__rvalid_in) begin
                                    beat_data_reg_tmp = host__rdata_in;
                                    beat_keep_reg_tmp = read_keep_comb;
                                    beat_sop_reg_tmp = unsigned'(1'(first_beat_reg && command_sop_reg));
                                    beat_eop_reg_tmp = unsigned'(1'(remaining_reg<=DATA_BYTES && command_eop_reg));
                                    state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_SEND_QUEUE));
                                end
                                else begin
                                    if ((unsigned'(32'(state_reg)) == MasterDmaState_pkg::MASTER_DMA_SEND_QUEUE) && queue_output_ready_in) begin
                                        if (remaining_reg<=DATA_BYTES) begin
                                            complete_command();
                                        end
                                        else begin
                                            address_reg_tmp = address_reg + DATA_BYTES;
                                            remaining_reg_tmp = remaining_reg - DATA_BYTES;
                                            first_beat_reg_tmp = unsigned'(1'(0));
                                            state_reg_tmp = unsigned'(8'(MasterDmaState_pkg::MASTER_DMA_READ_ADDRESS));
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if (reset) begin
            state_reg_tmp = '0;
            direction_reg_tmp = '0;
            queue_reg_tmp = '0;
            address_reg_tmp = '0;
            remaining_reg_tmp = '0;
            command_sop_reg_tmp = '0;
            command_eop_reg_tmp = '0;
            first_beat_reg_tmp = '0;
            beat_data_reg_tmp = '0;
            beat_keep_reg_tmp = '0;
            beat_sop_reg_tmp = '0;
            beat_eop_reg_tmp = '0;
            completion_valid_reg_tmp = '0;
            completion_queue_reg_tmp = '0;
            completion_direction_reg_tmp = '0;
            completed_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge system_clock) begin
        state_reg_tmp = state_reg;
        direction_reg_tmp = direction_reg;
        queue_reg_tmp = queue_reg;
        address_reg_tmp = address_reg;
        remaining_reg_tmp = remaining_reg;
        command_sop_reg_tmp = command_sop_reg;
        command_eop_reg_tmp = command_eop_reg;
        first_beat_reg_tmp = first_beat_reg;
        beat_data_reg_tmp = beat_data_reg;
        beat_keep_reg_tmp = beat_keep_reg;
        beat_sop_reg_tmp = beat_sop_reg;
        beat_eop_reg_tmp = beat_eop_reg;
        completion_valid_reg_tmp = completion_valid_reg;
        completion_queue_reg_tmp = completion_queue_reg;
        completion_direction_reg_tmp = completion_direction_reg;
        completed_reg_tmp = completed_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work(reset);

        state_reg <= state_reg_tmp;
        direction_reg <= direction_reg_tmp;
        queue_reg <= queue_reg_tmp;
        address_reg <= address_reg_tmp;
        remaining_reg <= remaining_reg_tmp;
        command_sop_reg <= command_sop_reg_tmp;
        command_eop_reg <= command_eop_reg_tmp;
        first_beat_reg <= first_beat_reg_tmp;
        beat_data_reg <= beat_data_reg_tmp;
        beat_keep_reg <= beat_keep_reg_tmp;
        beat_sop_reg <= beat_sop_reg_tmp;
        beat_eop_reg <= beat_eop_reg_tmp;
        completion_valid_reg <= completion_valid_reg_tmp;
        completion_queue_reg <= completion_queue_reg_tmp;
        completion_direction_reg <= completion_direction_reg_tmp;
        completed_reg <= completed_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
