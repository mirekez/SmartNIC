`default_nettype none

import Predef_pkg::*;


module TxQueue #(
    parameter DEPTH = 'h100
 )
 (
    input wire l2_clock
,   input wire system_clock
,   input wire reset
,   input wire write_valid_in
,   input wire[256-1:0] write_data_in
,   input wire[32-1:0] write_keep_in
,   input wire write_sop_in
,   input wire write_eop_in
,   output wire write_ready_out
,   output wire read_valid_out
,   output wire[256-1:0] read_data_out
,   output wire[32-1:0] read_keep_out
,   output wire read_sop_out
,   output wire read_eop_out
,   input wire read_ready_in
,   output wire empty_out
,   output wire full_out
,   output wire[16-1:0] packet_length_out
,   output wire[$clog2(DEPTH + 'h1)-1:0] packet_count_out
,   output wire protocol_error_out
,   input wire clear_in
);


    // regs and combs

    // members
    wire queue__write_valid_in;
    wire[256-1:0] queue__write_data_in;
    wire[256/'h8-1:0] queue__write_keep_in;
    wire queue__write_sop_in;
    wire queue__write_eop_in;
    wire queue__write_ready_out;
    wire queue__read_valid_out;
    wire[256-1:0] queue__read_data_out;
    wire[256/'h8-1:0] queue__read_keep_out;
    wire queue__read_sop_out;
    wire queue__read_eop_out;
    wire queue__read_ready_in;
    wire queue__empty_out;
    wire queue__full_out;
    wire[16-1:0] queue__packet_length_out;
    wire[$clog2(256 + 'h1)-1:0] queue__packet_count_out;
    wire queue__protocol_error_out;
    wire queue__clear_in;
    PacketQueue #(
        256
,       256
,       16
    ) queue (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_valid_in(queue__write_valid_in)
,       .write_data_in(queue__write_data_in)
,       .write_keep_in(queue__write_keep_in)
,       .write_sop_in(queue__write_sop_in)
,       .write_eop_in(queue__write_eop_in)
,       .write_ready_out(queue__write_ready_out)
,       .read_valid_out(queue__read_valid_out)
,       .read_data_out(queue__read_data_out)
,       .read_keep_out(queue__read_keep_out)
,       .read_sop_out(queue__read_sop_out)
,       .read_eop_out(queue__read_eop_out)
,       .read_ready_in(queue__read_ready_in)
,       .empty_out(queue__empty_out)
,       .full_out(queue__full_out)
,       .packet_length_out(queue__packet_length_out)
,       .packet_count_out(queue__packet_count_out)
,       .protocol_error_out(queue__protocol_error_out)
,       .clear_in(queue__clear_in)
    );

    // tmp variables


    generate  // _assign
        assign queue__write_valid_in = write_valid_in;
        assign queue__write_data_in = write_data_in;
        assign queue__write_keep_in = write_keep_in;
        assign queue__write_sop_in = write_sop_in;
        assign queue__write_eop_in = write_eop_in;
        assign queue__read_ready_in = read_ready_in;
        assign queue__clear_in = clear_in;
        assign write_ready_out = queue__write_ready_out;
        assign read_valid_out = queue__read_valid_out;
        assign read_data_out = queue__read_data_out;
        assign read_keep_out = queue__read_keep_out;
        assign read_sop_out = queue__read_sop_out;
        assign read_eop_out = queue__read_eop_out;
        assign empty_out = queue__empty_out;
        assign full_out = queue__full_out;
        assign packet_length_out = queue__packet_length_out;
        assign packet_count_out = queue__packet_count_out;
        assign protocol_error_out = queue__protocol_error_out;
    endgenerate

    task _work (input logic reset);
    begin: _work
    end
    endtask

    task _work_system_clock (input logic reset);
    begin: _work_system_clock
    end
    endtask

    always_ff @(posedge l2_clock) begin

        _work(reset);

    end

    always_ff @(posedge system_clock) begin

        _work_system_clock(reset);

    end


endmodule
