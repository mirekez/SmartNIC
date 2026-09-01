`default_nettype none

import Predef_pkg::*;


module RxLineBuffer #(
    parameter DATA_WIDTH = 'h100
,   parameter DEPTH = 'h4
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire valid_in
,   input wire[DATA_WIDTH-1:0] data_in
,   input wire[KEEP_WIDTH-1:0] keep_in
,   input wire sop_in
,   input wire eop_in
,   output wire ready_out
,   output wire valid_out
,   output wire[DATA_WIDTH-1:0] data_out
,   output wire[KEEP_WIDTH-1:0] keep_out
,   output wire sop_out
,   output wire eop_out
,   input wire ready_in
);
    localparam  KEEP_WIDTH = DATA_WIDTH/'h8;
    localparam  PTR_BITS = (DEPTH<='h2) ? ('h1) : ($clog2(DEPTH));
    localparam  COUNT_BITS = $clog2(DEPTH + 'h1);


    // regs and combs
    reg[DATA_WIDTH-1:0] data_reg[DEPTH];
    reg[KEEP_WIDTH-1:0] keep_reg[DEPTH];
    reg sop_reg[DEPTH];
    reg eop_reg[DEPTH];
    reg[PTR_BITS-1:0] head_reg;
    reg[PTR_BITS-1:0] tail_reg;
    reg[COUNT_BITS-1:0] count_reg;
    logic ready_comb;
    logic valid_comb;
    logic[DATA_WIDTH-1:0] data_comb;
    logic[KEEP_WIDTH-1:0] keep_comb;
    logic sop_comb;
    logic eop_comb;

    // members

    // tmp variables
    logic[DATA_WIDTH-1:0] data_reg_tmp[DEPTH];
    logic[KEEP_WIDTH-1:0] keep_reg_tmp[DEPTH];
    logic sop_reg_tmp[DEPTH];
    logic eop_reg_tmp[DEPTH];
    logic[PTR_BITS-1:0] head_reg_tmp;
    logic[PTR_BITS-1:0] tail_reg_tmp;
    logic[COUNT_BITS-1:0] count_reg_tmp;


    always_comb begin : ready_comb_func  // ready_comb_func
        ready_comb=unsigned'(32'(count_reg)) < DEPTH;
    end

    always_comb begin : valid_comb_func  // valid_comb_func
        valid_comb=unsigned'(32'(count_reg)) != 'h0;
    end

    always_comb begin : data_comb_func  // data_comb_func
        data_comb = data_reg[unsigned'(32'(head_reg))];
    end

    always_comb begin : keep_comb_func  // keep_comb_func
        keep_comb = keep_reg[unsigned'(32'(head_reg))];
    end

    always_comb begin : sop_comb_func  // sop_comb_func
        sop_comb=sop_reg[unsigned'(32'(head_reg))];
    end

    always_comb begin : eop_comb_func  // eop_comb_func
        eop_comb=eop_reg[unsigned'(32'(head_reg))];
    end

    generate  // _assign
        assign ready_out = ready_comb;
        assign valid_out = valid_comb;
        assign data_out = data_comb;
        assign keep_out = keep_comb;
        assign sop_out = sop_comb;
        assign eop_out = eop_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] count;
        logic push;
        logic pop;
        if (reset) begin
            head_reg_tmp = '0;
            tail_reg_tmp = '0;
            count_reg_tmp = '0;
            disable _work;
        end
        head=unsigned'(32'(head_reg));
        tail=unsigned'(32'(tail_reg));
        count=unsigned'(32'(count_reg));
        push=valid_in && ready_comb;
        pop=valid_comb && ready_in;
        if (push) begin
            data_reg_tmp[tail] = data_in;
            keep_reg_tmp[tail] = keep_in;
            sop_reg_tmp[tail] = unsigned'(1'(sop_in));
            eop_reg_tmp[tail] = unsigned'(1'(eop_in));
            tail=((tail + 'h1)) & ((DEPTH - 'h1));
        end
        if (pop) begin
            head=((head + 'h1)) & ((DEPTH - 'h1));
        end
        if (push && !pop) begin
            count=count+1;
        end
        else begin
            if (pop && !push) begin
                --count;
            end
        end
        head_reg_tmp = head;
        tail_reg_tmp = tail;
        count_reg_tmp = count;
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        data_reg_tmp = data_reg;
        keep_reg_tmp = keep_reg;
        sop_reg_tmp = sop_reg;
        eop_reg_tmp = eop_reg;
        head_reg_tmp = head_reg;
        tail_reg_tmp = tail_reg;
        count_reg_tmp = count_reg;

        _work(reset);

        data_reg <= data_reg_tmp;
        keep_reg <= keep_reg_tmp;
        sop_reg <= sop_reg_tmp;
        eop_reg <= eop_reg_tmp;
        head_reg <= head_reg_tmp;
        tail_reg <= tail_reg_tmp;
        count_reg <= count_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
