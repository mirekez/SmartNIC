`timescale 1ns/1ps
`default_nettype none

import PacketParserWord_pkg::*;

// Resource-bounded FPGA implementation of the generated PacketParser module
// boundary. It captures the first 64 bytes of each frame and queues one record
// per port. The CppHDL parser remains the behavioral reference; replacing this
// shim with a pipelined parser does not change Network or SmartNIC interfaces.
module PacketParser #(
    parameter LANE_WIDTH = 64,
    parameter STREAMS = 2,
    parameter LANE_BYTES = LANE_WIDTH / 8,
    parameter INPUT_BITS = STREAMS * LANE_WIDTH,
    parameter INPUT_BYTES = STREAMS * LANE_BYTES
) (
    input  wire net_clk,
    input  wire l2_clk,
    input  wire reset,
    input  wire [STREAMS-1:0] valid_in,
    input  wire [INPUT_BITS-1:0] data_in,
    input  wire [INPUT_BYTES-1:0] keep_in,
    input  wire [INPUT_BYTES-1:0] sop_in,
    input  wire [INPUT_BYTES-1:0] eop_in,
    input  wire [STREAMS-1:0] raw_in,
    output wire [STREAMS-1:0] ready_out,
    output PacketParserWord [STREAMS-1:0] data_out,
    output wire [STREAMS*64-1:0] keep_out,
    output wire [STREAMS-1:0] valid_out,
    output wire [STREAMS-1:0] last_out,
    output wire [STREAMS-1:0] raw_out,
    input  wire [STREAMS-1:0] ready_in,
    output wire protocol_error_out
);
    wire unused_l2_clk = l2_clk;
    reg [511:0] capture [0:STREAMS-1];
    reg [6:0] count [0:STREAMS-1];
    reg in_frame [0:STREAMS-1];
    reg frame_raw [0:STREAMS-1];
    reg [511:0] output_data [0:STREAMS-1];
    reg [63:0] output_keep [0:STREAMS-1];
    reg output_valid [0:STREAMS-1];
    reg output_raw [0:STREAMS-1];
    reg protocol_error;

    genvar g;
    generate for (g = 0; g < STREAMS; g = g + 1) begin : output_wiring
        assign ready_out[g] = ~output_valid[g] | ready_in[g];
        assign data_out[g].raw = output_data[g];
        assign keep_out[g*64 +: 64] = output_keep[g];
        assign valid_out[g] = output_valid[g];
        assign last_out[g] = output_valid[g];
        assign raw_out[g] = output_raw[g];
    end endgenerate
    assign protocol_error_out = protocol_error;

    integer stream;
    integer byte_index;
    integer flat;
    integer next_count;
    reg [511:0] next_capture;
    reg next_in_frame;
    reg next_raw;
    always @(posedge net_clk) begin
        if (reset) begin
            protocol_error <= 1'b0;
            for (stream = 0; stream < STREAMS; stream = stream + 1) begin
                capture[stream] <= 512'b0;
                count[stream] <= 7'd0;
                in_frame[stream] <= 1'b0;
                frame_raw[stream] <= 1'b0;
                output_data[stream] <= 512'b0;
                output_keep[stream] <= 64'b0;
                output_valid[stream] <= 1'b0;
                output_raw[stream] <= 1'b0;
            end
        end else begin
            for (stream = 0; stream < STREAMS; stream = stream + 1) begin
                if (output_valid[stream] && ready_in[stream])
                    output_valid[stream] <= 1'b0;
                if (valid_in[stream] && ready_out[stream]) begin
                    next_capture = capture[stream];
                    next_count = count[stream];
                    next_in_frame = in_frame[stream];
                    next_raw = frame_raw[stream];
                    for (byte_index = 0; byte_index < LANE_BYTES;
                            byte_index = byte_index + 1) begin
                        flat = stream * LANE_BYTES + byte_index;
                        if (keep_in[flat]) begin
                            if (sop_in[flat]) begin
                                if (next_in_frame)
                                    protocol_error <= 1'b1;
                                next_capture = 512'b0;
                                next_count = 0;
                                next_in_frame = 1'b1;
                                next_raw = raw_in[stream];
                            end else if (!next_in_frame) begin
                                protocol_error <= 1'b1;
                            end
                            if (next_in_frame && next_count < 64) begin
                                next_capture[next_count*8 +: 8] =
                                    data_in[flat*8 +: 8];
                                next_count = next_count + 1;
                            end
                            if (eop_in[flat] && next_in_frame) begin
                                output_data[stream] <= next_capture;
                                output_keep[stream] <=
                                    (next_count >= 64) ? 64'hffff_ffff_ffff_ffff :
                                    ((64'h1 << next_count) - 1'b1);
                                output_raw[stream] <= next_raw;
                                output_valid[stream] <= 1'b1;
                                next_in_frame = 1'b0;
                            end
                        end else if (sop_in[flat] || eop_in[flat]) begin
                            protocol_error <= 1'b1;
                        end
                    end
                    capture[stream] <= next_capture;
                    count[stream] <= next_count[6:0];
                    in_frame[stream] <= next_in_frame;
                    frame_raw[stream] <= next_raw;
                end
            end
        end
    end
endmodule

`default_nettype wire
