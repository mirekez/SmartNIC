`default_nettype none

// Two asynchronous read ports are implemented by replicated distributed RAM.
// This keeps packet-boundary lookup off the payload BRAM clock-to-out path
// without expanding 4096 individual flip-flops and their read muxes.
(* keep_hierarchy = "yes" *)
module TxEopMemory #(
    parameter integer DEPTH = 2048
) (
    input  wire                         net_clk,
    input  wire                         l2_clk,
    input  wire                         reset,
    input  wire [$clog2(DEPTH)-1:0]     write_addr_in,
    input  wire                         write_in,
    input  wire                         write_data_in,
    input  wire [$clog2(DEPTH)-1:0]     read_addr0_in,
    input  wire [$clog2(DEPTH)-1:0]     read_addr1_in,
    output wire                         read_data0_out,
    output wire                         read_data1_out
);
    (* ram_style = "distributed" *)
    reg memory0 [0:DEPTH-1];
    (* ram_style = "distributed" *)
    reg memory1 [0:DEPTH-1];

    always_ff @(posedge net_clk) begin
        if (write_in) begin
            memory0[write_addr_in] <= write_data_in;
            memory1[write_addr_in] <= write_data_in;
        end
    end

    assign read_data0_out = memory0[read_addr0_in];
    assign read_data1_out = memory1[read_addr1_in];

    wire unused_l2_clk = l2_clk;
    wire unused_reset = reset;
endmodule

`default_nettype wire
