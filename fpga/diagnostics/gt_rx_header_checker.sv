`timescale 1ns/1ps
`default_nettype none

// Clause-49 style block-lock monitor for the GTX receive gearbox.  A wrong
// bit alignment produces random two-bit headers, while a correct 10GBASE-R
// stream produces only 01 or 10.  Test 64 headers before requesting one slip
// so random headers cannot masquerade as a valid alignment.
module gt_rx_header_checker (
    input  wire        clk,
    input  wire        reset,
    input  wire        header_valid,
    input  wire [1:0]  header,
    output reg         gearbox_slip,
    output reg         block_locked,
    output reg  [6:0]  current_invalid,
    output reg  [6:0]  last_invalid,
    output reg  [7:0]  slip_count,
    output reg  [15:0] header_count
);
    reg [5:0] window_count;
    wire header_good = (header == 2'b01) || (header == 2'b10);
    wire [6:0] completed_invalid = current_invalid + !header_good;

    always @(posedge clk) begin
        gearbox_slip <= 1'b0;
        if (reset) begin
            gearbox_slip <= 1'b0;
            block_locked <= 1'b0;
            current_invalid <= 7'd0;
            last_invalid <= 7'h7f;
            slip_count <= 8'd0;
            header_count <= 16'd0;
            window_count <= 6'd0;
        end else if (header_valid) begin
            header_count <= header_count + 1'b1;
            if (window_count == 6'd63) begin
                last_invalid <= completed_invalid;
                current_invalid <= 7'd0;
                window_count <= 6'd0;
                if (completed_invalid > 7'd16) begin
                    gearbox_slip <= 1'b1;
                    block_locked <= 1'b0;
                    slip_count <= slip_count + 1'b1;
                end else begin
                    block_locked <= 1'b1;
                end
            end else begin
                window_count <= window_count + 1'b1;
                if (!header_good)
                    current_invalid <= current_invalid + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
