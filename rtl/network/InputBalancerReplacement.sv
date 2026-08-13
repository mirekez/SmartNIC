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
    parameter  LANES = 64'h2;
    parameter  FIFO_WORDS = 64'h800;
    parameter  MAX_FRAME_BYTES = 64'h2400;
    parameter  FLUSH_CYCLES = 64'h8;
    parameter  LANE_BYTES = LANE_WIDTH/'h8;
    parameter  INPUT_BITS = LANES*LANE_WIDTH;
    parameter  INPUT_BYTES = LANES*LANE_BYTES;
    parameter  FIFO_BANKS = 64'h8;
    parameter  FIFO_BANK_DEPTH = 64'h100;
    parameter  MAX_LANE_WIDTH = 64'h40;
    parameter  MAX_LANE_BYTES = 64'h8;
    parameter  POINTER_BITS = 64'hB;
    parameter  COUNT_BITS = 64'hC;
    parameter  PACK_COUNT_BITS = $clog2(LANE_BYTES + 'h1);
    parameter  AGE_BITS = 64'h4;
    parameter  RESERVED_WORDS = ((((MAX_FRAME_BYTES + LANE_BYTES) - 'h1))/LANE_BYTES) + LANES;
    parameter  ELIGIBLE_WORDS = FIFO_WORDS - RESERVED_WORDS;


    // regs and combs
    reg[64-1:0] data_0_0[256];
    reg[8-1:0] keep_0_0[256];
    reg[8-1:0] sop_0_0[256];
    reg[8-1:0] eop_0_0[256];
    reg[64-1:0] data_0_1[256];
    reg[8-1:0] keep_0_1[256];
    reg[8-1:0] sop_0_1[256];
    reg[8-1:0] eop_0_1[256];
    reg[64-1:0] data_0_2[256];
    reg[8-1:0] keep_0_2[256];
    reg[8-1:0] sop_0_2[256];
    reg[8-1:0] eop_0_2[256];
    reg[64-1:0] data_0_3[256];
    reg[8-1:0] keep_0_3[256];
    reg[8-1:0] sop_0_3[256];
    reg[8-1:0] eop_0_3[256];
    reg[64-1:0] data_0_4[256];
    reg[8-1:0] keep_0_4[256];
    reg[8-1:0] sop_0_4[256];
    reg[8-1:0] eop_0_4[256];
    reg[64-1:0] data_0_5[256];
    reg[8-1:0] keep_0_5[256];
    reg[8-1:0] sop_0_5[256];
    reg[8-1:0] eop_0_5[256];
    reg[64-1:0] data_0_6[256];
    reg[8-1:0] keep_0_6[256];
    reg[8-1:0] sop_0_6[256];
    reg[8-1:0] eop_0_6[256];
    reg[64-1:0] data_0_7[256];
    reg[8-1:0] keep_0_7[256];
    reg[8-1:0] sop_0_7[256];
    reg[8-1:0] eop_0_7[256];
    reg[64-1:0] data_1_0[256];
    reg[8-1:0] keep_1_0[256];
    reg[8-1:0] sop_1_0[256];
    reg[8-1:0] eop_1_0[256];
    reg[64-1:0] data_1_1[256];
    reg[8-1:0] keep_1_1[256];
    reg[8-1:0] sop_1_1[256];
    reg[8-1:0] eop_1_1[256];
    reg[64-1:0] data_1_2[256];
    reg[8-1:0] keep_1_2[256];
    reg[8-1:0] sop_1_2[256];
    reg[8-1:0] eop_1_2[256];
    reg[64-1:0] data_1_3[256];
    reg[8-1:0] keep_1_3[256];
    reg[8-1:0] sop_1_3[256];
    reg[8-1:0] eop_1_3[256];
    reg[64-1:0] data_1_4[256];
    reg[8-1:0] keep_1_4[256];
    reg[8-1:0] sop_1_4[256];
    reg[8-1:0] eop_1_4[256];
    reg[64-1:0] data_1_5[256];
    reg[8-1:0] keep_1_5[256];
    reg[8-1:0] sop_1_5[256];
    reg[8-1:0] eop_1_5[256];
    reg[64-1:0] data_1_6[256];
    reg[8-1:0] keep_1_6[256];
    reg[8-1:0] sop_1_6[256];
    reg[8-1:0] eop_1_6[256];
    reg[64-1:0] data_1_7[256];
    reg[8-1:0] keep_1_7[256];
    reg[8-1:0] sop_1_7[256];
    reg[8-1:0] eop_1_7[256];
    reg[11-1:0] head_reg[2];
    reg[11-1:0] tail_reg[2];
    reg[12-1:0] count_reg[2];
    reg[LANE_WIDTH-1:0] pack_data_reg[2];
    reg[LANE_BYTES-1:0] pack_keep_reg[2];
    reg[LANE_BYTES-1:0] pack_sop_reg[2];
    reg[LANE_BYTES-1:0] pack_eop_reg[2];
    reg[PACK_COUNT_BITS-1:0] pack_count_reg[2];
    reg pack_boundary_reg[2];
    reg[4-1:0] pack_age_reg[2];
    reg[3-1:0] rr_reg;
    reg[3-1:0] frame_dest_reg;
    reg in_frame_reg;
    reg protocol_error_reg;
    logic input_ready_comb;
;
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

    // tmp variables
    logic[11-1:0] head_reg_tmp[2];
    logic[11-1:0] tail_reg_tmp[2];
    logic[12-1:0] count_reg_tmp[2];
    logic[LANE_WIDTH-1:0] pack_data_reg_tmp[2];
    logic[LANE_BYTES-1:0] pack_keep_reg_tmp[2];
    logic[LANE_BYTES-1:0] pack_sop_reg_tmp[2];
    logic[LANE_BYTES-1:0] pack_eop_reg_tmp[2];
    logic[PACK_COUNT_BITS-1:0] pack_count_reg_tmp[2];
    logic pack_boundary_reg_tmp[2];
    logic[4-1:0] pack_age_reg_tmp[2];
    logic[3-1:0] rr_reg_tmp;
    logic[3-1:0] frame_dest_reg_tmp;
    logic in_frame_reg_tmp;
    logic protocol_error_reg_tmp;


    function logic[31:0] occupancy_after_pop (input logic[63:0] _output);
        logic[31:0] count;
        count = unsigned'(32'(count_reg[_output]));
        if ((count != 'h0) && ready_in[_output]) begin
            --count;
        end
        if (unsigned'(32'(pack_count_reg[_output])) != 'h0) begin
            count=count+1;
        end
        return count;
    endfunction

    function logic output_eligible (input logic[63:0] _output);
        return occupancy_after_pop(_output)<=ELIGIBLE_WORDS;
    endfunction

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[63:0] _output;
        logic[63:0] _byte;
        logic[31:0] eligible;
        logic[31:0] starts;
        logic[31:0] active_count;
        input_ready_comb=1;
        active_count='h0;
        if (!valid_in) begin
            disable input_ready_comb_func;
        end
        eligible='h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (output_eligible(_output)) begin
                eligible=eligible+1;
            end
        end
        starts='h0;
        for (_byte='h0;_byte < INPUT_BYTES;_byte=_byte+1) begin
            if (keep_in[_byte] && sop_in[_byte]) begin
                starts=starts+1;
            end
        end
        if (starts > eligible) begin
            input_ready_comb=0;
        end
        if (in_frame_reg) begin
            active_count=unsigned'(32'(count_reg[unsigned'(32'(frame_dest_reg))]));
            if ((active_count != 'h0) && ready_in[unsigned'(32'(frame_dest_reg))]) begin
                --active_count;
            end
            if (active_count > (FIFO_WORDS - LANES)) begin
                input_ready_comb=0;
            end
        end
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[63:0] _output;
        logic[63:0] lane_bit;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[64-1:0] entry;
        output_data_comb = 'h0;
        logical='h0;
        bank='h0;
        row='h0;
        entry = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (unsigned'(32'(count_reg[_output])) != 'h0) begin
                logical=unsigned'(32'(head_reg[_output]));
                bank=logical & ((FIFO_BANKS - 'h1));
                row=logical >>> 'h3;
                if ((_output == 'h0) && (bank == 'h0)) begin
                    entry = data_0_0[row];
                end
                if ((_output == 'h0) && (bank == 'h1)) begin
                    entry = data_0_1[row];
                end
                if ((_output == 'h0) && (bank == 'h2)) begin
                    entry = data_0_2[row];
                end
                if ((_output == 'h0) && (bank == 'h3)) begin
                    entry = data_0_3[row];
                end
                if ((_output == 'h0) && (bank == 'h4)) begin
                    entry = data_0_4[row];
                end
                if ((_output == 'h0) && (bank == 'h5)) begin
                    entry = data_0_5[row];
                end
                if ((_output == 'h0) && (bank == 'h6)) begin
                    entry = data_0_6[row];
                end
                if ((_output == 'h0) && (bank == 'h7)) begin
                    entry = data_0_7[row];
                end
                if ((_output == 'h1) && (bank == 'h0)) begin
                    entry = data_1_0[row];
                end
                if ((_output == 'h1) && (bank == 'h1)) begin
                    entry = data_1_1[row];
                end
                if ((_output == 'h1) && (bank == 'h2)) begin
                    entry = data_1_2[row];
                end
                if ((_output == 'h1) && (bank == 'h3)) begin
                    entry = data_1_3[row];
                end
                if ((_output == 'h1) && (bank == 'h4)) begin
                    entry = data_1_4[row];
                end
                if ((_output == 'h1) && (bank == 'h5)) begin
                    entry = data_1_5[row];
                end
                if ((_output == 'h1) && (bank == 'h6)) begin
                    entry = data_1_6[row];
                end
                if ((_output == 'h1) && (bank == 'h7)) begin
                    entry = data_1_7[row];
                end
                for (lane_bit='h0;lane_bit < LANE_WIDTH;lane_bit=lane_bit+1) begin
                    output_data_comb[(_output*LANE_WIDTH) + lane_bit] = entry[lane_bit];
                end
            end
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[63:0] _output;
        logic[63:0] lane_byte;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[8-1:0] entry;
        output_keep_comb = 'h0;
        logical='h0;
        bank='h0;
        row='h0;
        entry = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (unsigned'(32'(count_reg[_output])) != 'h0) begin
                logical=unsigned'(32'(head_reg[_output]));
                bank=logical & ((FIFO_BANKS - 'h1));
                row=logical >>> 'h3;
                if ((_output == 'h0) && (bank == 'h0)) begin
                    entry = keep_0_0[row];
                end
                if ((_output == 'h0) && (bank == 'h1)) begin
                    entry = keep_0_1[row];
                end
                if ((_output == 'h0) && (bank == 'h2)) begin
                    entry = keep_0_2[row];
                end
                if ((_output == 'h0) && (bank == 'h3)) begin
                    entry = keep_0_3[row];
                end
                if ((_output == 'h0) && (bank == 'h4)) begin
                    entry = keep_0_4[row];
                end
                if ((_output == 'h0) && (bank == 'h5)) begin
                    entry = keep_0_5[row];
                end
                if ((_output == 'h0) && (bank == 'h6)) begin
                    entry = keep_0_6[row];
                end
                if ((_output == 'h0) && (bank == 'h7)) begin
                    entry = keep_0_7[row];
                end
                if ((_output == 'h1) && (bank == 'h0)) begin
                    entry = keep_1_0[row];
                end
                if ((_output == 'h1) && (bank == 'h1)) begin
                    entry = keep_1_1[row];
                end
                if ((_output == 'h1) && (bank == 'h2)) begin
                    entry = keep_1_2[row];
                end
                if ((_output == 'h1) && (bank == 'h3)) begin
                    entry = keep_1_3[row];
                end
                if ((_output == 'h1) && (bank == 'h4)) begin
                    entry = keep_1_4[row];
                end
                if ((_output == 'h1) && (bank == 'h5)) begin
                    entry = keep_1_5[row];
                end
                if ((_output == 'h1) && (bank == 'h6)) begin
                    entry = keep_1_6[row];
                end
                if ((_output == 'h1) && (bank == 'h7)) begin
                    entry = keep_1_7[row];
                end
                for (lane_byte='h0;lane_byte < LANE_BYTES;lane_byte=lane_byte+1) begin
                    output_keep_comb[(_output*LANE_BYTES) + lane_byte] = entry[lane_byte];
                end
            end
        end
    end

    always_comb begin : output_sop_comb_func  // output_sop_comb_func
        logic[63:0] _output;
        logic[63:0] lane_byte;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[8-1:0] entry;
        output_sop_comb = 'h0;
        logical='h0;
        bank='h0;
        row='h0;
        entry = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (unsigned'(32'(count_reg[_output])) != 'h0) begin
                logical=unsigned'(32'(head_reg[_output]));
                bank=logical & ((FIFO_BANKS - 'h1));
                row=logical >>> 'h3;
                if ((_output == 'h0) && (bank == 'h0)) begin
                    entry = sop_0_0[row];
                end
                if ((_output == 'h0) && (bank == 'h1)) begin
                    entry = sop_0_1[row];
                end
                if ((_output == 'h0) && (bank == 'h2)) begin
                    entry = sop_0_2[row];
                end
                if ((_output == 'h0) && (bank == 'h3)) begin
                    entry = sop_0_3[row];
                end
                if ((_output == 'h0) && (bank == 'h4)) begin
                    entry = sop_0_4[row];
                end
                if ((_output == 'h0) && (bank == 'h5)) begin
                    entry = sop_0_5[row];
                end
                if ((_output == 'h0) && (bank == 'h6)) begin
                    entry = sop_0_6[row];
                end
                if ((_output == 'h0) && (bank == 'h7)) begin
                    entry = sop_0_7[row];
                end
                if ((_output == 'h1) && (bank == 'h0)) begin
                    entry = sop_1_0[row];
                end
                if ((_output == 'h1) && (bank == 'h1)) begin
                    entry = sop_1_1[row];
                end
                if ((_output == 'h1) && (bank == 'h2)) begin
                    entry = sop_1_2[row];
                end
                if ((_output == 'h1) && (bank == 'h3)) begin
                    entry = sop_1_3[row];
                end
                if ((_output == 'h1) && (bank == 'h4)) begin
                    entry = sop_1_4[row];
                end
                if ((_output == 'h1) && (bank == 'h5)) begin
                    entry = sop_1_5[row];
                end
                if ((_output == 'h1) && (bank == 'h6)) begin
                    entry = sop_1_6[row];
                end
                if ((_output == 'h1) && (bank == 'h7)) begin
                    entry = sop_1_7[row];
                end
                for (lane_byte='h0;lane_byte < LANE_BYTES;lane_byte=lane_byte+1) begin
                    output_sop_comb[(_output*LANE_BYTES) + lane_byte] = entry[lane_byte];
                end
            end
        end
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        logic[63:0] _output;
        logic[63:0] lane_byte;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[8-1:0] entry;
        output_eop_comb = 'h0;
        logical='h0;
        bank='h0;
        row='h0;
        entry = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (unsigned'(32'(count_reg[_output])) != 'h0) begin
                logical=unsigned'(32'(head_reg[_output]));
                bank=logical & ((FIFO_BANKS - 'h1));
                row=logical >>> 'h3;
                if ((_output == 'h0) && (bank == 'h0)) begin
                    entry = eop_0_0[row];
                end
                if ((_output == 'h0) && (bank == 'h1)) begin
                    entry = eop_0_1[row];
                end
                if ((_output == 'h0) && (bank == 'h2)) begin
                    entry = eop_0_2[row];
                end
                if ((_output == 'h0) && (bank == 'h3)) begin
                    entry = eop_0_3[row];
                end
                if ((_output == 'h0) && (bank == 'h4)) begin
                    entry = eop_0_4[row];
                end
                if ((_output == 'h0) && (bank == 'h5)) begin
                    entry = eop_0_5[row];
                end
                if ((_output == 'h0) && (bank == 'h6)) begin
                    entry = eop_0_6[row];
                end
                if ((_output == 'h0) && (bank == 'h7)) begin
                    entry = eop_0_7[row];
                end
                if ((_output == 'h1) && (bank == 'h0)) begin
                    entry = eop_1_0[row];
                end
                if ((_output == 'h1) && (bank == 'h1)) begin
                    entry = eop_1_1[row];
                end
                if ((_output == 'h1) && (bank == 'h2)) begin
                    entry = eop_1_2[row];
                end
                if ((_output == 'h1) && (bank == 'h3)) begin
                    entry = eop_1_3[row];
                end
                if ((_output == 'h1) && (bank == 'h4)) begin
                    entry = eop_1_4[row];
                end
                if ((_output == 'h1) && (bank == 'h5)) begin
                    entry = eop_1_5[row];
                end
                if ((_output == 'h1) && (bank == 'h6)) begin
                    entry = eop_1_6[row];
                end
                if ((_output == 'h1) && (bank == 'h7)) begin
                    entry = eop_1_7[row];
                end
                for (lane_byte='h0;lane_byte < LANE_BYTES;lane_byte=lane_byte+1) begin
                    output_eop_comb[(_output*LANE_BYTES) + lane_byte] = entry[lane_byte];
                end
            end
        end
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        logic[63:0] _output;
        output_valid_comb = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            output_valid_comb[_output] = unsigned'(32'(count_reg[_output])) != 'h0;
        end
    end

    generate  // _assign
        assign ready_out = input_ready_comb;
        assign data_out = output_data_comb;
        assign keep_out = output_keep_comb;
        assign sop_out = output_sop_comb;
        assign eop_out = output_eop_comb;
        assign valid_out = output_valid_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    always @(posedge net_clk) begin: input_balancer_clocked
        logic[63:0] _output;
        logic[63:0] _byte;
        logic[63:0] offset;
        logic[2-1:0][31:0] head;
        logic[2-1:0][31:0] tail;
        logic[2-1:0][31:0] count;
        logic[2-1:0][31:0] pushes;
        logic[2-1:0][31:0] pack_count;
        logic[2-1:0][31:0] pack_age;
        logic[2-1:0] pack_boundary;
        logic[2-1:0] appended;
        logic[2-1:0] reserved;
        logic write_valid_0_0;
        logic[31:0] write_row_0_0;
        logic[64-1:0] write_data_0_0;
        logic[8-1:0] write_keep_0_0;
        logic[8-1:0] write_sop_0_0;
        logic[8-1:0] write_eop_0_0;
        logic write_valid_0_1;
        logic[31:0] write_row_0_1;
        logic[64-1:0] write_data_0_1;
        logic[8-1:0] write_keep_0_1;
        logic[8-1:0] write_sop_0_1;
        logic[8-1:0] write_eop_0_1;
        logic write_valid_0_2;
        logic[31:0] write_row_0_2;
        logic[64-1:0] write_data_0_2;
        logic[8-1:0] write_keep_0_2;
        logic[8-1:0] write_sop_0_2;
        logic[8-1:0] write_eop_0_2;
        logic write_valid_0_3;
        logic[31:0] write_row_0_3;
        logic[64-1:0] write_data_0_3;
        logic[8-1:0] write_keep_0_3;
        logic[8-1:0] write_sop_0_3;
        logic[8-1:0] write_eop_0_3;
        logic write_valid_0_4;
        logic[31:0] write_row_0_4;
        logic[64-1:0] write_data_0_4;
        logic[8-1:0] write_keep_0_4;
        logic[8-1:0] write_sop_0_4;
        logic[8-1:0] write_eop_0_4;
        logic write_valid_0_5;
        logic[31:0] write_row_0_5;
        logic[64-1:0] write_data_0_5;
        logic[8-1:0] write_keep_0_5;
        logic[8-1:0] write_sop_0_5;
        logic[8-1:0] write_eop_0_5;
        logic write_valid_0_6;
        logic[31:0] write_row_0_6;
        logic[64-1:0] write_data_0_6;
        logic[8-1:0] write_keep_0_6;
        logic[8-1:0] write_sop_0_6;
        logic[8-1:0] write_eop_0_6;
        logic write_valid_0_7;
        logic[31:0] write_row_0_7;
        logic[64-1:0] write_data_0_7;
        logic[8-1:0] write_keep_0_7;
        logic[8-1:0] write_sop_0_7;
        logic[8-1:0] write_eop_0_7;
        logic write_valid_1_0;
        logic[31:0] write_row_1_0;
        logic[64-1:0] write_data_1_0;
        logic[8-1:0] write_keep_1_0;
        logic[8-1:0] write_sop_1_0;
        logic[8-1:0] write_eop_1_0;
        logic write_valid_1_1;
        logic[31:0] write_row_1_1;
        logic[64-1:0] write_data_1_1;
        logic[8-1:0] write_keep_1_1;
        logic[8-1:0] write_sop_1_1;
        logic[8-1:0] write_eop_1_1;
        logic write_valid_1_2;
        logic[31:0] write_row_1_2;
        logic[64-1:0] write_data_1_2;
        logic[8-1:0] write_keep_1_2;
        logic[8-1:0] write_sop_1_2;
        logic[8-1:0] write_eop_1_2;
        logic write_valid_1_3;
        logic[31:0] write_row_1_3;
        logic[64-1:0] write_data_1_3;
        logic[8-1:0] write_keep_1_3;
        logic[8-1:0] write_sop_1_3;
        logic[8-1:0] write_eop_1_3;
        logic write_valid_1_4;
        logic[31:0] write_row_1_4;
        logic[64-1:0] write_data_1_4;
        logic[8-1:0] write_keep_1_4;
        logic[8-1:0] write_sop_1_4;
        logic[8-1:0] write_eop_1_4;
        logic write_valid_1_5;
        logic[31:0] write_row_1_5;
        logic[64-1:0] write_data_1_5;
        logic[8-1:0] write_keep_1_5;
        logic[8-1:0] write_sop_1_5;
        logic[8-1:0] write_eop_1_5;
        logic write_valid_1_6;
        logic[31:0] write_row_1_6;
        logic[64-1:0] write_data_1_6;
        logic[8-1:0] write_keep_1_6;
        logic[8-1:0] write_sop_1_6;
        logic[8-1:0] write_eop_1_6;
        logic write_valid_1_7;
        logic[31:0] write_row_1_7;
        logic[64-1:0] write_data_1_7;
        logic[8-1:0] write_keep_1_7;
        logic[8-1:0] write_sop_1_7;
        logic[8-1:0] write_eop_1_7;
        logic in_frame;
        logic found;
        logic keep;
        logic sop;
        logic eop;
        logic[31:0] rr;
        logic[31:0] dest;
        logic[31:0] candidate;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[7:0] input_byte;

        head_reg_tmp = head_reg;
        tail_reg_tmp = tail_reg;
        count_reg_tmp = count_reg;
        pack_data_reg_tmp = pack_data_reg;
        pack_keep_reg_tmp = pack_keep_reg;
        pack_sop_reg_tmp = pack_sop_reg;
        pack_eop_reg_tmp = pack_eop_reg;
        pack_count_reg_tmp = pack_count_reg;
        pack_boundary_reg_tmp = pack_boundary_reg;
        pack_age_reg_tmp = pack_age_reg;
        rr_reg_tmp = rr_reg;
        frame_dest_reg_tmp = frame_dest_reg;
        in_frame_reg_tmp = in_frame_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        if (reset) begin
            for (_output='h0;_output < LANES;_output=_output+1) begin
                head_reg_tmp[_output] = 'h0;
                tail_reg_tmp[_output] = 'h0;
                count_reg_tmp[_output] = 'h0;
                pack_data_reg_tmp[_output] = 'h0;
                pack_keep_reg_tmp[_output] = 'h0;
                pack_sop_reg_tmp[_output] = 'h0;
                pack_eop_reg_tmp[_output] = 'h0;
                pack_count_reg_tmp[_output] = 'h0;
                pack_boundary_reg_tmp[_output] = unsigned'(1'h0);
                pack_age_reg_tmp[_output] = 'h0;
            end
            rr_reg_tmp = 'h0;
            frame_dest_reg_tmp = 'h0;
            in_frame_reg_tmp = unsigned'(1'h0);
            protocol_error_reg_tmp = unsigned'(1'h0);
            disable input_balancer_clocked;
        end
        write_valid_0_0=0;
        write_row_0_0='h0;
        write_data_0_0 = 'h0;
        write_keep_0_0 = 'h0;
        write_sop_0_0 = 'h0;
        write_eop_0_0 = 'h0;
        write_valid_0_1=0;
        write_row_0_1='h0;
        write_data_0_1 = 'h0;
        write_keep_0_1 = 'h0;
        write_sop_0_1 = 'h0;
        write_eop_0_1 = 'h0;
        write_valid_0_2=0;
        write_row_0_2='h0;
        write_data_0_2 = 'h0;
        write_keep_0_2 = 'h0;
        write_sop_0_2 = 'h0;
        write_eop_0_2 = 'h0;
        write_valid_0_3=0;
        write_row_0_3='h0;
        write_data_0_3 = 'h0;
        write_keep_0_3 = 'h0;
        write_sop_0_3 = 'h0;
        write_eop_0_3 = 'h0;
        write_valid_0_4=0;
        write_row_0_4='h0;
        write_data_0_4 = 'h0;
        write_keep_0_4 = 'h0;
        write_sop_0_4 = 'h0;
        write_eop_0_4 = 'h0;
        write_valid_0_5=0;
        write_row_0_5='h0;
        write_data_0_5 = 'h0;
        write_keep_0_5 = 'h0;
        write_sop_0_5 = 'h0;
        write_eop_0_5 = 'h0;
        write_valid_0_6=0;
        write_row_0_6='h0;
        write_data_0_6 = 'h0;
        write_keep_0_6 = 'h0;
        write_sop_0_6 = 'h0;
        write_eop_0_6 = 'h0;
        write_valid_0_7=0;
        write_row_0_7='h0;
        write_data_0_7 = 'h0;
        write_keep_0_7 = 'h0;
        write_sop_0_7 = 'h0;
        write_eop_0_7 = 'h0;
        write_valid_1_0=0;
        write_row_1_0='h0;
        write_data_1_0 = 'h0;
        write_keep_1_0 = 'h0;
        write_sop_1_0 = 'h0;
        write_eop_1_0 = 'h0;
        write_valid_1_1=0;
        write_row_1_1='h0;
        write_data_1_1 = 'h0;
        write_keep_1_1 = 'h0;
        write_sop_1_1 = 'h0;
        write_eop_1_1 = 'h0;
        write_valid_1_2=0;
        write_row_1_2='h0;
        write_data_1_2 = 'h0;
        write_keep_1_2 = 'h0;
        write_sop_1_2 = 'h0;
        write_eop_1_2 = 'h0;
        write_valid_1_3=0;
        write_row_1_3='h0;
        write_data_1_3 = 'h0;
        write_keep_1_3 = 'h0;
        write_sop_1_3 = 'h0;
        write_eop_1_3 = 'h0;
        write_valid_1_4=0;
        write_row_1_4='h0;
        write_data_1_4 = 'h0;
        write_keep_1_4 = 'h0;
        write_sop_1_4 = 'h0;
        write_eop_1_4 = 'h0;
        write_valid_1_5=0;
        write_row_1_5='h0;
        write_data_1_5 = 'h0;
        write_keep_1_5 = 'h0;
        write_sop_1_5 = 'h0;
        write_eop_1_5 = 'h0;
        write_valid_1_6=0;
        write_row_1_6='h0;
        write_data_1_6 = 'h0;
        write_keep_1_6 = 'h0;
        write_sop_1_6 = 'h0;
        write_eop_1_6 = 'h0;
        write_valid_1_7=0;
        write_row_1_7='h0;
        write_data_1_7 = 'h0;
        write_keep_1_7 = 'h0;
        write_sop_1_7 = 'h0;
        write_eop_1_7 = 'h0;
        for (_output='h0;_output < LANES;_output=_output+1) begin
            head[_output]=unsigned'(32'(head_reg[_output]));
            tail[_output]=unsigned'(32'(tail_reg[_output]));
            count[_output]=unsigned'(32'(count_reg[_output]));
            pushes[_output]='h0;
            pack_count[_output]=unsigned'(32'(pack_count_reg[_output]));
            pack_age[_output]=unsigned'(32'(pack_age_reg[_output]));
            pack_data_reg_tmp[_output] = pack_data_reg[_output];
            pack_keep_reg_tmp[_output] = pack_keep_reg[_output];
            pack_sop_reg_tmp[_output] = pack_sop_reg[_output];
            pack_eop_reg_tmp[_output] = pack_eop_reg[_output];
            pack_boundary[_output]=pack_boundary_reg[_output];
            appended[_output]=0;
            reserved[_output]=0;
            if ((count[_output] != 'h0) && ready_in[_output]) begin
                head[_output]=((head[_output] + 'h1)) & ((FIFO_WORDS - 'h1));
                --count[_output];
            end
        end
        rr=unsigned'(32'(rr_reg));
        dest=unsigned'(32'(frame_dest_reg));
        in_frame=in_frame_reg;
        if (valid_in && input_ready_comb) begin
            for (_byte='h0;_byte < INPUT_BYTES;_byte=_byte+1) begin
                keep=keep_in[_byte];
                sop=sop_in[_byte];
                eop=eop_in[_byte];
                if (!keep) begin
                    if (sop || eop) begin
                        protocol_error_reg_tmp = unsigned'(1'h1);
                    end
                end
                else begin
                    if (sop) begin
                        if (in_frame) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        found=0;
                        candidate=rr;
                        for (offset='h0;offset < LANES;offset=offset+1) begin
                            candidate=((rr + offset)) & ((LANES - 'h1));
                            if ((!found && !reserved[candidate]) && output_eligible(candidate)) begin
                                dest=candidate;
                                found=1;
                            end
                        end
                        if (!found) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        else begin
                            reserved[dest]=1;
                            rr=((dest + 'h1)) & ((LANES - 'h1));
                        end
                        in_frame=1;
                    end
                    else begin
                        if (!in_frame) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                    input_byte=unsigned'(8'(data_in[_byte*'h8 +:8]));
                    for (offset='h0;offset < 'h8;offset=offset+1) begin
                        pack_data_reg_tmp[dest][(pack_count[dest]*'h8) + offset] = ((input_byte >>> offset)) & 'h1;
                    end
                    pack_keep_reg_tmp[dest][pack_count[dest]] = 'h1;
                    pack_sop_reg_tmp[dest][pack_count[dest]] = sop;
                    pack_eop_reg_tmp[dest][pack_count[dest]] = eop;
                    pack_count[dest]=pack_count[dest]+1;
                    appended[dest]=1;
                    pack_age[dest]='h0;
                    pack_boundary[dest]=eop;
                    if (pack_count[dest] == LANE_BYTES) begin
                        logical=((tail[dest] + pushes[dest])) & ((FIFO_WORDS - 'h1));
                        bank=logical & ((FIFO_BANKS - 'h1));
                        row=logical >>> 'h3;
                        if ((dest == 'h0) && (bank == 'h0)) begin
                            write_valid_0_0=1;
                            write_row_0_0=row;
                            write_data_0_0 = pack_data_reg_tmp[dest];
                            write_keep_0_0 = pack_keep_reg_tmp[dest];
                            write_sop_0_0 = pack_sop_reg_tmp[dest];
                            write_eop_0_0 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h1)) begin
                            write_valid_0_1=1;
                            write_row_0_1=row;
                            write_data_0_1 = pack_data_reg_tmp[dest];
                            write_keep_0_1 = pack_keep_reg_tmp[dest];
                            write_sop_0_1 = pack_sop_reg_tmp[dest];
                            write_eop_0_1 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h2)) begin
                            write_valid_0_2=1;
                            write_row_0_2=row;
                            write_data_0_2 = pack_data_reg_tmp[dest];
                            write_keep_0_2 = pack_keep_reg_tmp[dest];
                            write_sop_0_2 = pack_sop_reg_tmp[dest];
                            write_eop_0_2 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h3)) begin
                            write_valid_0_3=1;
                            write_row_0_3=row;
                            write_data_0_3 = pack_data_reg_tmp[dest];
                            write_keep_0_3 = pack_keep_reg_tmp[dest];
                            write_sop_0_3 = pack_sop_reg_tmp[dest];
                            write_eop_0_3 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h4)) begin
                            write_valid_0_4=1;
                            write_row_0_4=row;
                            write_data_0_4 = pack_data_reg_tmp[dest];
                            write_keep_0_4 = pack_keep_reg_tmp[dest];
                            write_sop_0_4 = pack_sop_reg_tmp[dest];
                            write_eop_0_4 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h5)) begin
                            write_valid_0_5=1;
                            write_row_0_5=row;
                            write_data_0_5 = pack_data_reg_tmp[dest];
                            write_keep_0_5 = pack_keep_reg_tmp[dest];
                            write_sop_0_5 = pack_sop_reg_tmp[dest];
                            write_eop_0_5 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h6)) begin
                            write_valid_0_6=1;
                            write_row_0_6=row;
                            write_data_0_6 = pack_data_reg_tmp[dest];
                            write_keep_0_6 = pack_keep_reg_tmp[dest];
                            write_sop_0_6 = pack_sop_reg_tmp[dest];
                            write_eop_0_6 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h0) && (bank == 'h7)) begin
                            write_valid_0_7=1;
                            write_row_0_7=row;
                            write_data_0_7 = pack_data_reg_tmp[dest];
                            write_keep_0_7 = pack_keep_reg_tmp[dest];
                            write_sop_0_7 = pack_sop_reg_tmp[dest];
                            write_eop_0_7 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h0)) begin
                            write_valid_1_0=1;
                            write_row_1_0=row;
                            write_data_1_0 = pack_data_reg_tmp[dest];
                            write_keep_1_0 = pack_keep_reg_tmp[dest];
                            write_sop_1_0 = pack_sop_reg_tmp[dest];
                            write_eop_1_0 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h1)) begin
                            write_valid_1_1=1;
                            write_row_1_1=row;
                            write_data_1_1 = pack_data_reg_tmp[dest];
                            write_keep_1_1 = pack_keep_reg_tmp[dest];
                            write_sop_1_1 = pack_sop_reg_tmp[dest];
                            write_eop_1_1 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h2)) begin
                            write_valid_1_2=1;
                            write_row_1_2=row;
                            write_data_1_2 = pack_data_reg_tmp[dest];
                            write_keep_1_2 = pack_keep_reg_tmp[dest];
                            write_sop_1_2 = pack_sop_reg_tmp[dest];
                            write_eop_1_2 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h3)) begin
                            write_valid_1_3=1;
                            write_row_1_3=row;
                            write_data_1_3 = pack_data_reg_tmp[dest];
                            write_keep_1_3 = pack_keep_reg_tmp[dest];
                            write_sop_1_3 = pack_sop_reg_tmp[dest];
                            write_eop_1_3 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h4)) begin
                            write_valid_1_4=1;
                            write_row_1_4=row;
                            write_data_1_4 = pack_data_reg_tmp[dest];
                            write_keep_1_4 = pack_keep_reg_tmp[dest];
                            write_sop_1_4 = pack_sop_reg_tmp[dest];
                            write_eop_1_4 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h5)) begin
                            write_valid_1_5=1;
                            write_row_1_5=row;
                            write_data_1_5 = pack_data_reg_tmp[dest];
                            write_keep_1_5 = pack_keep_reg_tmp[dest];
                            write_sop_1_5 = pack_sop_reg_tmp[dest];
                            write_eop_1_5 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h6)) begin
                            write_valid_1_6=1;
                            write_row_1_6=row;
                            write_data_1_6 = pack_data_reg_tmp[dest];
                            write_keep_1_6 = pack_keep_reg_tmp[dest];
                            write_sop_1_6 = pack_sop_reg_tmp[dest];
                            write_eop_1_6 = pack_eop_reg_tmp[dest];
                        end
                        if ((dest == 'h1) && (bank == 'h7)) begin
                            write_valid_1_7=1;
                            write_row_1_7=row;
                            write_data_1_7 = pack_data_reg_tmp[dest];
                            write_keep_1_7 = pack_keep_reg_tmp[dest];
                            write_sop_1_7 = pack_sop_reg_tmp[dest];
                            write_eop_1_7 = pack_eop_reg_tmp[dest];
                        end
                        pushes[dest]=pushes[dest]+1;
                        pack_data_reg_tmp[dest] = 'h0;
                        pack_keep_reg_tmp[dest] = 'h0;
                        pack_sop_reg_tmp[dest] = 'h0;
                        pack_eop_reg_tmp[dest] = 'h0;
                        pack_count[dest]='h0;
                        pack_boundary[dest]=0;
                    end
                    if (eop) begin
                        if (!in_frame) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                        in_frame=0;
                    end
                end
            end
        end
        for (_output='h0;_output < LANES;_output=_output+1) begin
            if (((pack_count[_output] != 'h0) && pack_boundary[_output]) && !appended[_output]) begin
                if (pack_age[_output] + 'h1>=FLUSH_CYCLES) begin
                    logical=((tail[_output] + pushes[_output])) & ((FIFO_WORDS - 'h1));
                    bank=logical & ((FIFO_BANKS - 'h1));
                    row=logical >>> 'h3;
                    if ((_output == 'h0) && (bank == 'h0)) begin
                        write_valid_0_0=1;
                        write_row_0_0=row;
                        write_data_0_0 = pack_data_reg_tmp[_output];
                        write_keep_0_0 = pack_keep_reg_tmp[_output];
                        write_sop_0_0 = pack_sop_reg_tmp[_output];
                        write_eop_0_0 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h1)) begin
                        write_valid_0_1=1;
                        write_row_0_1=row;
                        write_data_0_1 = pack_data_reg_tmp[_output];
                        write_keep_0_1 = pack_keep_reg_tmp[_output];
                        write_sop_0_1 = pack_sop_reg_tmp[_output];
                        write_eop_0_1 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h2)) begin
                        write_valid_0_2=1;
                        write_row_0_2=row;
                        write_data_0_2 = pack_data_reg_tmp[_output];
                        write_keep_0_2 = pack_keep_reg_tmp[_output];
                        write_sop_0_2 = pack_sop_reg_tmp[_output];
                        write_eop_0_2 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h3)) begin
                        write_valid_0_3=1;
                        write_row_0_3=row;
                        write_data_0_3 = pack_data_reg_tmp[_output];
                        write_keep_0_3 = pack_keep_reg_tmp[_output];
                        write_sop_0_3 = pack_sop_reg_tmp[_output];
                        write_eop_0_3 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h4)) begin
                        write_valid_0_4=1;
                        write_row_0_4=row;
                        write_data_0_4 = pack_data_reg_tmp[_output];
                        write_keep_0_4 = pack_keep_reg_tmp[_output];
                        write_sop_0_4 = pack_sop_reg_tmp[_output];
                        write_eop_0_4 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h5)) begin
                        write_valid_0_5=1;
                        write_row_0_5=row;
                        write_data_0_5 = pack_data_reg_tmp[_output];
                        write_keep_0_5 = pack_keep_reg_tmp[_output];
                        write_sop_0_5 = pack_sop_reg_tmp[_output];
                        write_eop_0_5 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h6)) begin
                        write_valid_0_6=1;
                        write_row_0_6=row;
                        write_data_0_6 = pack_data_reg_tmp[_output];
                        write_keep_0_6 = pack_keep_reg_tmp[_output];
                        write_sop_0_6 = pack_sop_reg_tmp[_output];
                        write_eop_0_6 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h0) && (bank == 'h7)) begin
                        write_valid_0_7=1;
                        write_row_0_7=row;
                        write_data_0_7 = pack_data_reg_tmp[_output];
                        write_keep_0_7 = pack_keep_reg_tmp[_output];
                        write_sop_0_7 = pack_sop_reg_tmp[_output];
                        write_eop_0_7 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h0)) begin
                        write_valid_1_0=1;
                        write_row_1_0=row;
                        write_data_1_0 = pack_data_reg_tmp[_output];
                        write_keep_1_0 = pack_keep_reg_tmp[_output];
                        write_sop_1_0 = pack_sop_reg_tmp[_output];
                        write_eop_1_0 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h1)) begin
                        write_valid_1_1=1;
                        write_row_1_1=row;
                        write_data_1_1 = pack_data_reg_tmp[_output];
                        write_keep_1_1 = pack_keep_reg_tmp[_output];
                        write_sop_1_1 = pack_sop_reg_tmp[_output];
                        write_eop_1_1 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h2)) begin
                        write_valid_1_2=1;
                        write_row_1_2=row;
                        write_data_1_2 = pack_data_reg_tmp[_output];
                        write_keep_1_2 = pack_keep_reg_tmp[_output];
                        write_sop_1_2 = pack_sop_reg_tmp[_output];
                        write_eop_1_2 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h3)) begin
                        write_valid_1_3=1;
                        write_row_1_3=row;
                        write_data_1_3 = pack_data_reg_tmp[_output];
                        write_keep_1_3 = pack_keep_reg_tmp[_output];
                        write_sop_1_3 = pack_sop_reg_tmp[_output];
                        write_eop_1_3 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h4)) begin
                        write_valid_1_4=1;
                        write_row_1_4=row;
                        write_data_1_4 = pack_data_reg_tmp[_output];
                        write_keep_1_4 = pack_keep_reg_tmp[_output];
                        write_sop_1_4 = pack_sop_reg_tmp[_output];
                        write_eop_1_4 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h5)) begin
                        write_valid_1_5=1;
                        write_row_1_5=row;
                        write_data_1_5 = pack_data_reg_tmp[_output];
                        write_keep_1_5 = pack_keep_reg_tmp[_output];
                        write_sop_1_5 = pack_sop_reg_tmp[_output];
                        write_eop_1_5 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h6)) begin
                        write_valid_1_6=1;
                        write_row_1_6=row;
                        write_data_1_6 = pack_data_reg_tmp[_output];
                        write_keep_1_6 = pack_keep_reg_tmp[_output];
                        write_sop_1_6 = pack_sop_reg_tmp[_output];
                        write_eop_1_6 = pack_eop_reg_tmp[_output];
                    end
                    if ((_output == 'h1) && (bank == 'h7)) begin
                        write_valid_1_7=1;
                        write_row_1_7=row;
                        write_data_1_7 = pack_data_reg_tmp[_output];
                        write_keep_1_7 = pack_keep_reg_tmp[_output];
                        write_sop_1_7 = pack_sop_reg_tmp[_output];
                        write_eop_1_7 = pack_eop_reg_tmp[_output];
                    end
                    pushes[_output]=pushes[_output]+1;
                    pack_data_reg_tmp[_output] = 'h0;
                    pack_keep_reg_tmp[_output] = 'h0;
                    pack_sop_reg_tmp[_output] = 'h0;
                    pack_eop_reg_tmp[_output] = 'h0;
                    pack_count[_output]='h0;
                    pack_boundary[_output]=0;
                    pack_age[_output]='h0;
                end
                else begin
                    pack_age[_output]=pack_age[_output]+1;
                end
            end
            if ((count[_output] + pushes[_output]) > FIFO_WORDS) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
            else begin
                count[_output]+=pushes[_output];
            end
            tail[_output]=((tail[_output] + pushes[_output])) & ((FIFO_WORDS - 'h1));
            head_reg_tmp[_output] = unsigned'(POINTER_BITS'(unsigned'(POINTER_BITS'(head[_output]))));
            tail_reg_tmp[_output] = unsigned'(POINTER_BITS'(unsigned'(POINTER_BITS'(tail[_output]))));
            count_reg_tmp[_output] = unsigned'(COUNT_BITS'(unsigned'(COUNT_BITS'(count[_output]))));
            pack_count_reg_tmp[_output] = unsigned'(PACK_COUNT_BITS'(unsigned'(PACK_COUNT_BITS'(pack_count[_output]))));
            pack_boundary_reg_tmp[_output] = unsigned'(1'(pack_boundary[_output]));
            pack_age_reg_tmp[_output] = unsigned'(AGE_BITS'(unsigned'(AGE_BITS'(pack_age[_output]))));
        end
        if (write_valid_0_0) begin
            data_0_0[write_row_0_0] <= write_data_0_0;
            keep_0_0[write_row_0_0] <= write_keep_0_0;
            sop_0_0[write_row_0_0] <= write_sop_0_0;
            eop_0_0[write_row_0_0] <= write_eop_0_0;
        end
        if (write_valid_0_1) begin
            data_0_1[write_row_0_1] <= write_data_0_1;
            keep_0_1[write_row_0_1] <= write_keep_0_1;
            sop_0_1[write_row_0_1] <= write_sop_0_1;
            eop_0_1[write_row_0_1] <= write_eop_0_1;
        end
        if (write_valid_0_2) begin
            data_0_2[write_row_0_2] <= write_data_0_2;
            keep_0_2[write_row_0_2] <= write_keep_0_2;
            sop_0_2[write_row_0_2] <= write_sop_0_2;
            eop_0_2[write_row_0_2] <= write_eop_0_2;
        end
        if (write_valid_0_3) begin
            data_0_3[write_row_0_3] <= write_data_0_3;
            keep_0_3[write_row_0_3] <= write_keep_0_3;
            sop_0_3[write_row_0_3] <= write_sop_0_3;
            eop_0_3[write_row_0_3] <= write_eop_0_3;
        end
        if (write_valid_0_4) begin
            data_0_4[write_row_0_4] <= write_data_0_4;
            keep_0_4[write_row_0_4] <= write_keep_0_4;
            sop_0_4[write_row_0_4] <= write_sop_0_4;
            eop_0_4[write_row_0_4] <= write_eop_0_4;
        end
        if (write_valid_0_5) begin
            data_0_5[write_row_0_5] <= write_data_0_5;
            keep_0_5[write_row_0_5] <= write_keep_0_5;
            sop_0_5[write_row_0_5] <= write_sop_0_5;
            eop_0_5[write_row_0_5] <= write_eop_0_5;
        end
        if (write_valid_0_6) begin
            data_0_6[write_row_0_6] <= write_data_0_6;
            keep_0_6[write_row_0_6] <= write_keep_0_6;
            sop_0_6[write_row_0_6] <= write_sop_0_6;
            eop_0_6[write_row_0_6] <= write_eop_0_6;
        end
        if (write_valid_0_7) begin
            data_0_7[write_row_0_7] <= write_data_0_7;
            keep_0_7[write_row_0_7] <= write_keep_0_7;
            sop_0_7[write_row_0_7] <= write_sop_0_7;
            eop_0_7[write_row_0_7] <= write_eop_0_7;
        end
        if (write_valid_1_0) begin
            data_1_0[write_row_1_0] <= write_data_1_0;
            keep_1_0[write_row_1_0] <= write_keep_1_0;
            sop_1_0[write_row_1_0] <= write_sop_1_0;
            eop_1_0[write_row_1_0] <= write_eop_1_0;
        end
        if (write_valid_1_1) begin
            data_1_1[write_row_1_1] <= write_data_1_1;
            keep_1_1[write_row_1_1] <= write_keep_1_1;
            sop_1_1[write_row_1_1] <= write_sop_1_1;
            eop_1_1[write_row_1_1] <= write_eop_1_1;
        end
        if (write_valid_1_2) begin
            data_1_2[write_row_1_2] <= write_data_1_2;
            keep_1_2[write_row_1_2] <= write_keep_1_2;
            sop_1_2[write_row_1_2] <= write_sop_1_2;
            eop_1_2[write_row_1_2] <= write_eop_1_2;
        end
        if (write_valid_1_3) begin
            data_1_3[write_row_1_3] <= write_data_1_3;
            keep_1_3[write_row_1_3] <= write_keep_1_3;
            sop_1_3[write_row_1_3] <= write_sop_1_3;
            eop_1_3[write_row_1_3] <= write_eop_1_3;
        end
        if (write_valid_1_4) begin
            data_1_4[write_row_1_4] <= write_data_1_4;
            keep_1_4[write_row_1_4] <= write_keep_1_4;
            sop_1_4[write_row_1_4] <= write_sop_1_4;
            eop_1_4[write_row_1_4] <= write_eop_1_4;
        end
        if (write_valid_1_5) begin
            data_1_5[write_row_1_5] <= write_data_1_5;
            keep_1_5[write_row_1_5] <= write_keep_1_5;
            sop_1_5[write_row_1_5] <= write_sop_1_5;
            eop_1_5[write_row_1_5] <= write_eop_1_5;
        end
        if (write_valid_1_6) begin
            data_1_6[write_row_1_6] <= write_data_1_6;
            keep_1_6[write_row_1_6] <= write_keep_1_6;
            sop_1_6[write_row_1_6] <= write_sop_1_6;
            eop_1_6[write_row_1_6] <= write_eop_1_6;
        end
        if (write_valid_1_7) begin
            data_1_7[write_row_1_7] <= write_data_1_7;
            keep_1_7[write_row_1_7] <= write_keep_1_7;
            sop_1_7[write_row_1_7] <= write_sop_1_7;
            eop_1_7[write_row_1_7] <= write_eop_1_7;
        end
        rr_reg_tmp = unsigned'(3'(unsigned'(3'(rr))));
        frame_dest_reg_tmp = unsigned'(3'(unsigned'(3'(dest))));
        in_frame_reg_tmp = unsigned'(1'(in_frame));

        head_reg <= head_reg_tmp;
        tail_reg <= tail_reg_tmp;
        count_reg <= count_reg_tmp;
        pack_data_reg <= pack_data_reg_tmp;
        pack_keep_reg <= pack_keep_reg_tmp;
        pack_sop_reg <= pack_sop_reg_tmp;
        pack_eop_reg <= pack_eop_reg_tmp;
        pack_count_reg <= pack_count_reg_tmp;
        pack_boundary_reg <= pack_boundary_reg_tmp;
        pack_age_reg <= pack_age_reg_tmp;
        rr_reg <= rr_reg_tmp;
        frame_dest_reg <= frame_dest_reg_tmp;
        in_frame_reg <= in_frame_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end


endmodule
