`timescale 1ns/1ps
`default_nettype none

// Minimal single-beat AXI-like responder matching Tribe's 256-bit memory port.
// Address and data channels are independent; one read and one write response
// may be outstanding.  Byte enables preserve normal cache writeback behavior.
module axi_boot_bram #(
    parameter integer BYTES = 65536,
    parameter INIT_FILE = "capture.mem"
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         awvalid,
    output wire         awready,
    input  wire [30:0]  awaddr,
    input  wire [3:0]   awid,
    input  wire         wvalid,
    output wire         wready,
    input  wire [255:0] wdata,
    input  wire [31:0]  wstrb,
    input  wire         wlast,
    output wire         bvalid,
    input  wire         bready,
    output wire [3:0]   bid,
    input  wire         arvalid,
    output wire         arready,
    input  wire [30:0]  araddr,
    input  wire [3:0]   arid,
    output wire         rvalid,
    input  wire         rready,
    output wire [255:0] rdata,
    output wire         rlast,
    output wire [3:0]   rid
);
    localparam integer WORD_BYTES = 32;
    localparam integer WORDS = BYTES / WORD_BYTES;
    localparam integer WORD_ADDR_BITS = $clog2(WORDS);

    initial begin
        if (BYTES < WORD_BYTES || (BYTES % WORD_BYTES) != 0)
            $error("axi_boot_bram BYTES must be a positive multiple of 32");
    end

    (* ram_style = "block" *) reg [255:0] memory [0:WORDS-1];
    initial $readmemh(INIT_FILE, memory);

    reg         read_valid_reg = 1'b0;
    reg [255:0] read_data_reg = 256'd0;
    reg [3:0]   read_id_reg = 4'd0;
    reg         write_addr_valid_reg = 1'b0;
    reg [WORD_ADDR_BITS-1:0] write_addr_reg = {WORD_ADDR_BITS{1'b0}};
    reg [3:0]   write_id_reg = 4'd0;
    reg         write_resp_valid_reg = 1'b0;
    integer byte_index;

    assign arready = ~read_valid_reg;
    assign rvalid = read_valid_reg;
    assign rdata = read_data_reg;
    assign rlast = read_valid_reg;
    assign rid = read_id_reg;
    assign awready = ~write_addr_valid_reg & ~write_resp_valid_reg;
    assign wready = write_addr_valid_reg & ~write_resp_valid_reg;
    assign bvalid = write_resp_valid_reg;
    assign bid = write_id_reg;

    always @(posedge clk) begin
        if (arvalid && arready) begin
            read_data_reg <= memory[araddr[5 +: WORD_ADDR_BITS]];
            read_id_reg <= arid;
            read_valid_reg <= 1'b1;
        end else if (read_valid_reg && rready) begin
            read_valid_reg <= 1'b0;
        end

        if (awvalid && awready) begin
            write_addr_reg <= awaddr[5 +: WORD_ADDR_BITS];
            write_id_reg <= awid;
            write_addr_valid_reg <= 1'b1;
        end
        if (wvalid && wready) begin
            for (byte_index = 0; byte_index < WORD_BYTES;
                 byte_index = byte_index + 1)
                if (wstrb[byte_index])
                    memory[write_addr_reg][byte_index*8 +: 8]
                        <= wdata[byte_index*8 +: 8];
            write_addr_valid_reg <= 1'b0;
            write_resp_valid_reg <= 1'b1;
        end
        if (write_resp_valid_reg && bready)
            write_resp_valid_reg <= 1'b0;

        if (reset) begin
            read_valid_reg <= 1'b0;
            write_addr_valid_reg <= 1'b0;
            write_resp_valid_reg <= 1'b0;
        end
    end

    // The protocol is single-beat, but consume wlast to make accidental
    // interface drift visible in elaborated debug/netlist views.
    wire unused_wlast = wlast;
endmodule

`default_nettype wire
