`default_nettype none

import Predef_pkg::*;


module AsyncFifoL2ToSystem #(
    parameter WIDTH = 290
,   parameter DEPTH = 'h10
 )
 (
    input wire l2_clock
,   input wire system_clock
,   input wire reset
,   input wire write_valid_in
,   input wire[WIDTH-1:0] write_data_in
,   output wire write_ready_out
,   input wire read_ready_in
,   output wire read_valid_out
,   output wire[WIDTH-1:0] read_data_out
);
    parameter  ADDR_BITS = $clog2(DEPTH);
    parameter  PTR_BITS = ADDR_BITS + 'h1;


    // regs and combs
    reg[1-1:0][WIDTH-1:0] data_mem[DEPTH];
    reg[PTR_BITS-1:0] write_bin_reg;
    reg[PTR_BITS-1:0] write_gray_reg;
    reg[PTR_BITS-1:0] read_gray_write1_reg;
    reg[PTR_BITS-1:0] read_gray_write2_reg;
    reg[PTR_BITS-1:0] read_bin_reg;
    reg[PTR_BITS-1:0] read_gray_reg;
    reg[PTR_BITS-1:0] write_gray_read1_reg;
    reg[PTR_BITS-1:0] write_gray_read2_reg;
    logic write_ready_comb;
    logic read_valid_comb;
    logic[WIDTH-1:0] read_data_comb;

    // members

    // tmp variables
    logic[PTR_BITS-1:0] write_bin_reg_tmp;
    logic[PTR_BITS-1:0] write_gray_reg_tmp;
    logic[PTR_BITS-1:0] read_gray_write1_reg_tmp;
    logic[PTR_BITS-1:0] read_gray_write2_reg_tmp;
    logic[PTR_BITS-1:0] read_bin_reg_tmp;
    logic[PTR_BITS-1:0] read_gray_reg_tmp;
    logic[PTR_BITS-1:0] write_gray_read1_reg_tmp;
    logic[PTR_BITS-1:0] write_gray_read2_reg_tmp;


    always_comb begin : write_ready_comb_func  // write_ready_comb_func
        logic[5-1:0] full_gray;
        full_gray = read_gray_write2_reg ^ unsigned'(PTR_BITS'(unsigned'(PTR_BITS'(((('h1 <<< ADDR_BITS)) | (('h1 <<< ((ADDR_BITS - 'h1)))))))));
        write_ready_comb=write_gray_reg != full_gray;
    end

    always_comb begin : read_valid_comb_func  // read_valid_comb_func
        read_valid_comb=read_gray_reg != write_gray_read2_reg;
    end

    task work_write (input logic reset);
    begin: work_write
        logic[5-1:0] next;
        read_gray_write1_reg_tmp = read_gray_reg;
        read_gray_write2_reg_tmp = read_gray_write1_reg;
        if (write_valid_in && write_ready_comb) begin
            data_mem[unsigned'(32'(write_bin_reg)) & ((DEPTH - 'h1))] <= write_data_in;
            next = write_bin_reg + 'h1;
            write_bin_reg_tmp = next;
            write_gray_reg_tmp = next ^ ((next >>> 'h1));
        end
        if (reset) begin
            write_bin_reg_tmp = '0;
            write_gray_reg_tmp = '0;
            read_gray_write1_reg_tmp = '0;
            read_gray_write2_reg_tmp = '0;
        end
    end
    endtask

    task work_read (input logic reset);
    begin: work_read
        logic[5-1:0] next;
        write_gray_read1_reg_tmp = write_gray_reg;
        write_gray_read2_reg_tmp = write_gray_read1_reg;
        if (read_ready_in && read_valid_comb) begin
            next = read_bin_reg + 'h1;
            read_bin_reg_tmp = next;
            read_gray_reg_tmp = next ^ ((next >>> 'h1));
        end
        if (reset) begin
            read_bin_reg_tmp = '0;
            read_gray_reg_tmp = '0;
            write_gray_read1_reg_tmp = '0;
            write_gray_read2_reg_tmp = '0;
        end
    end
    endtask

    generate  // _assign
    endgenerate

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
        work_write(reset);
    end
    endtask

    task _work_system_clock (input logic reset);
    begin: _work_system_clock
        work_read(reset);
    end
    endtask

    always_comb begin : read_data_comb_func  // read_data_comb_func
        read_data_comb=data_mem[unsigned'(32'(read_bin_reg)) & ((DEPTH - 'h1))];
    end

    always_ff @(posedge l2_clock) begin
        write_bin_reg_tmp = write_bin_reg;
        write_gray_reg_tmp = write_gray_reg;
        read_gray_write1_reg_tmp = read_gray_write1_reg;
        read_gray_write2_reg_tmp = read_gray_write2_reg;

        _work_l2_clock(reset);

        write_bin_reg <= write_bin_reg_tmp;
        write_gray_reg <= write_gray_reg_tmp;
        read_gray_write1_reg <= read_gray_write1_reg_tmp;
        read_gray_write2_reg <= read_gray_write2_reg_tmp;
    end

    always_ff @(posedge system_clock) begin
        read_bin_reg_tmp = read_bin_reg;
        read_gray_reg_tmp = read_gray_reg;
        write_gray_read1_reg_tmp = write_gray_read1_reg;
        write_gray_read2_reg_tmp = write_gray_read2_reg;

        _work_system_clock(reset);

        read_bin_reg <= read_bin_reg_tmp;
        read_gray_reg <= read_gray_reg_tmp;
        write_gray_read1_reg <= write_gray_read1_reg_tmp;
        write_gray_read2_reg <= write_gray_read2_reg_tmp;
    end

    assign write_ready_out = write_ready_comb;

    assign read_valid_out = read_valid_comb;

    assign read_data_out = read_data_comb;


endmodule
