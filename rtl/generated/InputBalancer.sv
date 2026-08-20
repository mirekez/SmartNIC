`default_nettype none

import Predef_pkg::*;


module InputBalancer #(
    parameter LANE_WIDTH = 'h40
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire valid_in
,   input wire[INPUT_BITS-1:0] data_in
,   input wire[INPUT_BYTES-1:0] keep_in
,   input wire[INPUT_BYTES-1:0] sop_in
,   input wire[INPUT_BYTES-1:0] eop_in
,   output wire ready_out
,   output wire[INPUT_BITS-1:0] data_out
,   output wire[INPUT_BYTES-1:0] keep_out
,   output wire[INPUT_BYTES-1:0] sop_out
,   output wire[INPUT_BYTES-1:0] eop_out
,   output wire[2-1:0] valid_out
,   input wire[2-1:0] ready_in
,   output wire protocol_error_out
);
    localparam  LANES = 64'h2;
    localparam  FIFO_WORDS = 64'h800;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  INPUT_BITS = LANES*LANE_WIDTH;
    localparam  INPUT_BYTES = LANES*LANE_BYTES;
    localparam  ENTRY_BYTES = ((LANE_WIDTH + ('h3*LANE_BYTES)))/'h8;
    localparam  ENTRY_BITS = ENTRY_BYTES*'h8;
    localparam  KEEP_OFFSET = LANE_WIDTH;
    localparam  SOP_OFFSET = KEEP_OFFSET + LANE_BYTES;
    localparam  EOP_OFFSET = SOP_OFFSET + LANE_BYTES;


    // regs and combs
    reg in_frame_reg[2];
    reg protocol_error_reg;
    logic input_ready_comb;
;
    logic fifo_write_0_comb;
    logic fifo_read_0_comb;
    logic[ENTRY_BITS-1:0] input_entry_0_comb;
    logic fifo_write_1_comb;
    logic fifo_read_1_comb;
    logic[ENTRY_BITS-1:0] input_entry_1_comb;
    logic[INPUT_BITS-1:0] output_data_comb;
;
    logic[INPUT_BYTES-1:0] output_keep_comb;
;
    logic[INPUT_BYTES-1:0] output_sop_comb;
;
    logic[INPUT_BYTES-1:0] output_eop_comb;
;
    logic[2-1:0] output_valid_comb;
;

    // members
    genvar __i;
    wire fifos__write_in[2];
    wire[ENTRY_BYTES*'h8-1:0] fifos__write_data_in[2];
    wire fifos__read_in[2];
    wire[ENTRY_BYTES*'h8-1:0] fifos__read_data_out[2];
    wire fifos__empty_out[2];
    wire fifos__full_out[2];
    wire fifos__clear_in[2];
    wire fifos__afull_out[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        Fifo #(
        ENTRY_BYTES
,       FIFO_WORDS
,       1
,       1
        ) fifos (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .write_in(fifos__write_in[__i])
        ,           .write_data_in(fifos__write_data_in[__i])
        ,           .read_in(fifos__read_in[__i])
        ,           .read_data_out(fifos__read_data_out[__i])
        ,           .empty_out(fifos__empty_out[__i])
        ,           .full_out(fifos__full_out[__i])
        ,           .clear_in(fifos__clear_in[__i])
        ,           .afull_out(fifos__afull_out[__i])
        );
    end
    endgenerate

    // tmp variables
    logic in_frame_reg_tmp[2];
    logic protocol_error_reg_tmp;


    function logic lane_present (input logic[63:0] lane);
        return unsigned'(64'(keep_in[(lane*LANE_BYTES) +:((0 + LANE_BYTES) - 'h1) - 0 + 1])) != 'h0;
    endfunction

    function logic lane_pop (input logic[63:0] lane);
        return !fifos__empty_out[lane] && ready_in[lane];
    endfunction

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[63:0] lane;
        input_ready_comb=1;
        if (!valid_in) begin
            disable input_ready_comb_func;
        end
        for (lane='h0;lane < LANES;lane=lane+1) begin
            if ((lane_present(lane) && fifos__full_out[lane]) && !lane_pop(lane)) begin
                input_ready_comb=0;
            end
        end
    end

    always_comb begin : fifo_write_0_comb_func  // fifo_write_0_comb_func
        fifo_write_0_comb=(valid_in && input_ready_comb) && lane_present('h0);
    end

    always_comb begin : fifo_read_0_comb_func  // fifo_read_0_comb_func
        fifo_read_0_comb=lane_pop('h0);
    end

    always_comb begin : input_entry_0_comb_func  // input_entry_0_comb_func
        input_entry_0_comb = 'h0;
        input_entry_0_comb['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1] = data_in['h0*LANE_WIDTH +:(('h0*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h0*LANE_WIDTH + 1];
        input_entry_0_comb[KEEP_OFFSET +:(KEEP_OFFSET + LANE_BYTES) - 'h1 - KEEP_OFFSET + 1] = keep_in['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        input_entry_0_comb[SOP_OFFSET +:(SOP_OFFSET + LANE_BYTES) - 'h1 - SOP_OFFSET + 1] = sop_in['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        input_entry_0_comb[EOP_OFFSET +:(EOP_OFFSET + LANE_BYTES) - 'h1 - EOP_OFFSET + 1] = eop_in['h0*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
    end

    always_comb begin : fifo_write_1_comb_func  // fifo_write_1_comb_func
        fifo_write_1_comb=(valid_in && input_ready_comb) && lane_present('h1);
    end

    always_comb begin : fifo_read_1_comb_func  // fifo_read_1_comb_func
        fifo_read_1_comb=lane_pop('h1);
    end

    always_comb begin : input_entry_1_comb_func  // input_entry_1_comb_func
        input_entry_1_comb = 'h0;
        input_entry_1_comb['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1] = data_in['h1*LANE_WIDTH +:(('h1*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h1*LANE_WIDTH + 1];
        input_entry_1_comb[KEEP_OFFSET +:(KEEP_OFFSET + LANE_BYTES) - 'h1 - KEEP_OFFSET + 1] = keep_in['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        input_entry_1_comb[SOP_OFFSET +:(SOP_OFFSET + LANE_BYTES) - 'h1 - SOP_OFFSET + 1] = sop_in['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
        input_entry_1_comb[EOP_OFFSET +:(EOP_OFFSET + LANE_BYTES) - 'h1 - EOP_OFFSET + 1] = eop_in['h1*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1];
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[63:0] lane;
        logic[88-1:0] entry;
        output_data_comb = 'h0;
        for (lane='h0;lane < LANES;lane=lane+1) begin
            entry = fifos__read_data_out[lane];
            output_data_comb[lane*LANE_WIDTH +:(0 + LANE_WIDTH) - 'h1 - 0 + 1] = entry['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1];
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[63:0] lane;
        logic[88-1:0] entry;
        output_keep_comb = 'h0;
        for (lane='h0;lane < LANES;lane=lane+1) begin
            entry = fifos__read_data_out[lane];
            output_keep_comb[lane*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1] = entry[KEEP_OFFSET +:(KEEP_OFFSET + LANE_BYTES) - 'h1 - KEEP_OFFSET + 1];
        end
    end

    always_comb begin : output_sop_comb_func  // output_sop_comb_func
        logic[63:0] lane;
        logic[88-1:0] entry;
        output_sop_comb = 'h0;
        for (lane='h0;lane < LANES;lane=lane+1) begin
            entry = fifos__read_data_out[lane];
            output_sop_comb[lane*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1] = entry[SOP_OFFSET +:(SOP_OFFSET + LANE_BYTES) - 'h1 - SOP_OFFSET + 1];
        end
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        logic[63:0] lane;
        logic[88-1:0] entry;
        output_eop_comb = 'h0;
        for (lane='h0;lane < LANES;lane=lane+1) begin
            entry = fifos__read_data_out[lane];
            output_eop_comb[lane*LANE_BYTES +:(0 + LANE_BYTES) - 'h1 - 0 + 1] = entry[EOP_OFFSET +:(EOP_OFFSET + LANE_BYTES) - 'h1 - EOP_OFFSET + 1];
        end
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        logic[63:0] lane;
        output_valid_comb = 'h0;
        for (lane='h0;lane < LANES;lane=lane+1) begin
            output_valid_comb[lane] = !fifos__empty_out[lane];
        end
    end

    generate  // _assign
        assign fifos__write_in['h0] = fifo_write_0_comb;
        assign fifos__write_data_in['h0] = input_entry_0_comb;
        assign fifos__read_in['h0] = fifo_read_0_comb;
        assign fifos__clear_in['h0] = 0;
        assign fifos__write_in['h1] = fifo_write_1_comb;
        assign fifos__write_data_in['h1] = input_entry_1_comb;
        assign fifos__read_in['h1] = fifo_read_1_comb;
        assign fifos__clear_in['h1] = 0;
        assign ready_out = input_ready_comb;
        assign data_out = output_data_comb;
        assign keep_out = output_keep_comb;
        assign sop_out = output_sop_comb;
        assign eop_out = output_eop_comb;
        assign valid_out = output_valid_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[63:0] lane;
        logic[63:0] _byte;
        logic seen_zero;
        logic sop_seen;
        logic eop_seen;
        logic last_valid;
        logic keep;
        logic sop;
        logic eop;
        for (lane='h0;lane < LANES;lane=lane+1) begin
        end
        if (reset) begin
            for (lane='h0;lane < LANES;lane=lane+1) begin
                in_frame_reg_tmp[lane] = unsigned'(1'h0);
            end
            protocol_error_reg_tmp = unsigned'(1'h0);
            disable _work_net_clk;
        end
        for (lane='h0;lane < LANES;lane=lane+1) begin
            if ((valid_in && input_ready_comb) && lane_present(lane)) begin
                seen_zero=0;
                sop_seen=0;
                eop_seen=0;
                last_valid=0;
                for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                    logic[63:0] flat; flat = (lane*LANE_BYTES) + _byte;
                    keep=keep_in[flat];
                    sop=sop_in[flat];
                    eop=eop_in[flat];
                    if (!keep) begin
                        seen_zero=1;
                        if (sop || eop) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                    else begin
                        if (seen_zero) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        if (sop_seen && sop) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        if (eop_seen && eop) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        sop_seen=sop_seen || sop;
                        eop_seen=eop_seen || eop;
                        last_valid=eop;
                    end
                end
                if (sop_seen == in_frame_reg[lane]) begin
                    protocol_error_reg_tmp = unsigned'(1'h1);
                end
                if (eop_seen && !last_valid) begin
                    protocol_error_reg_tmp = unsigned'(1'h1);
                end
                if ((eop_seen && !in_frame_reg[lane]) && !sop_seen) begin
                    protocol_error_reg_tmp = unsigned'(1'h1);
                end
                in_frame_reg_tmp[lane] = unsigned'(1'(!eop_seen));
            end
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
        _work_net_clk(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        in_frame_reg_tmp = in_frame_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        in_frame_reg <= in_frame_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
