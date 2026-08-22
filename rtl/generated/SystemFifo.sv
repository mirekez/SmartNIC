`default_nettype none

import Predef_pkg::*;


module SystemFifo #(
    parameter FIFO_WIDTH_BYTES = 160
,   parameter FIFO_DEPTH = 64
,   parameter SHOWAHEAD = 1
,   parameter OUTPUT_REG = 0
 )
 (
    input wire l2_clock
,   input wire system_clock
,   input wire reset
,   input wire write_in
,   input wire[FIFO_WIDTH_BYTES*'h8-1:0] write_data_in
,   input wire read_in
,   output wire[FIFO_WIDTH_BYTES*'h8-1:0] read_data_out
,   output wire empty_out
,   output wire full_out
,   input wire clear_in
,   output wire afull_out
);


    // regs and combs
    reg[$clog2(FIFO_DEPTH)-1:0] wp_reg;
    reg[$clog2(FIFO_DEPTH)-1:0] rp_reg;
    reg full_reg;
    reg afull_reg;
    reg read_valid_reg;
    logic full_comb;
    logic empty_comb;
    logic mem_read_comb;
    logic mem_write_comb;
    logic[FIFO_WIDTH_BYTES*'h8-1:0] read_data_comb;

    // members
    wire[$clog2(FIFO_DEPTH)-1:0] mem__write_addr_in;
    wire mem__write_in;
    wire[FIFO_WIDTH_BYTES*'h8-1:0] mem__write_data_in;
    wire[FIFO_WIDTH_BYTES-1:0] mem__write_mask_in;
    wire[$clog2(FIFO_DEPTH)-1:0] mem__read_addr_in;
    wire mem__read_in;
    wire[FIFO_WIDTH_BYTES*'h8-1:0] mem__read_data_out;
    SystemMemory #(
        FIFO_WIDTH_BYTES
,       FIFO_DEPTH
,       (OUTPUT_REG) ? (0) : (SHOWAHEAD)
,       1
    ) mem (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_addr_in(mem__write_addr_in)
,       .write_in(mem__write_in)
,       .write_data_in(mem__write_data_in)
,       .write_mask_in(mem__write_mask_in)
,       .read_addr_in(mem__read_addr_in)
,       .read_in(mem__read_in)
,       .read_data_out(mem__read_data_out)
    );

    // tmp variables
    logic[$clog2(FIFO_DEPTH)-1:0] wp_reg_tmp;
    logic[$clog2(FIFO_DEPTH)-1:0] rp_reg_tmp;
    logic full_reg_tmp;
    logic afull_reg_tmp;
    logic read_valid_reg_tmp;


    always_comb begin : full_comb_func  // full_comb_func
        if (OUTPUT_REG) begin
            full_comb=((wp_reg == rp_reg) && full_reg) && read_valid_reg;
        end
        else begin
            full_comb=(wp_reg == rp_reg) && full_reg;
        end
    end

    always_comb begin : empty_comb_func  // empty_comb_func
        if (OUTPUT_REG) begin
            empty_comb=!read_valid_reg;
        end
        else begin
            empty_comb=(wp_reg == rp_reg) && !full_reg;
        end
    end

    always_comb begin : read_data_comb_func  // read_data_comb_func
        read_data_comb = mem__read_data_out;
    end

    always_comb begin : mem_read_comb_func  // mem_read_comb_func
        if (OUTPUT_REG) begin
            logic mem_empty;
            logic output_needs_word;
            mem_empty=(wp_reg == rp_reg) && !full_reg;
            output_needs_word=!read_valid_reg || read_in;
            mem_read_comb=output_needs_word && !mem_empty;
        end
        else begin
            mem_read_comb=read_in;
        end
    end

    always_comb begin : mem_write_comb_func  // mem_write_comb_func
        if (OUTPUT_REG) begin
            logic mem_full;
            mem_full=(wp_reg == rp_reg) && full_reg;
            mem_write_comb=write_in && ((!mem_full || mem_read_comb));
        end
        else begin
            mem_write_comb=write_in;
        end
    end

    generate  // _assign
        assign mem__write_data_in = write_data_in;
        assign mem__write_in = mem_write_comb;
        assign mem__write_mask_in = ~('h0);
        assign mem__write_addr_in = wp_reg;
        assign mem__read_in = mem_read_comb;
        assign mem__read_addr_in = rp_reg;
        assign read_data_out = read_data_comb;
        assign empty_out = empty_comb;
        assign full_out = full_comb;
        assign afull_out = afull_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic mem_read;
        logic mem_write;
        logic output_read;
        logic[31:0] count;
        if (reset) begin
            wp_reg_tmp = '0;
            rp_reg_tmp = '0;
            full_reg_tmp = '0;
            afull_reg_tmp = '0;
            read_valid_reg_tmp = '0;
            disable _work;
        end
        if (OUTPUT_REG) begin
            mem_read=mem_read_comb;
            mem_write=mem_write_comb;
            output_read=read_in && read_valid_reg;
            if (mem_write) begin
                wp_reg_tmp = wp_reg + 'h1;
            end
            if (mem_read) begin
                rp_reg_tmp = rp_reg + 'h1;
                read_valid_reg_tmp = unsigned'(1'h1);
            end
            else begin
                if (output_read) begin
                    read_valid_reg_tmp = unsigned'(1'h0);
                end
            end
            if ((mem_write && !mem_read) && ((wp_reg + 'h1) == rp_reg)) begin
                full_reg_tmp = unsigned'(1'h1);
            end
            if (mem_read && !mem_write) begin
                full_reg_tmp = unsigned'(1'h0);
            end
            count=(full_reg) ? (FIFO_DEPTH) : (((wp_reg>=unsigned'(32'(rp_reg))) ? (unsigned'(32'(wp_reg)) - unsigned'(32'(rp_reg))) : ((FIFO_DEPTH - unsigned'(32'(rp_reg))) + unsigned'(32'(wp_reg)))));
            afull_reg_tmp = unsigned'(1'(count + ((read_valid_reg) ? ('h1) : ('h0))>=FIFO_DEPTH/'h2));
        end
        else begin
            mem_read=read_in && !empty_comb;
            mem_write=write_in && ((!full_comb || mem_read));
            if (mem_write) begin
                wp_reg_tmp = wp_reg + 'h1;
            end
            if (mem_read) begin
                rp_reg_tmp = rp_reg + 'h1;
            end
            if ((mem_write && !mem_read) && ((wp_reg + 'h1) == rp_reg)) begin
                full_reg_tmp = unsigned'(1'h1);
            end
            if (mem_read && !mem_write) begin
                full_reg_tmp = unsigned'(1'h0);
            end
            count=(full_reg) ? (FIFO_DEPTH) : (((wp_reg>=unsigned'(32'(rp_reg))) ? (unsigned'(32'(wp_reg)) - unsigned'(32'(rp_reg))) : ((FIFO_DEPTH - unsigned'(32'(rp_reg))) + unsigned'(32'(wp_reg)))));
            afull_reg_tmp = unsigned'(1'(count>=FIFO_DEPTH/'h2));
        end
        if (clear_in) begin
            wp_reg_tmp = 'h0;
            rp_reg_tmp = 'h0;
            full_reg_tmp = unsigned'(1'h0);
            read_valid_reg_tmp = unsigned'(1'h0);
        end
    end
    endtask

    task _work_system_clock (input logic reset);
    begin: _work_system_clock
    end
    endtask

    always_ff @(posedge l2_clock) begin
        wp_reg_tmp = wp_reg;
        rp_reg_tmp = rp_reg;
        full_reg_tmp = full_reg;
        afull_reg_tmp = afull_reg;
        read_valid_reg_tmp = read_valid_reg;

        _work(reset);

        wp_reg <= wp_reg_tmp;
        rp_reg <= rp_reg_tmp;
        full_reg <= full_reg_tmp;
        afull_reg <= afull_reg_tmp;
        read_valid_reg <= read_valid_reg_tmp;
    end

    always_ff @(posedge system_clock) begin

        _work_system_clock(reset);

    end


endmodule
