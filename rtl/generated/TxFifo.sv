`default_nettype none

import Predef_pkg::*;


module TxFifo #(
    parameter LANE_WIDTH = 'hA0
,   parameter FIFO_WORDS = 'h400
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire valid_in
,   input wire[LANE_WIDTH-1:0] data_in
,   input wire[LANE_BYTES-1:0] keep_in
,   input wire sop_in
,   input wire eop_in
,   output wire ready_out
,   output wire[WINDOW_WORDS*LANE_WIDTH-1:0] data_out
,   output wire[WINDOW_WORDS*LANE_BYTES-1:0] keep_out
,   output wire[8-1:0] sop_out
,   output wire[8-1:0] eop_out
,   output wire[8-1:0] valid_out
,   input wire[4-1:0] read_count_in
,   input wire clear_in
,   output wire almost_full_out
,   output wire protocol_error_out
);
    parameter  WINDOW_WORDS = 64'h8;
    parameter  LANE_BYTES = LANE_WIDTH/'h8;
    parameter  MAX_LANE_WIDTH = 64'h140;
    parameter  MAX_LANE_BYTES = 64'h28;
    parameter  BANK_DEPTH = FIFO_WORDS/WINDOW_WORDS;
    parameter  POINTER_BITS = $clog2(FIFO_WORDS);
    parameter  COUNT_BITS = $clog2(FIFO_WORDS + 'h1);


    // regs and combs
    reg[1-1:0][320-1:0] data_bank_0[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_0[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_0[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_0[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_1[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_1[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_1[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_1[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_2[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_2[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_2[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_2[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_3[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_3[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_3[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_3[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_4[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_4[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_4[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_4[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_5[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_5[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_5[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_5[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_6[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_6[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_6[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_6[BANK_DEPTH];
    reg[1-1:0][320-1:0] data_bank_7[BANK_DEPTH];
    reg[1-1:0][40-1:0] keep_bank_7[BANK_DEPTH];
    reg[1-1:0][1-1:0] sop_bank_7[BANK_DEPTH];
    reg[1-1:0][1-1:0] eop_bank_7[BANK_DEPTH];
    reg[POINTER_BITS-1:0] head_reg;
    reg[POINTER_BITS-1:0] tail_reg;
    reg[COUNT_BITS-1:0] total_count_reg;
    reg[COUNT_BITS-1:0] committed_count_reg;
    reg[COUNT_BITS-1:0] pending_count_reg;
    reg in_packet_reg;
    reg protocol_error_reg;
    logic ready_comb;
;
    logic[8-1:0] window_valid_comb;
;
    logic[WINDOW_WORDS*LANE_WIDTH-1:0] window_data_comb;
;
    logic[WINDOW_WORDS*LANE_BYTES-1:0] window_keep_comb;
;
    logic[8-1:0] window_sop_comb;
;
    logic[8-1:0] window_eop_comb;
;
    logic almost_full_comb;
;

    // members

    // tmp variables
    logic[POINTER_BITS-1:0] head_reg_tmp;
    logic[POINTER_BITS-1:0] tail_reg_tmp;
    logic[COUNT_BITS-1:0] total_count_reg_tmp;
    logic[COUNT_BITS-1:0] committed_count_reg_tmp;
    logic[COUNT_BITS-1:0] pending_count_reg_tmp;
    logic in_packet_reg_tmp;
    logic protocol_error_reg_tmp;


    always_comb begin : ready_comb_func  // ready_comb_func
        logic[31:0] count;
        logic[31:0] pop;
        count=unsigned'(32'(total_count_reg));
        pop=unsigned'(32'(read_count_in));
        if (pop<=count) begin
            count-=pop;
        end
        ready_comb=count < FIFO_WORDS;
    end

    always_comb begin : window_valid_comb_func  // window_valid_comb_func
        logic[63:0] slot;
        window_valid_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            window_valid_comb[slot] = slot < unsigned'(32'(committed_count_reg));
        end
    end

    always_comb begin : window_data_comb_func  // window_data_comb_func
        logic[63:0] slot;
        logic[63:0] _bit;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[320-1:0] entry;
        window_data_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            row=logical >>> 'h3;
            entry = 'h0;
            if (bank == 'h0) begin
                entry = data_bank_0[row];
            end
            if (bank == 'h1) begin
                entry = data_bank_1[row];
            end
            if (bank == 'h2) begin
                entry = data_bank_2[row];
            end
            if (bank == 'h3) begin
                entry = data_bank_3[row];
            end
            if (bank == 'h4) begin
                entry = data_bank_4[row];
            end
            if (bank == 'h5) begin
                entry = data_bank_5[row];
            end
            if (bank == 'h6) begin
                entry = data_bank_6[row];
            end
            if (bank == 'h7) begin
                entry = data_bank_7[row];
            end
            for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                window_data_comb[(slot*LANE_WIDTH) + _bit] = entry[_bit];
            end
        end
    end

    always_comb begin : window_keep_comb_func  // window_keep_comb_func
        logic[63:0] slot;
        logic[63:0] _byte;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[40-1:0] entry;
        window_keep_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            row=logical >>> 'h3;
            entry = 'h0;
            if (bank == 'h0) begin
                entry = keep_bank_0[row];
            end
            if (bank == 'h1) begin
                entry = keep_bank_1[row];
            end
            if (bank == 'h2) begin
                entry = keep_bank_2[row];
            end
            if (bank == 'h3) begin
                entry = keep_bank_3[row];
            end
            if (bank == 'h4) begin
                entry = keep_bank_4[row];
            end
            if (bank == 'h5) begin
                entry = keep_bank_5[row];
            end
            if (bank == 'h6) begin
                entry = keep_bank_6[row];
            end
            if (bank == 'h7) begin
                entry = keep_bank_7[row];
            end
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                window_keep_comb[(slot*LANE_BYTES) + _byte] = entry[_byte];
            end
        end
    end

    always_comb begin : window_sop_comb_func  // window_sop_comb_func
        logic[63:0] slot;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[1-1:0] entry;
        window_sop_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            row=logical >>> 'h3;
            entry = 'h0;
            if (bank == 'h0) begin
                entry = sop_bank_0[row];
            end
            if (bank == 'h1) begin
                entry = sop_bank_1[row];
            end
            if (bank == 'h2) begin
                entry = sop_bank_2[row];
            end
            if (bank == 'h3) begin
                entry = sop_bank_3[row];
            end
            if (bank == 'h4) begin
                entry = sop_bank_4[row];
            end
            if (bank == 'h5) begin
                entry = sop_bank_5[row];
            end
            if (bank == 'h6) begin
                entry = sop_bank_6[row];
            end
            if (bank == 'h7) begin
                entry = sop_bank_7[row];
            end
            window_sop_comb[slot] = entry;
        end
    end

    always_comb begin : window_eop_comb_func  // window_eop_comb_func
        logic[63:0] slot;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[31:0] row;
        logic[1-1:0] entry;
        window_eop_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            row=logical >>> 'h3;
            entry = 'h0;
            if (bank == 'h0) begin
                entry = eop_bank_0[row];
            end
            if (bank == 'h1) begin
                entry = eop_bank_1[row];
            end
            if (bank == 'h2) begin
                entry = eop_bank_2[row];
            end
            if (bank == 'h3) begin
                entry = eop_bank_3[row];
            end
            if (bank == 'h4) begin
                entry = eop_bank_4[row];
            end
            if (bank == 'h5) begin
                entry = eop_bank_5[row];
            end
            if (bank == 'h6) begin
                entry = eop_bank_6[row];
            end
            if (bank == 'h7) begin
                entry = eop_bank_7[row];
            end
            window_eop_comb[slot] = entry;
        end
    end

    always_comb begin : almost_full_comb_func  // almost_full_comb_func
        almost_full_comb=total_count_reg>=FIFO_WORDS - WINDOW_WORDS;
    end

    generate  // _assign
        assign ready_out = ready_comb;
        assign data_out = window_data_comb;
        assign keep_out = window_keep_comb;
        assign sop_out = window_sop_comb;
        assign eop_out = window_eop_comb;
        assign valid_out = window_valid_comb;
        assign almost_full_out = almost_full_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[63:0] _byte;
        logic[31:0] pop;
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] total;
        logic[31:0] committed;
        logic[31:0] pending;
        logic[31:0] bank;
        logic[31:0] row;
        logic in_packet;
        logic seen_zero;
        logic malformed_keep;
        logic incomplete_keep;
        logic[320-1:0] data_entry;
        logic[40-1:0] keep_entry;
        if (reset) begin
            head_reg_tmp = '0;
            tail_reg_tmp = '0;
            total_count_reg_tmp = '0;
            committed_count_reg_tmp = '0;
            pending_count_reg_tmp = '0;
            in_packet_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            disable _work;
        end
        head=unsigned'(32'(head_reg));
        tail=unsigned'(32'(tail_reg));
        total=unsigned'(32'(total_count_reg));
        committed=unsigned'(32'(committed_count_reg));
        pending=unsigned'(32'(pending_count_reg));
        in_packet=in_packet_reg;
        pop=unsigned'(32'(read_count_in));
        if ((pop > WINDOW_WORDS) || (pop > committed)) begin
            if (pop != 'h0) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
            pop='h0;
        end
        head=((head + pop)) & ((FIFO_WORDS - 'h1));
        total-=pop;
        committed-=pop;
        if (valid_in && ready_comb) begin
            malformed_keep=0;
            incomplete_keep=0;
            seen_zero=0;
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                if (!keep_in[_byte]) begin
                    seen_zero=1;
                    incomplete_keep=1;
                end
                else begin
                    if (seen_zero) begin
                        malformed_keep=1;
                    end
                end
            end
            if (((unsigned'(64'(keep_in)) == 'h0) || ((!eop_in && incomplete_keep))) || malformed_keep) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
            if ((sop_in == in_packet) || (((eop_in && !in_packet) && !sop_in))) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
            data_entry = 'h0;
            keep_entry = 'h0;
            for (_byte='h0;_byte < LANE_WIDTH;_byte=_byte+1) begin
                data_entry[_byte] = data_in[_byte];
            end
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                keep_entry[_byte] = keep_in[_byte];
            end
            bank=tail & ((WINDOW_WORDS - 'h1));
            row=tail >>> 'h3;
            if (bank == 'h0) begin
                data_bank_0[row] <= data_entry;
                keep_bank_0[row] <= keep_entry;
                sop_bank_0[row] <= sop_in;
                eop_bank_0[row] <= eop_in;
            end
            if (bank == 'h1) begin
                data_bank_1[row] <= data_entry;
                keep_bank_1[row] <= keep_entry;
                sop_bank_1[row] <= sop_in;
                eop_bank_1[row] <= eop_in;
            end
            if (bank == 'h2) begin
                data_bank_2[row] <= data_entry;
                keep_bank_2[row] <= keep_entry;
                sop_bank_2[row] <= sop_in;
                eop_bank_2[row] <= eop_in;
            end
            if (bank == 'h3) begin
                data_bank_3[row] <= data_entry;
                keep_bank_3[row] <= keep_entry;
                sop_bank_3[row] <= sop_in;
                eop_bank_3[row] <= eop_in;
            end
            if (bank == 'h4) begin
                data_bank_4[row] <= data_entry;
                keep_bank_4[row] <= keep_entry;
                sop_bank_4[row] <= sop_in;
                eop_bank_4[row] <= eop_in;
            end
            if (bank == 'h5) begin
                data_bank_5[row] <= data_entry;
                keep_bank_5[row] <= keep_entry;
                sop_bank_5[row] <= sop_in;
                eop_bank_5[row] <= eop_in;
            end
            if (bank == 'h6) begin
                data_bank_6[row] <= data_entry;
                keep_bank_6[row] <= keep_entry;
                sop_bank_6[row] <= sop_in;
                eop_bank_6[row] <= eop_in;
            end
            if (bank == 'h7) begin
                data_bank_7[row] <= data_entry;
                keep_bank_7[row] <= keep_entry;
                sop_bank_7[row] <= sop_in;
                eop_bank_7[row] <= eop_in;
            end
            tail=((tail + 'h1)) & ((FIFO_WORDS - 'h1));
            total=total+1;
            if (eop_in) begin
                committed+=pending + 'h1;
                pending='h0;
                in_packet=0;
            end
            else begin
                pending=pending+1;
                in_packet=1;
            end
        end
        head_reg_tmp = head;
        tail_reg_tmp = tail;
        total_count_reg_tmp = total;
        committed_count_reg_tmp = committed;
        pending_count_reg_tmp = pending;
        in_packet_reg_tmp = unsigned'(1'(in_packet));
        if (clear_in) begin
            head_reg_tmp = 'h0;
            tail_reg_tmp = 'h0;
            total_count_reg_tmp = 'h0;
            committed_count_reg_tmp = 'h0;
            pending_count_reg_tmp = 'h0;
            in_packet_reg_tmp = unsigned'(1'h0);
        end
    end
    endtask

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        _work(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        head_reg_tmp = head_reg;
        tail_reg_tmp = tail_reg;
        total_count_reg_tmp = total_count_reg;
        committed_count_reg_tmp = committed_count_reg;
        pending_count_reg_tmp = pending_count_reg;
        in_packet_reg_tmp = in_packet_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        head_reg <= head_reg_tmp;
        tail_reg <= tail_reg_tmp;
        total_count_reg <= total_count_reg_tmp;
        committed_count_reg <= committed_count_reg_tmp;
        pending_count_reg <= pending_count_reg_tmp;
        in_packet_reg <= in_packet_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
