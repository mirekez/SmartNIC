`default_nettype none

import Predef_pkg::*;


module SmartNicMemory #(
    parameter MEM_WIDTH_BYTES = 160
,   parameter MEM_DEPTH = 64
,   parameter SHOWAHEAD = 1
 )
 (
    input wire system_clock
,   input wire l2_clock
,   input wire reset
,   input wire[$clog2(MEM_DEPTH)-1:0] write_addr_in
,   input wire write_in
,   input wire[MEM_WIDTH_BYTES*'h8-1:0] write_data_in
,   input wire[MEM_WIDTH_BYTES-1:0] write_mask_in
,   input wire[$clog2(MEM_DEPTH)-1:0] read_addr_in
,   input wire read_in
,   output wire[MEM_WIDTH_BYTES*'h8-1:0] read_data_out
);


    // regs and combs
    reg[MEM_WIDTH_BYTES*'h8-1:0] data_out_reg;
    reg[MEM_WIDTH_BYTES-1:0][8-1:0] buffer[MEM_DEPTH];
    logic[MEM_WIDTH_BYTES*'h8-1:0] data_out_comb;
    logic[MEM_WIDTH_BYTES*'h8-1:0] write_mask_comb;

    // members

    // tmp variables
    logic[MEM_WIDTH_BYTES*'h8-1:0] data_out_reg_tmp;


    always_comb begin : data_out_comb_func  // data_out_comb_func
        if (SHOWAHEAD) begin
            data_out_comb = buffer[read_addr_in];
        end
        else begin
            data_out_comb = data_out_reg;
        end
    end

    generate  // _assign
        assign read_data_out = data_out_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[63:0] _byte;
        if (reset) begin
            data_out_reg_tmp = '0;
            disable _work;
        end
        if (write_in) begin
            write_mask_comb = 'h0;
            for (_byte='h0;_byte < MEM_WIDTH_BYTES;_byte=_byte+1) begin
                write_mask_comb[_byte*'h8 +:8] = (write_mask_in[_byte]) ? ('hFF) : ('h0);
            end
            buffer[write_addr_in] <= (buffer[write_addr_in] & ~(write_mask_comb)) | (write_data_in & write_mask_comb);
        end
        if (!SHOWAHEAD && read_in) begin
            data_out_reg_tmp = buffer[read_addr_in];
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge system_clock) begin
        data_out_reg_tmp = data_out_reg;

        _work(reset);

        data_out_reg <= data_out_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
