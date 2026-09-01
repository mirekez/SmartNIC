`default_nettype none

// Canonical Xilinx distributed-RAM implementation for the CppHDL storage
// leaf. Queue policy, pointers, occupancy, and protocol handling remain in
// the generated parent RTL.
(* keep_hierarchy = "yes" *)
module AsyncReadRam #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 64
) (
    input  wire                         clk,
    input  wire                         l2_clock,
    input  wire                         reset,
    input  wire [$clog2(DEPTH)-1:0]     write_addr_in,
    input  wire                         write_in,
    input  wire [WIDTH-1:0]             write_data_in,
    input  wire [$clog2(DEPTH)-1:0]     read_addr_in,
    output wire [WIDTH-1:0]             read_data_out
);
    (* ram_style = "distributed" *)
    reg [WIDTH-1:0] memory [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (write_in)
            memory[write_addr_in] <= write_data_in;
    end

    assign read_data_out = memory[read_addr_in];

    wire unused_l2_clock = l2_clock;
    wire unused_reset = reset;
endmodule

`default_nettype wire
