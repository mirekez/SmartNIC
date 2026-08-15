`default_nettype none

import Predef_pkg::*;


module SmartNicRAM #(
    parameter WIDTH = 320
,   parameter DEPTH = 4096
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire[$clog2(DEPTH)-1:0] addr_in
,   input wire[WIDTH-1:0] data_in
,   input wire wr_in
,   input wire rd_in
,   output wire[WIDTH-1:0] q_out
,   input wire signed[31:0] id_in
);


    // regs and combs
    reg[WIDTH-1:0] q_out_reg;
    reg[((WIDTH + 'h7))/'h8-1:0][8-1:0] buffer[DEPTH];

    // members

    // tmp variables
    logic[WIDTH-1:0] q_out_reg_tmp;


    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        if (reset) begin
            q_out_reg_tmp = '0;
            disable _work_net_clk;
        end
        if (wr_in) begin
            buffer[addr_in] <= data_in;
        end
        if (rd_in) begin
            q_out_reg_tmp = buffer[addr_in];
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        q_out_reg_tmp = q_out_reg;

        _work_net_clk(reset);

        q_out_reg <= q_out_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end

    assign q_out = q_out_reg;


endmodule
