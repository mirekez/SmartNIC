`default_nettype none

// System-only physical storage leaf.  Control and queue behavior remain in
// CppHDL; this module expresses a synchronous, byte-write-enabled block RAM
// with the l2_clock/system_clock port names used by generated System RTL.
(* keep_hierarchy = "yes" *)
module SystemMemory #(
    parameter integer MEM_WIDTH_BYTES = 37,
    parameter integer MEM_DEPTH = 256,
    parameter integer SHOWAHEAD = 1,
    parameter integer FULL_WORD_WRITE = 0
) (
    input  wire                              l2_clock,
    input  wire                              system_clock,
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

    // PacketQueue storage is wholly inside System's 125 MHz domain.  The
    // l2_clock port exists only because CppHDL carries every design clock to
    // every generated child.
    always_ff @(posedge system_clock) begin
        if (write_in) begin
            if (FULL_WORD_WRITE) begin
                memory[write_addr_in] <= write_data_in;
            end else begin
                for (byte_index = 0; byte_index < MEM_WIDTH_BYTES;
                    byte_index = byte_index + 1) begin
                    if (write_mask_in[byte_index])
                        memory[write_addr_in][byte_index*8 +: 8]
                            <= write_data_in[byte_index*8 +: 8];
                end
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

    wire unused_l2_clock = l2_clock;
    wire unused_reset = reset;
endmodule

`default_nettype wire
