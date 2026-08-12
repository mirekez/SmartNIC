`default_nettype none

import Predef_pkg::*;


module PacketStream #(
    parameter SRC_WIDTH = 256
,   parameter DST_WIDTH = 64
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire valid_in
,   input wire[SRC_WIDTH-1:0] data_in
,   input wire[SRC_BYTES-1:0] keep_in
,   input wire sop_in
,   input wire eop_in
,   output wire ready_out
,   output wire valid_out
,   output wire[DST_WIDTH-1:0] data_out
,   output wire[DST_BYTES-1:0] keep_out
,   output wire sop_out
,   output wire eop_out
,   input wire ready_in
);
    parameter  SRC_BYTES = SRC_WIDTH/'h8;
    parameter  DST_BYTES = DST_WIDTH/'h8;
    parameter  BUFFER_BYTES = 64'h40;
    parameter  BUFFER_BITS = 64'h200;


    // regs and combs
    reg[512-1:0] data_reg;
    reg[7-1:0] count_reg;
    reg sop_reg;
    reg eop_reg;
    logic ready_comb;
    logic valid_comb;
    logic eop_comb;
    logic[DST_WIDTH-1:0] data_comb;
    logic[DST_BYTES-1:0] keep_comb;

    // members

    // tmp variables
    logic[512-1:0] data_reg_tmp;
    logic[7-1:0] count_reg_tmp;
    logic sop_reg_tmp;
    logic eop_reg_tmp;


    function logic output_valid_value ();
        return count_reg>=DST_BYTES || ((eop_reg && (unsigned'(32'(count_reg)) != 'h0)));
    endfunction

    always_comb begin : ready_comb_func  // ready_comb_func
        logic[31:0] count;
        logic eop;
        count = unsigned'(32'(count_reg));
        eop = eop_reg;
        if (output_valid_value() && ready_in) begin
            count-=(count > DST_BYTES) ? (DST_BYTES) : (count);
            if (count == 'h0) begin
                eop=0;
            end
        end
        ready_comb=!eop && (count + SRC_BYTES)<=BUFFER_BYTES;
    end

    always_comb begin : data_comb_func  // data_comb_func
        logic[31:0] _byte;
        data_comb = 'h0;
        for (_byte='h0;_byte < DST_BYTES;_byte=_byte+1) begin
            if (_byte < unsigned'(32'(count_reg))) begin
                data_comb[_byte*'h8 +:8] = data_reg[_byte*'h8 +:8];
            end
        end
    end

    always_comb begin : keep_comb_func  // keep_comb_func
        logic[31:0] _byte;
        keep_comb = 'h0;
        for (_byte='h0;_byte < DST_BYTES;_byte=_byte+1) begin
            keep_comb[_byte] = _byte < unsigned'(32'(count_reg));
        end
    end

    always_comb begin : valid_comb_func  // valid_comb_func
        valid_comb=output_valid_value();
    end

    always_comb begin : eop_comb_func  // eop_comb_func
        eop_comb=eop_reg && count_reg<=DST_BYTES;
    end

    generate  // _assign
        assign ready_out = ready_comb;
        assign valid_out = valid_comb;
        assign data_out = data_comb;
        assign keep_out = keep_comb;
        assign sop_out = sop_reg;
        assign eop_out = eop_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[512-1:0] data;
        logic[31:0] count;
        logic[31:0] remove;
        logic[31:0] _byte;
        logic sop;
        logic eop;
        data = data_reg;
        count = unsigned'(32'(count_reg));
        sop = sop_reg;
        eop = eop_reg;
        if (output_valid_value() && ready_in) begin
            remove=(count > DST_BYTES) ? (DST_BYTES) : (count);
            for (_byte='h0;_byte < BUFFER_BYTES;_byte=_byte+1) begin
                if ((_byte + remove) < count) begin
                    data[_byte*'h8 +:8] = data[((_byte + remove))*'h8 +:8];
                end
                else begin
                    data[_byte*'h8 +:8] = 'h0;
                end
            end
            count-=remove;
            sop=0;
            if (count == 'h0) begin
                eop=0;
            end
        end
        if (valid_in && ready_comb) begin
            for (_byte='h0;_byte < SRC_BYTES;_byte=_byte+1) begin
                if (keep_in[_byte]) begin
                    data[count*'h8 +:8] = data_in[_byte*'h8 +:8];
                    count=count+1;
                end
            end
            if (sop_in) begin
                sop=1;
            end
            if (eop_in) begin
                eop=1;
            end
        end
        data_reg_tmp = data;
        count_reg_tmp = count;
        sop_reg_tmp = unsigned'(1'(sop));
        eop_reg_tmp = unsigned'(1'(eop));
        if (reset) begin
            data_reg_tmp = '0;
            count_reg_tmp = '0;
            sop_reg_tmp = '0;
            eop_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clk (input logic reset);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        data_reg_tmp = data_reg;
        count_reg_tmp = count_reg;
        sop_reg_tmp = sop_reg;
        eop_reg_tmp = eop_reg;

        _work(reset);

        data_reg <= data_reg_tmp;
        count_reg <= count_reg_tmp;
        sop_reg <= sop_reg_tmp;
        eop_reg <= eop_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
