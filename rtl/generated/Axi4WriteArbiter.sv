`default_nettype none

import Predef_pkg::*;
import Axi4WriteArbiterState_pkg::*;


module Axi4WriteArbiter #(
    parameter ADDR_WIDTH = 31
,   parameter ID_WIDTH = 4
,   parameter DATA_WIDTH = 256
 )
 (
    input wire clk
,   input wire l2_clock
,   input wire reset
,   input wire cpu__awvalid_in
,   output wire cpu__awready_out
,   input wire[31-1:0] cpu__awaddr_in
,   input wire[4-1:0] cpu__awid_in
,   input wire cpu__wvalid_in
,   output wire cpu__wready_out
,   input wire[256-1:0] cpu__wdata_in
,   input wire[256/'h8-1:0] cpu__wstrb_in
,   input wire cpu__wlast_in
,   output wire cpu__bvalid_out
,   input wire cpu__bready_in
,   output wire[4-1:0] cpu__bid_out
,   input wire cpu__arvalid_in
,   output wire cpu__arready_out
,   input wire[31-1:0] cpu__araddr_in
,   input wire[4-1:0] cpu__arid_in
,   output wire cpu__rvalid_out
,   input wire cpu__rready_in
,   output wire[256-1:0] cpu__rdata_out
,   output wire cpu__rlast_out
,   output wire[4-1:0] cpu__rid_out
,   input wire packet__awvalid_in
,   output wire packet__awready_out
,   input wire[31-1:0] packet__awaddr_in
,   input wire[4-1:0] packet__awid_in
,   input wire packet__wvalid_in
,   output wire packet__wready_out
,   input wire[256-1:0] packet__wdata_in
,   input wire[256/'h8-1:0] packet__wstrb_in
,   input wire packet__wlast_in
,   output wire packet__bvalid_out
,   input wire packet__bready_in
,   output wire[4-1:0] packet__bid_out
,   input wire packet__arvalid_in
,   output wire packet__arready_out
,   input wire[31-1:0] packet__araddr_in
,   input wire[4-1:0] packet__arid_in
,   output wire packet__rvalid_out
,   input wire packet__rready_in
,   output wire[256-1:0] packet__rdata_out
,   output wire packet__rlast_out
,   output wire[4-1:0] packet__rid_out
,   output wire memory__awvalid_out
,   input wire memory__awready_in
,   output wire[31-1:0] memory__awaddr_out
,   output wire[4-1:0] memory__awid_out
,   output wire memory__wvalid_out
,   input wire memory__wready_in
,   output wire[256-1:0] memory__wdata_out
,   output wire[256/'h8-1:0] memory__wstrb_out
,   output wire memory__wlast_out
,   input wire memory__bvalid_in
,   output wire memory__bready_out
,   input wire[4-1:0] memory__bid_in
,   output wire memory__arvalid_out
,   input wire memory__arready_in
,   output wire[31-1:0] memory__araddr_out
,   output wire[4-1:0] memory__arid_out
,   input wire memory__rvalid_in
,   output wire memory__rready_out
,   input wire[256-1:0] memory__rdata_in
,   input wire memory__rlast_in
,   input wire[4-1:0] memory__rid_in
);


    // regs and combs
    reg[2-1:0] state_reg;
    reg packet_owner_reg;
    logic packet_aw_selected_comb;
;
    logic cpu_aw_selected_comb;
;
    logic cpu_ar_selected_comb;
;
    logic packet_ar_selected_comb;
;

    // members

    // tmp variables
    logic[2-1:0] state_reg_tmp;
    logic packet_owner_reg_tmp;


    always_comb begin : packet_aw_selected_comb_func  // packet_aw_selected_comb_func
        packet_aw_selected_comb=((((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE) && !cpu__arvalid_in) && !packet__arvalid_in) && !cpu__awvalid_in) && packet__awvalid_in;
    end

    always_comb begin : cpu_aw_selected_comb_func  // cpu_aw_selected_comb_func
        cpu_aw_selected_comb=(((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE) && !cpu__arvalid_in) && !packet__arvalid_in) && cpu__awvalid_in;
    end

    always_comb begin : cpu_ar_selected_comb_func  // cpu_ar_selected_comb_func
        cpu_ar_selected_comb=(unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE) && cpu__arvalid_in;
    end

    always_comb begin : packet_ar_selected_comb_func  // packet_ar_selected_comb_func
        packet_ar_selected_comb=((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE) && !cpu__arvalid_in) && packet__arvalid_in;
    end

    generate  // _assign
        assign memory__awvalid_out = packet_aw_selected_comb || cpu_aw_selected_comb;
        assign memory__awaddr_out = (packet_aw_selected_comb) ? (unsigned'(ADDR_WIDTH'(unsigned'(ADDR_WIDTH'(packet__awaddr_in))))) : (unsigned'(ADDR_WIDTH'(unsigned'(ADDR_WIDTH'(cpu__awaddr_in)))));
        assign memory__awid_out = (packet_aw_selected_comb) ? (unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(packet__awid_in))))) : (unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(cpu__awid_in)))));
        assign memory__wvalid_out = ((packet_aw_selected_comb && packet__wvalid_in)) || (((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA) && ((packet_owner_reg) ? (packet__wvalid_in) : (cpu__wvalid_in))));
        assign memory__wdata_out = (packet_aw_selected_comb || packet_owner_reg) ? (packet__wdata_in) : (cpu__wdata_in);
        assign memory__wstrb_out = (packet_aw_selected_comb || packet_owner_reg) ? (packet__wstrb_in) : (cpu__wstrb_in);
        assign memory__wlast_out = (packet_aw_selected_comb || packet_owner_reg) ? (packet__wlast_in) : (cpu__wlast_in);
        assign memory__bready_out = (unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE) && ((packet_owner_reg) ? (packet__bready_in) : (cpu__bready_in));
        assign memory__arvalid_out = cpu_ar_selected_comb || packet_ar_selected_comb;
        assign memory__araddr_out = (packet_ar_selected_comb) ? (unsigned'(ADDR_WIDTH'(unsigned'(ADDR_WIDTH'(packet__araddr_in))))) : (unsigned'(ADDR_WIDTH'(unsigned'(ADDR_WIDTH'(cpu__araddr_in)))));
        assign memory__arid_out = (packet_ar_selected_comb) ? (unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(packet__arid_in))))) : (unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(cpu__arid_in)))));
        assign memory__rready_out = (unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA) && ((packet_owner_reg) ? (packet__rready_in) : (cpu__rready_in));
        assign packet__awready_out = packet_aw_selected_comb && memory__awready_in;
        assign cpu__awready_out = cpu_aw_selected_comb && memory__awready_in;
        assign packet__wready_out = ((packet_aw_selected_comb || (((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA) && packet_owner_reg)))) && memory__wready_in;
        assign cpu__wready_out = ((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA) && !packet_owner_reg) && memory__wready_in;
        assign packet__bvalid_out = ((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE) && packet_owner_reg) && memory__bvalid_in;
        assign cpu__bvalid_out = ((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE) && !packet_owner_reg) && memory__bvalid_in;
        assign packet__bid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(memory__bid_in))));
        assign cpu__bid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(memory__bid_in))));
        assign packet__arready_out = packet_ar_selected_comb && memory__arready_in;
        assign cpu__arready_out = cpu_ar_selected_comb && memory__arready_in;
        assign packet__rvalid_out = ((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA) && packet_owner_reg) && memory__rvalid_in;
        assign packet__rdata_out = memory__rdata_in;
        assign packet__rlast_out = memory__rlast_in;
        assign packet__rid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(memory__rid_in))));
        assign cpu__rvalid_out = ((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA) && !packet_owner_reg) && memory__rvalid_in;
        assign cpu__rdata_out = memory__rdata_in;
        assign cpu__rlast_out = memory__rlast_in;
        assign cpu__rid_out = unsigned'(ID_WIDTH'(unsigned'(ID_WIDTH'(memory__rid_in))));
    endgenerate

    task _work (input logic reset);
    begin: _work
        if (unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE) begin
            if (cpu__arvalid_in && cpu__arready_out) begin
                packet_owner_reg_tmp = unsigned'(1'(0));
                state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA;
            end
            else begin
                if (packet__arvalid_in && packet__arready_out) begin
                    packet_owner_reg_tmp = unsigned'(1'(1));
                    state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA;
                end
                else begin
                    if (cpu__awvalid_in && cpu__awready_out) begin
                        packet_owner_reg_tmp = unsigned'(1'(0));
                        state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA;
                    end
                    else begin
                        if (packet__awvalid_in && packet__awready_out) begin
                            packet_owner_reg_tmp = unsigned'(1'(1));
                            state_reg_tmp = (packet__wvalid_in && packet__wready_out) ? (Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE) : (Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA);
                        end
                    end
                end
            end
        end
        else begin
            if (((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_DATA) && memory__wvalid_out) && memory__wready_in) begin
                state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE;
            end
            else begin
                if (((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_WRITE_RESPONSE) && memory__bvalid_in) && memory__bready_out) begin
                    state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE;
                end
                else begin
                    if ((((unsigned'(32'(state_reg)) == Axi4WriteArbiterState_pkg::AXI4_ARB_READ_DATA) && memory__rvalid_in) && memory__rready_out) && memory__rlast_in) begin
                        state_reg_tmp = Axi4WriteArbiterState_pkg::AXI4_ARB_IDLE;
                    end
                end
            end
        end
        if (reset) begin
            state_reg_tmp = '0;
            packet_owner_reg_tmp = '0;
        end
    end
    endtask

    task _work_l2_clock (input logic reset);
    begin: _work_l2_clock
    end
    endtask

    always_ff @(posedge clk) begin
        state_reg_tmp = state_reg;
        packet_owner_reg_tmp = packet_owner_reg;

        _work(reset);

        state_reg <= state_reg_tmp;
        packet_owner_reg <= packet_owner_reg_tmp;
    end

    always_ff @(posedge l2_clock) begin

        _work_l2_clock(reset);

    end


endmodule
