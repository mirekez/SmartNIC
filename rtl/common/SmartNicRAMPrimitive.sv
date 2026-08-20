`default_nettype none

// FPGA storage leaf for CppHDL SmartNicRAM. RxRAM retains addressing,
// allocation, arbitration, and packet-lifetime control; this module only
// expresses the canonical synchronous simple-dual-port block-RAM pattern.
module SmartNicRAM #(
    parameter integer WIDTH = 320,
    parameter integer DEPTH = 4096
) (
    input  wire                         net_clk,
    input  wire                         l2_clk,
    input  wire                         reset,
    input  wire [$clog2(DEPTH)-1:0]     write_addr_in,
    input  wire [$clog2(DEPTH)-1:0]     read_addr_in,
    input  wire [WIDTH-1:0]             data_in,
    input  wire                         wr_in,
    input  wire                         rd_in,
    output wire [WIDTH-1:0]             q_out,
    input  wire signed [31:0]           id_in
);
    (* ram_style = "block" *)
    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [WIDTH-1:0] read_data_reg;

    always_ff @(posedge net_clk) begin
        if (wr_in)
            memory[write_addr_in] <= data_in;
        if (reset)
            read_data_reg <= '0;
        else if (rd_in)
            read_data_reg <= memory[read_addr_in];
    end

    assign q_out = read_data_reg;

    wire unused_l2_clk = l2_clk;
    wire signed [31:0] unused_id_in = id_in;
endmodule

