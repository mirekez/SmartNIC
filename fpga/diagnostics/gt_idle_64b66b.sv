`timescale 1ns/1ps
`default_nettype none

// Minimal 10GBASE-R transmit PCS for the GTXE2 synchronous gearbox.  The
// scrambler supplies a continuous stream of 64-bit all-idle control payloads
// as two 32-bit words.  The GTX inserts the uns scrambled two-bit sync header.
module gt_idle_64b66b (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] txdata,
    output wire [1:0]  txheader,
    output wire [6:0]  txsequence
);
    // The generated Xilinx PCS presents its conventional 2'b10 control header
    // to the primitive with both bits swapped.  Match the primitive-facing
    // value, not the PCS-internal notation.
    localparam [1:0] CONTROL_HEADER = 2'b01;
    reg [57:0] scrambler_state;
    reg [5:0] sequence_count;
    reg data_half;
    reg [31:0] held_txdata;
    reg [31:0] payload32_input;

    wire [31:0] scrambled32;
    wire [57:0] state32;

    scrambler_parallel_32 scrambler32_inst (
        .data_in(payload32_input), .state_in(scrambler_state),
        .data_out(scrambled32), .state_out(state32)
    );

    // An all-idle control block has block type 0x1e followed by seven encoded
    // idle control characters (all zero).  Payload bits are sent LSB first.
    always @* begin
        payload32_input = data_half ? 32'h00000000 : 32'h0000001e;
    end

    // TXDATA must describe the same gearbox phase as TXSEQUENCE before the
    // active clock edge.  Registering it here added a one-cycle phase error:
    // the GTX sampled the previous half-block with the current sequence.
    // During the two sequence-32 pause clocks, retain the last accepted word.
    // This scrambler is already expressed in primitive serialization order
    // (bit 0 first).  The generated Xilinx wrapper reverses its own PCS bus
    // because that internal bus is MSB-first; applying that reversal here
    // would reverse the Clause-49 stream a second time.
    assign txdata = (sequence_count == 6'd32) ? held_txdata : scrambled32;
    assign txheader = CONTROL_HEADER;
    assign txsequence = {1'b0, sequence_count};

    always @(posedge clk) begin
        if (reset) begin
            scrambler_state <= {58{1'b1}};
            sequence_count <= 6'd0;
            data_half <= 1'b0;
            held_txdata <= 32'd0;
        end else begin
            // With 32-bit fabric and internal datapaths TXSEQUENCE changes
            // every two clocks.  At sequence 32 the synchronous gearbox
            // consumes no new payload for two clocks while it emits headers.
            if (sequence_count == 6'd32) begin
                if (data_half) begin
                    sequence_count <= 6'd0;
                    data_half <= 1'b0;
                end else begin
                    data_half <= 1'b1;
                end
            end else begin
                held_txdata <= scrambled32;
                scrambler_state <= state32;
                if (data_half) begin
                    sequence_count <= sequence_count + 1'b1;
                    data_half <= 1'b0;
                end else begin
                    data_half <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
