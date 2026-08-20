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
    localparam  SRC_BYTES = SRC_WIDTH/'h8;
    localparam  DST_BYTES = DST_WIDTH/'h8;
    localparam  WIDE_WIDTH = 64'h100;
    localparam  WIDE_BYTES = 64'h20;
    localparam  LANE_WIDTH = 64'h40;
    localparam  LANE_BYTES = 64'h8;
    localparam  LANES = 64'h4;


    // regs and combs
    reg[256-1:0] data_reg;
    reg[32-1:0] keep_reg;
    reg[2-1:0] lane_reg;
    reg[2-1:0] last_lane_reg;
    reg valid_reg;
    reg sop_reg;
    reg eop_reg;
    logic ready_comb;
    logic valid_comb;
    logic sop_comb;
    logic eop_comb;
    logic[DST_WIDTH-1:0] data_comb;
    logic[DST_BYTES-1:0] keep_comb;

    // members

    // tmp variables
    logic[256-1:0] data_reg_tmp;
    logic[32-1:0] keep_reg_tmp;
    logic[2-1:0] lane_reg_tmp;
    logic[2-1:0] last_lane_reg_tmp;
    logic valid_reg_tmp;
    logic sop_reg_tmp;
    logic eop_reg_tmp;


    function logic last_output_lane ();
        if (SRC_WIDTH < DST_WIDTH) begin
            return 1;
        end
        return unsigned'(32'(lane_reg)) == unsigned'(32'(last_lane_reg));
    endfunction

    always_comb begin : ready_comb_func  // ready_comb_func
        ready_comb=!valid_reg || ((ready_in && last_output_lane()));
    end

    always_comb begin : valid_comb_func  // valid_comb_func
        valid_comb=valid_reg;
    end

    always_comb begin : data_comb_func  // data_comb_func
        data_comb = 'h0;
        if (SRC_WIDTH < DST_WIDTH) begin
            data_comb = data_reg;
        end
        else begin
            if (unsigned'(32'(lane_reg)) == 'h0) begin
                data_comb = data_reg['h0 +:64];
            end
            else begin
                if (unsigned'(32'(lane_reg)) == 'h1) begin
                    data_comb = data_reg['h40 +:64];
                end
                else begin
                    if (unsigned'(32'(lane_reg)) == 'h2) begin
                        data_comb = data_reg['h80 +:64];
                    end
                    else begin
                        data_comb = data_reg['hC0 +:64];
                    end
                end
            end
        end
    end

    always_comb begin : keep_comb_func  // keep_comb_func
        keep_comb = 'h0;
        if (SRC_WIDTH < DST_WIDTH) begin
            keep_comb = keep_reg;
        end
        else begin
            if (unsigned'(32'(lane_reg)) == 'h0) begin
                keep_comb = keep_reg['h0 +:8];
            end
            else begin
                if (unsigned'(32'(lane_reg)) == 'h1) begin
                    keep_comb = keep_reg['h8 +:8];
                end
                else begin
                    if (unsigned'(32'(lane_reg)) == 'h2) begin
                        keep_comb = keep_reg['h10 +:8];
                    end
                    else begin
                        keep_comb = keep_reg['h18 +:8];
                    end
                end
            end
        end
    end

    always_comb begin : sop_comb_func  // sop_comb_func
        if (SRC_WIDTH < DST_WIDTH) begin
            sop_comb=sop_reg;
        end
        else begin
            sop_comb=sop_reg && (unsigned'(32'(lane_reg)) == 'h0);
        end
    end

    always_comb begin : eop_comb_func  // eop_comb_func
        if (SRC_WIDTH < DST_WIDTH) begin
            eop_comb=eop_reg;
        end
        else begin
            eop_comb=eop_reg && last_output_lane();
        end
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
        logic output_fire;
        logic input_fire;
        logic word_complete;
        logic[31:0] lane;
        logic[31:0] last_lane;
        logic[256-1:0] data;
        logic[32-1:0] keep;
        output_fire=valid_reg && ready_in;
        input_fire=valid_in && ready_comb;
        if (SRC_WIDTH < DST_WIDTH) begin
            lane=(output_fire) ? ('h0) : (unsigned'(32'(lane_reg)));
            data = (output_fire) ? ('h0) : (data_reg);
            keep = (output_fire) ? ('h0) : (keep_reg);
            if (output_fire) begin
                valid_reg_tmp = unsigned'(1'(0));
                sop_reg_tmp = unsigned'(1'(0));
                eop_reg_tmp = unsigned'(1'(0));
            end
            if (input_fire) begin
                if (lane == 'h0) begin
                    data['h0 +:64] = data_in;
                    keep['h0 +:8] = keep_in;
                end
                else begin
                    if (lane == 'h1) begin
                        data['h40 +:64] = data_in;
                        keep['h8 +:8] = keep_in;
                    end
                    else begin
                        if (lane == 'h2) begin
                            data['h80 +:64] = data_in;
                            keep['h10 +:8] = keep_in;
                        end
                        else begin
                            data['hC0 +:64] = data_in;
                            keep['h18 +:8] = keep_in;
                        end
                    end
                end
                if (sop_in) begin
                    sop_reg_tmp = unsigned'(1'(1));
                end
                word_complete=eop_in || (lane == (LANES - 'h1));
                if (word_complete) begin
                    valid_reg_tmp = unsigned'(1'(1));
                    eop_reg_tmp = unsigned'(1'(eop_in));
                    lane_reg_tmp = 'h0;
                end
                else begin
                    lane_reg_tmp = lane + 'h1;
                end
                data_reg_tmp = data;
                keep_reg_tmp = keep;
            end
        end
        else begin
            if (output_fire) begin
                if (last_output_lane()) begin
                    valid_reg_tmp = unsigned'(1'(0));
                end
                else begin
                    lane_reg_tmp = lane_reg + 'h1;
                end
            end
            if (input_fire) begin
                last_lane='h0;
                if (unsigned'(64'(keep_in['h18 +:8])) != 'h0) begin
                    last_lane='h3;
                end
                else begin
                    if (unsigned'(64'(keep_in['h10 +:8])) != 'h0) begin
                        last_lane='h2;
                    end
                    else begin
                        if (unsigned'(64'(keep_in['h8 +:8])) != 'h0) begin
                            last_lane='h1;
                        end
                    end
                end
                data_reg_tmp = data_in;
                keep_reg_tmp = keep_in;
                lane_reg_tmp = 'h0;
                last_lane_reg_tmp = last_lane;
                valid_reg_tmp = unsigned'(1'(unsigned'(64'(keep_in)) != 'h0));
                sop_reg_tmp = unsigned'(1'(sop_in));
                eop_reg_tmp = unsigned'(1'(eop_in));
            end
        end
        if (reset) begin
            data_reg_tmp = '0;
            keep_reg_tmp = '0;
            lane_reg_tmp = '0;
            last_lane_reg_tmp = '0;
            valid_reg_tmp = '0;
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
        keep_reg_tmp = keep_reg;
        lane_reg_tmp = lane_reg;
        last_lane_reg_tmp = last_lane_reg;
        valid_reg_tmp = valid_reg;
        sop_reg_tmp = sop_reg;
        eop_reg_tmp = eop_reg;

        _work(reset);

        data_reg <= data_reg_tmp;
        keep_reg <= keep_reg_tmp;
        lane_reg <= lane_reg_tmp;
        last_lane_reg <= last_lane_reg_tmp;
        valid_reg <= valid_reg_tmp;
        sop_reg <= sop_reg_tmp;
        eop_reg <= eop_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
