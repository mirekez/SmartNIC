`timescale 1ns/1ps
`default_nettype none

// Canonical 128 x 1024 synchronous simple-dual-port memory. Keeping this
// primitive separate prevents CppHDL's generic memory array from becoming
// flip-flops while all probe control remains generated from UART_PROBE.h.
module UARTProbeMemory #(
    parameter integer WIDTH = 128,
    parameter integer DEPTH = 1024
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     write_in,
    input  wire [$clog2(DEPTH)-1:0] write_addr_in,
    input  wire [WIDTH-1:0]         write_data_in,
    input  wire                     read_in,
    input  wire [$clog2(DEPTH)-1:0] read_addr_in,
    output wire [WIDTH-1:0]         read_data_out
);
    (* ram_style = "block" *) reg [WIDTH-1:0] buffer [0:DEPTH-1];
    reg [WIDTH-1:0] read_data_reg = {WIDTH{1'b0}};

    always @(posedge clk) begin
        if (write_in)
            buffer[write_addr_in] <= write_data_in;
        if (reset)
            read_data_reg <= {WIDTH{1'b0}};
        else if (read_in)
            read_data_reg <= buffer[read_addr_in];
    end

    assign read_data_out = read_data_reg;
endmodule

`default_nettype wire
