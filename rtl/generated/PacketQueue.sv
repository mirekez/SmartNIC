`default_nettype none

import Predef_pkg::*;


module PacketQueue #(
    parameter DEPTH = 'h100
,   parameter DATA_WIDTH = 'h100
,   parameter LENGTH_BITS = 'h10
 )
 (
    input wire l2_clock
,   input wire system_clock
,   input wire reset
,   input wire write_valid_in
,   input wire[DATA_WIDTH-1:0] write_data_in
,   input wire[DATA_BYTES-1:0] write_keep_in
,   input wire write_sop_in
,   input wire write_eop_in
,   output wire write_ready_out
,   output wire read_valid_out
,   output wire[DATA_WIDTH-1:0] read_data_out
,   output wire[DATA_BYTES-1:0] read_keep_out
,   output wire read_sop_out
,   output wire read_eop_out
,   input wire read_ready_in
,   output wire empty_out
,   output wire full_out
,   output wire[LENGTH_BITS-1:0] packet_length_out
,   output wire[COUNT_BITS-1:0] packet_count_out
,   output wire protocol_error_out
,   input wire clear_in
);
    parameter  DATA_BYTES = DATA_WIDTH/'h8;
    parameter  ENTRY_BITS = (DATA_WIDTH + DATA_BYTES) + 'h2;
    parameter  ENTRY_BYTES = ((ENTRY_BITS + 'h7))/'h8;
    parameter  COUNT_BITS = $clog2(DEPTH + 'h1);


    // regs and combs
    reg[LENGTH_BITS-1:0] assembling_length_reg;
    reg[COUNT_BITS-1:0] packet_count_reg;
    reg assembling_reg;
    reg protocol_error_reg;
    logic[ENTRY_BYTES*'h8-1:0] write_entry_comb;
    logic[LENGTH_BITS-1:0] write_length_comb;

    // members
    wire data_fifo__write_in;
    wire[ENTRY_BYTES*'h8-1:0] data_fifo__write_data_in;
    wire data_fifo__read_in;
    wire[ENTRY_BYTES*'h8-1:0] data_fifo__read_data_out;
    wire data_fifo__empty_out;
    wire data_fifo__full_out;
    wire data_fifo__clear_in;
    wire data_fifo__afull_out;
    Fifo #(
        ENTRY_BYTES
,       DEPTH
,       1
,       0
    ) data_fifo (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_in(data_fifo__write_in)
,       .write_data_in(data_fifo__write_data_in)
,       .read_in(data_fifo__read_in)
,       .read_data_out(data_fifo__read_data_out)
,       .empty_out(data_fifo__empty_out)
,       .full_out(data_fifo__full_out)
,       .clear_in(data_fifo__clear_in)
,       .afull_out(data_fifo__afull_out)
    );
    wire length_fifo__write_in;
    wire[(LENGTH_BITS/'h8)*'h8-1:0] length_fifo__write_data_in;
    wire length_fifo__read_in;
    wire[(LENGTH_BITS/'h8)*'h8-1:0] length_fifo__read_data_out;
    wire length_fifo__empty_out;
    wire length_fifo__full_out;
    wire length_fifo__clear_in;
    wire length_fifo__afull_out;
    Fifo #(
        LENGTH_BITS/'h8
,       DEPTH
,       1
,       0
    ) length_fifo (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_in(length_fifo__write_in)
,       .write_data_in(length_fifo__write_data_in)
,       .read_in(length_fifo__read_in)
,       .read_data_out(length_fifo__read_data_out)
,       .empty_out(length_fifo__empty_out)
,       .full_out(length_fifo__full_out)
,       .clear_in(length_fifo__clear_in)
,       .afull_out(length_fifo__afull_out)
    );

    // tmp variables
    logic[LENGTH_BITS-1:0] assembling_length_reg_tmp;
    logic[COUNT_BITS-1:0] packet_count_reg_tmp;
    logic assembling_reg_tmp;
    logic protocol_error_reg_tmp;


    always_comb begin : write_entry_comb_func  // write_entry_comb_func
        write_entry_comb = 'h0;
        write_entry_comb['h0 +:DATA_WIDTH - 'h1 - 'h0 + 1] = write_data_in;
        write_entry_comb[DATA_WIDTH +:(DATA_WIDTH + DATA_BYTES) - 'h1 - DATA_WIDTH + 1] = write_keep_in;
        write_entry_comb[DATA_WIDTH + DATA_BYTES] = write_sop_in;
        write_entry_comb[(DATA_WIDTH + DATA_BYTES) + 'h1] = write_eop_in;
    end

    function logic[31:0] input_bytes ();
        logic[31:0] _byte;
        logic[31:0] count;
        count='h0;
        for (_byte='h0;_byte < DATA_BYTES;_byte=_byte+1) begin
            if (write_keep_in[_byte]) begin
                count=count+1;
            end
        end
        return count;
    endfunction

    function logic input_keep_contiguous ();
        logic[31:0] _byte;
        logic gap;
        gap=0;
        for (_byte='h0;_byte < DATA_BYTES;_byte=_byte+1) begin
            if (write_keep_in[_byte] && gap) begin
                return 0;
            end
            if (!write_keep_in[_byte]) begin
                gap=1;
            end
        end
        return 1;
    endfunction

    always_comb begin : write_length_comb_func  // write_length_comb_func
        write_length_comb = ((write_sop_in) ? ('h0) : (unsigned'(32'(assembling_length_reg)))) + input_bytes();
    end

    generate  // _assign
        assign data_fifo__write_data_in = write_entry_comb;
        assign data_fifo__clear_in = clear_in;
        assign length_fifo__write_data_in = write_length_comb;
        assign length_fifo__clear_in = clear_in;
        assign write_ready_out = !data_fifo__full_out && (((!write_valid_in || !write_eop_in) || !length_fifo__full_out));
        assign read_valid_out = !data_fifo__empty_out && !length_fifo__empty_out;
        assign read_data_out = data_fifo__read_data_out['h0 +:DATA_WIDTH - 'h1 - 'h0 + 1];
        assign read_keep_out = data_fifo__read_data_out[DATA_WIDTH +:(DATA_WIDTH + DATA_BYTES) - 'h1 - DATA_WIDTH + 1];
        assign read_sop_out = data_fifo__read_data_out[DATA_WIDTH + DATA_BYTES];
        assign read_eop_out = data_fifo__read_data_out[(DATA_WIDTH + DATA_BYTES) + 'h1];
        assign empty_out = unsigned'(32'(packet_count_reg)) == 'h0;
        assign full_out = data_fifo__full_out;
        assign packet_length_out = unsigned'(LENGTH_BITS'(unsigned'(LENGTH_BITS'(length_fifo__read_data_out))));
        assign packet_count_out = packet_count_reg;
        assign protocol_error_out = protocol_error_reg;
        assign data_fifo__write_in = write_valid_in && write_ready_out;
        assign data_fifo__read_in = read_valid_out && read_ready_in;
        assign length_fifo__write_in = (write_valid_in && write_ready_out) && write_eop_in;
        assign length_fifo__read_in = (read_valid_out && read_ready_in) && read_eop_out;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] bytes;
        logic[31:0] count;
        logic write_fire;
        logic read_fire;
        write_fire=write_valid_in && write_ready_out;
        read_fire=read_valid_out && read_ready_in;
        count=unsigned'(32'(packet_count_reg));
        if (write_fire) begin
            bytes=input_bytes();
            if (((bytes == 'h0) || !input_keep_contiguous()) || ((write_sop_in != !assembling_reg))) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            if (write_sop_in) begin
                assembling_length_reg_tmp = bytes;
                assembling_reg_tmp = unsigned'(1'(1));
            end
            else begin
                assembling_length_reg_tmp = assembling_length_reg + bytes;
            end
            if (write_eop_in) begin
                assembling_length_reg_tmp = 'h0;
                assembling_reg_tmp = unsigned'(1'(0));
                count=count+1;
            end
        end
        if (read_fire && read_eop_out) begin
            if (count == 'h0) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            else begin
                --count;
            end
        end
        packet_count_reg_tmp = count;
        if (clear_in) begin
            assembling_length_reg_tmp = 'h0;
            packet_count_reg_tmp = 'h0;
            assembling_reg_tmp = unsigned'(1'(0));
            protocol_error_reg_tmp = unsigned'(1'(0));
        end
        if (reset) begin
            assembling_length_reg_tmp = '0;
            packet_count_reg_tmp = '0;
            assembling_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
        end
    end
    endtask

    task _work_system_clock (input logic reset);
    begin: _work_system_clock
    end
    endtask

    always_ff @(posedge l2_clock) begin
        assembling_length_reg_tmp = assembling_length_reg;
        packet_count_reg_tmp = packet_count_reg;
        assembling_reg_tmp = assembling_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work(reset);

        assembling_length_reg <= assembling_length_reg_tmp;
        packet_count_reg <= packet_count_reg_tmp;
        assembling_reg <= assembling_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge system_clock) begin

        _work_system_clock(reset);

    end


endmodule
