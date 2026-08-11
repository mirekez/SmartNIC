`default_nettype none

import Predef_pkg::*;


module AsyncPacketStreamNetToL2 #(
    parameter SRC_WIDTH = 320
,   parameter DST_WIDTH = 256
,   parameter FIFO_DEPTH = 'h10
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
    parameter  CHUNK_BYTES = 64'h40;
    parameter  CHUNK_BITS = 64'h200;
    parameter  ENTRY_BITS = 64'h20A;
    parameter  BUFFER_BYTES = 64'h80;
    parameter  BUFFER_BITS = 64'h400;


    // regs and combs
    reg[1024-1:0] source_data_reg;
    reg[8-1:0] source_count_reg;
    reg source_sop_reg;
    reg source_eop_reg;
    reg[1024-1:0] output_data_reg;
    reg[8-1:0] output_count_reg;
    reg output_sop_reg;
    reg output_eop_reg;
    logic fifo_write_valid_comb;
    logic[522-1:0] fifo_write_data_comb;
    logic source_ready_comb;
    logic fifo_read_ready_comb;
    logic output_valid_comb;
    logic[DST_WIDTH-1:0] output_data_comb;
    logic[DST_BYTES-1:0] output_keep_comb;
    logic output_eop_comb;

    // members
    wire fifo__write_valid_in;
    wire[ENTRY_BITS-1:0] fifo__write_data_in;
    wire fifo__write_ready_out;
    wire fifo__read_ready_in;
    wire fifo__read_valid_out;
    wire[ENTRY_BITS-1:0] fifo__read_data_out;
    AsyncFifoNetToL2 #(
        ENTRY_BITS
,       FIFO_DEPTH
    ) fifo (
        .net_clk(net_clk)
,       .l2_clk(l2_clk)
,       .reset(reset)
,       .write_valid_in(fifo__write_valid_in)
,       .write_data_in(fifo__write_data_in)
,       .write_ready_out(fifo__write_ready_out)
,       .read_ready_in(fifo__read_ready_in)
,       .read_valid_out(fifo__read_valid_out)
,       .read_data_out(fifo__read_data_out)
    );

    // tmp variables
    logic[1024-1:0] source_data_reg_tmp;
    logic[8-1:0] source_count_reg_tmp;
    logic source_sop_reg_tmp;
    logic source_eop_reg_tmp;
    logic[1024-1:0] output_data_reg_tmp;
    logic[8-1:0] output_count_reg_tmp;
    logic output_sop_reg_tmp;
    logic output_eop_reg_tmp;


    always_comb begin : fifo_write_valid_comb_func  // fifo_write_valid_comb_func
        fifo_write_valid_comb=source_count_reg>=CHUNK_BYTES || ((source_eop_reg && (unsigned'(32'(source_count_reg)) != 'h0)));
    end

    always_comb begin : fifo_write_data_comb_func  // fifo_write_data_comb_func
        logic[31:0] _byte;
        logic[31:0] count;
        fifo_write_data_comb = 'h0;
        count=unsigned'(32'(source_count_reg));
        if (count > CHUNK_BYTES) begin
            count=CHUNK_BYTES;
        end
        for (_byte='h0;_byte < CHUNK_BYTES;_byte=_byte+1) begin
            if (_byte < count) begin
                fifo_write_data_comb[_byte*'h8 +:8] = source_data_reg[_byte*'h8 +:8];
            end
        end
        fifo_write_data_comb[CHUNK_BITS +:CHUNK_BITS + 'h6 - CHUNK_BITS + 1] = count;
        fifo_write_data_comb[CHUNK_BITS + 'h7] = source_sop_reg;
        fifo_write_data_comb[CHUNK_BITS + 'h8] = source_eop_reg && source_count_reg<=CHUNK_BYTES;
    end

    always_comb begin : source_ready_comb_func  // source_ready_comb_func
        logic[31:0] remaining;
        logic emit;
        logic eop_remaining;
        remaining=unsigned'(32'(source_count_reg));
        emit=fifo_write_valid_comb && fifo__write_ready_out;
        eop_remaining=source_eop_reg;
        if (emit) begin
            if (remaining > CHUNK_BYTES) begin
                remaining-=CHUNK_BYTES;
            end
            else begin
                remaining='h0;
            end
            if (source_count_reg<=CHUNK_BYTES) begin
                eop_remaining=0;
            end
        end
        source_ready_comb=!eop_remaining && (remaining + SRC_BYTES)<=BUFFER_BYTES;
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        output_valid_comb=output_count_reg>=DST_BYTES || ((output_eop_reg && (unsigned'(32'(output_count_reg)) != 'h0)));
    end

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[31:0] _byte;
        output_data_comb = 'h0;
        for (_byte='h0;_byte < DST_BYTES;_byte=_byte+1) begin
            if (_byte < unsigned'(32'(output_count_reg))) begin
                output_data_comb[_byte*'h8 +:8] = output_data_reg[_byte*'h8 +:8];
            end
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[31:0] _byte;
        output_keep_comb = 'h0;
        for (_byte='h0;_byte < DST_BYTES;_byte=_byte+1) begin
            output_keep_comb[_byte] = _byte < unsigned'(32'(output_count_reg));
        end
    end

    always_comb begin : output_eop_comb_func  // output_eop_comb_func
        output_eop_comb=output_eop_reg && output_count_reg<=DST_BYTES;
    end

    always_comb begin : fifo_read_ready_comb_func  // fifo_read_ready_comb_func
        logic[31:0] remaining;
        logic output_fire;
        logic eop_remaining;
        remaining=unsigned'(32'(output_count_reg));
        output_fire=output_valid_comb && ready_in;
        eop_remaining=output_eop_reg;
        if (output_fire) begin
            if (remaining > DST_BYTES) begin
                remaining-=DST_BYTES;
            end
            else begin
                remaining='h0;
            end
            if (output_count_reg<=DST_BYTES) begin
                eop_remaining=0;
            end
        end
        fifo_read_ready_comb=!eop_remaining && (remaining + CHUNK_BYTES)<=BUFFER_BYTES;
    end

    task work_source (input logic reset);
    begin: work_source
        logic[1024-1:0] data;
        logic[31:0] count;
        logic[31:0] _byte;
        logic[31:0] shifted;
        logic sop;
        logic eop;
        logic emit;
        data = source_data_reg;
        count=unsigned'(32'(source_count_reg));
        sop=source_sop_reg;
        eop=source_eop_reg;
        emit=fifo_write_valid_comb && fifo__write_ready_out;
        if (emit) begin
            shifted=(count > CHUNK_BYTES) ? (count - CHUNK_BYTES) : ('h0);
            for (_byte='h0;_byte < BUFFER_BYTES;_byte=_byte+1) begin
                if (_byte < shifted) begin
                    data[_byte*'h8 +:8] = data[((_byte + CHUNK_BYTES))*'h8 +:8];
                end
                else begin
                    data[_byte*'h8 +:8] = 'h0;
                end
            end
            count=shifted;
            sop=0;
            if (shifted == 'h0) begin
                eop=0;
            end
        end
        if (valid_in && source_ready_comb) begin
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
        source_data_reg_tmp = data;
        source_count_reg_tmp = count;
        source_sop_reg_tmp = unsigned'(1'(sop));
        source_eop_reg_tmp = unsigned'(1'(eop));
        if (reset) begin
            source_data_reg_tmp = '0;
            source_count_reg_tmp = '0;
            source_sop_reg_tmp = '0;
            source_eop_reg_tmp = '0;
        end
    end
    endtask

    task work_output (input logic reset);
    begin: work_output
        logic[1024-1:0] data;
        logic[522-1:0] entry;
        logic[31:0] count;
        logic[31:0] remove;
        logic[31:0] chunk_count;
        logic[31:0] _byte;
        logic sop;
        logic eop;
        data = output_data_reg;
        count=unsigned'(32'(output_count_reg));
        sop=output_sop_reg;
        eop=output_eop_reg;
        if (output_valid_comb && ready_in) begin
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
        if (fifo__read_valid_out && fifo_read_ready_comb) begin
            entry = fifo__read_data_out;
            chunk_count=unsigned'(32'(entry[CHUNK_BITS +:CHUNK_BITS + 'h6 - CHUNK_BITS + 1]));
            for (_byte='h0;_byte < CHUNK_BYTES;_byte=_byte+1) begin
                if (_byte < chunk_count) begin
                    data[((count + _byte))*'h8 +:8] = entry[_byte*'h8 +:8];
                end
            end
            if (entry[CHUNK_BITS + 'h7]) begin
                sop=1;
            end
            if (entry[CHUNK_BITS + 'h8]) begin
                eop=1;
            end
            count+=chunk_count;
        end
        output_data_reg_tmp = data;
        output_count_reg_tmp = count;
        output_sop_reg_tmp = unsigned'(1'(sop));
        output_eop_reg_tmp = unsigned'(1'(eop));
        if (reset) begin
            output_data_reg_tmp = '0;
            output_count_reg_tmp = '0;
            output_sop_reg_tmp = '0;
            output_eop_reg_tmp = '0;
        end
    end
    endtask

    generate  // _assign
        assign fifo__write_valid_in = fifo_write_valid_comb;
        assign fifo__write_data_in = fifo_write_data_comb;
        assign fifo__read_ready_in = fifo_read_ready_comb;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        work_source(reset);
    end
    endtask

    task _work_l2_clk (input logic reset);
    begin: _work_l2_clk
        work_output(reset);
    end
    endtask

    always_ff @(posedge net_clk) begin
        source_data_reg_tmp = source_data_reg;
        source_count_reg_tmp = source_count_reg;
        source_sop_reg_tmp = source_sop_reg;
        source_eop_reg_tmp = source_eop_reg;

        _work_net_clk(reset);

        source_data_reg <= source_data_reg_tmp;
        source_count_reg <= source_count_reg_tmp;
        source_sop_reg <= source_sop_reg_tmp;
        source_eop_reg <= source_eop_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin
        output_data_reg_tmp = output_data_reg;
        output_count_reg_tmp = output_count_reg;
        output_sop_reg_tmp = output_sop_reg;
        output_eop_reg_tmp = output_eop_reg;

        _work_l2_clk(reset);

        output_data_reg <= output_data_reg_tmp;
        output_count_reg <= output_count_reg_tmp;
        output_sop_reg <= output_sop_reg_tmp;
        output_eop_reg <= output_eop_reg_tmp;
    end

    assign ready_out = source_ready_comb;

    assign valid_out = output_valid_comb;

    assign data_out = output_data_comb;

    assign keep_out = output_keep_comb;

    assign sop_out = output_sop_reg;

    assign eop_out = output_eop_comb;


endmodule
