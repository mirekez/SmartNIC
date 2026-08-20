`default_nettype none

import Predef_pkg::*;


module TxFifo #(
    parameter LANE_WIDTH = 'h40
,   parameter FIFO_WORDS = 'h800
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
,   output wire[2-1:0] sop_out
,   output wire[2-1:0] eop_out
,   output wire[2-1:0] valid_out
,   input wire[4-1:0] read_count_in
,   input wire clear_in
,   output wire almost_full_out
,   output wire protocol_error_out
);
    localparam  WINDOW_WORDS = 64'h2;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  BANK_DEPTH = FIFO_WORDS/WINDOW_WORDS;
    localparam  ENTRY_BYTES = 64'hA;
    localparam  KEEP_OFFSET = LANE_WIDTH;
    localparam  SOP_OFFSET = KEEP_OFFSET + LANE_BYTES;
    localparam  EOP_OFFSET = SOP_OFFSET + 'h1;
    localparam  POINTER_BITS = $clog2(FIFO_WORDS);
    localparam  COUNT_BITS = $clog2(FIFO_WORDS + 'h1);
    localparam  MAX_LANE_WIDTH = 64'h40;
    localparam  MAX_LANE_BYTES = 64'h8;
    localparam  ENTRY_BITS = 64'h50;


    // regs and combs
    reg[POINTER_BITS-1:0] head_reg;
    reg[POINTER_BITS-1:0] tail_reg;
    reg[COUNT_BITS-1:0] total_count_reg;
    reg[COUNT_BITS-1:0] committed_count_reg;
    reg[COUNT_BITS-1:0] pending_count_reg;
    reg in_packet_reg;
    reg protocol_error_reg;
    logic[80-1:0] input_entry_comb;
    logic[$clog2(BANK_DEPTH)-1:0] bank_write_addr_comb;
    logic bank_write_0_comb;
    logic[$clog2(BANK_DEPTH)-1:0] bank_read_addr_0_comb;
    logic bank_write_1_comb;
    logic[$clog2(BANK_DEPTH)-1:0] bank_read_addr_1_comb;
    logic ready_comb;
;
    logic[2-1:0] window_valid_comb;
;
    logic[WINDOW_WORDS*LANE_WIDTH-1:0] window_data_comb;
;
    logic[WINDOW_WORDS*LANE_BYTES-1:0] window_keep_comb;
;
    logic[2-1:0] window_sop_comb;
;
    logic[2-1:0] window_eop_comb;
;
    logic almost_full_comb;
;

    // members
    genvar __i;
    wire[$clog2(BANK_DEPTH)-1:0] banks__write_addr_in[2];
    wire banks__write_in[2];
    wire[ENTRY_BYTES*'h8-1:0] banks__write_data_in[2];
    wire[ENTRY_BYTES-1:0] banks__write_mask_in[2];
    wire[$clog2(BANK_DEPTH)-1:0] banks__read_addr_in[2];
    wire banks__read_in[2];
    wire[ENTRY_BYTES*'h8-1:0] banks__read_data_out[2];
    generate
    for (__i=0; __i < 2; __i = __i + 1) begin
        SmartNicMemory #(
        ENTRY_BYTES
,       BANK_DEPTH
,       0
,       1
        ) banks (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .write_addr_in(banks__write_addr_in[__i])
        ,           .write_in(banks__write_in[__i])
        ,           .write_data_in(banks__write_data_in[__i])
        ,           .write_mask_in(banks__write_mask_in[__i])
        ,           .read_addr_in(banks__read_addr_in[__i])
        ,           .read_in(banks__read_in[__i])
        ,           .read_data_out(banks__read_data_out[__i])
        );
    end
    endgenerate

    // tmp variables
    logic[POINTER_BITS-1:0] head_reg_tmp;
    logic[POINTER_BITS-1:0] tail_reg_tmp;
    logic[COUNT_BITS-1:0] total_count_reg_tmp;
    logic[COUNT_BITS-1:0] committed_count_reg_tmp;
    logic[COUNT_BITS-1:0] pending_count_reg_tmp;
    logic in_packet_reg_tmp;
    logic protocol_error_reg_tmp;


    always_comb begin : input_entry_comb_func  // input_entry_comb_func
        input_entry_comb = 'h0;
        input_entry_comb['h0 +:LANE_WIDTH - 'h1 - 'h0 + 1] = data_in;
        input_entry_comb[KEEP_OFFSET +:(KEEP_OFFSET + LANE_BYTES) - 'h1 - KEEP_OFFSET + 1] = keep_in;
        input_entry_comb[SOP_OFFSET] = sop_in;
        input_entry_comb[EOP_OFFSET] = eop_in;
    end

    function logic[31:0] bank_read_row (input logic[63:0] bank);
        logic[31:0] head;
        logic[31:0] pop;
        logic[31:0] head_bank;
        head = unsigned'(32'(head_reg));
        pop = unsigned'(32'(read_count_in));
        if (pop<=WINDOW_WORDS && pop<=unsigned'(32'(committed_count_reg))) begin
            head=((head + pop)) & ((FIFO_WORDS - 'h1));
        end
        head_bank = head & ((WINDOW_WORDS - 'h1));
        return ((((head >>> 'h1)) + (((bank < head_bank)) ? ('h1) : ('h0)))) & ((BANK_DEPTH - 'h1));
    endfunction

    always_comb begin : bank_write_addr_comb_func  // bank_write_addr_comb_func
        bank_write_addr_comb = unsigned'(32'(tail_reg)) >>> 'h1;
    end

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

    always_comb begin : bank_write_0_comb_func  // bank_write_0_comb_func
        bank_write_0_comb=(valid_in && ready_comb) && ((((unsigned'(32'(tail_reg)) & ((WINDOW_WORDS - 'h1)))) == 'h0));
    end

    always_comb begin : bank_read_addr_0_comb_func  // bank_read_addr_0_comb_func
        bank_read_addr_0_comb = bank_read_row('h0);
    end

    always_comb begin : bank_write_1_comb_func  // bank_write_1_comb_func
        bank_write_1_comb=(valid_in && ready_comb) && ((((unsigned'(32'(tail_reg)) & ((WINDOW_WORDS - 'h1)))) == 'h1));
    end

    always_comb begin : bank_read_addr_1_comb_func  // bank_read_addr_1_comb_func
        bank_read_addr_1_comb = bank_read_row('h1);
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
        logic[80-1:0] entry;
        window_data_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            entry = banks__read_data_out[bank];
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
        logic[80-1:0] entry;
        window_keep_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            entry = banks__read_data_out[bank];
            for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                window_keep_comb[(slot*LANE_BYTES) + _byte] = entry[KEEP_OFFSET + _byte];
            end
        end
    end

    always_comb begin : window_sop_comb_func  // window_sop_comb_func
        logic[63:0] slot;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[80-1:0] entry;
        window_sop_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            entry = banks__read_data_out[bank];
            window_sop_comb[slot] = entry[SOP_OFFSET];
        end
    end

    always_comb begin : window_eop_comb_func  // window_eop_comb_func
        logic[63:0] slot;
        logic[31:0] logical;
        logic[31:0] bank;
        logic[80-1:0] entry;
        window_eop_comb = 'h0;
        for (slot='h0;slot < WINDOW_WORDS;slot=slot+1) begin
            logical=((unsigned'(32'(head_reg)) + slot)) & ((FIFO_WORDS - 'h1));
            bank=logical & ((WINDOW_WORDS - 'h1));
            entry = banks__read_data_out[bank];
            window_eop_comb[slot] = entry[EOP_OFFSET];
        end
    end

    always_comb begin : almost_full_comb_func  // almost_full_comb_func
        almost_full_comb=total_count_reg>=FIFO_WORDS - WINDOW_WORDS;
    end

    generate  // _assign
        assign banks__write_addr_in['h0] = bank_write_addr_comb;
        assign banks__write_in['h0] = bank_write_0_comb;
        assign banks__write_data_in['h0] = input_entry_comb;
        assign banks__write_mask_in['h0] = ~('h0);
        assign banks__read_addr_in['h0] = bank_read_addr_0_comb;
        assign banks__read_in['h0] = 1;
        assign banks__write_addr_in['h1] = bank_write_addr_comb;
        assign banks__write_in['h1] = bank_write_1_comb;
        assign banks__write_data_in['h1] = input_entry_comb;
        assign banks__write_mask_in['h1] = ~('h0);
        assign banks__read_addr_in['h1] = bank_read_addr_1_comb;
        assign banks__read_in['h1] = 1;
        assign ready_out = ready_comb;
        assign data_out = window_data_comb;
        assign keep_out = window_keep_comb;
        assign sop_out = window_sop_comb;
        assign eop_out = window_eop_comb;
        assign valid_out = window_valid_comb;
        assign almost_full_out = almost_full_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[63:0] _byte;
        logic[63:0] bank_index;
        logic[31:0] pop;
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] total;
        logic[31:0] committed;
        logic[31:0] pending;
        logic in_packet;
        logic seen_zero;
        logic malformed_keep;
        logic incomplete_keep;
        for (bank_index='h0;bank_index < WINDOW_WORDS;bank_index=bank_index+1) begin
        end
        if (reset) begin
            head_reg_tmp = '0;
            tail_reg_tmp = '0;
            total_count_reg_tmp = '0;
            committed_count_reg_tmp = '0;
            pending_count_reg_tmp = '0;
            in_packet_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            disable _work_net_clk;
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
