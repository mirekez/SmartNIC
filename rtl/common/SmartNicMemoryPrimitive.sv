`default_nettype none

// FPGA storage leaf for CppHDL SmartNicMemory. FIFO pointers, validity,
// backpressure, and protocol handling remain generated from the C++ module.
module SmartNicMemory #(
    parameter integer MEM_WIDTH_BYTES = 160,
    parameter integer MEM_DEPTH = 64,
    parameter integer SHOWAHEAD = 1
) (
    input  wire                              net_clk,
    input  wire                              l2_clk,
    input  wire                              reset,
    input  wire [$clog2(MEM_DEPTH)-1:0]      write_addr_in,
    input  wire                              write_in,
    input  wire [MEM_WIDTH_BYTES*8-1:0]      write_data_in,
    input  wire [MEM_WIDTH_BYTES-1:0]        write_mask_in,
    input  wire [$clog2(MEM_DEPTH)-1:0]      read_addr_in,
    input  wire                              read_in,
    output wire [MEM_WIDTH_BYTES*8-1:0]      read_data_out
);
    (* ram_style = "block" *)
    reg [MEM_WIDTH_BYTES*8-1:0] memory [0:MEM_DEPTH-1];
    reg [MEM_WIDTH_BYTES*8-1:0] read_data_reg;
    integer byte_index;

    always_ff @(posedge net_clk) begin
        if (write_in) begin
            for (byte_index = 0; byte_index < MEM_WIDTH_BYTES;
                byte_index = byte_index + 1) begin
                if (write_mask_in[byte_index])
                    memory[write_addr_in][byte_index*8 +: 8]
                        <= write_data_in[byte_index*8 +: 8];
            end
        end
        if (!SHOWAHEAD && read_in)
            read_data_reg <= memory[read_addr_in];
    end

    generate
        if (SHOWAHEAD) begin : g_showahead
            assign read_data_out = memory[read_addr_in];
        end else begin : g_registered
            assign read_data_out = read_data_reg;
        end
    endgenerate

    wire unused_l2_clk = l2_clk;
    wire unused_reset = reset;
endmodule

