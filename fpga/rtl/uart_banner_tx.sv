`timescale 1ns/1ps
`default_nettype none

// Small, firmware-independent UART beacon.  It starts as soon as the board
// startup clock is stable, so identifying the physical USB-UART connection
// does not depend on CPU boot, BRAM contents, PCIe, Ethernet, or JTAG.
module uart_banner_tx #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer MESSAGE_BYTES = 41,
    parameter logic [MESSAGE_BYTES * 8 - 1:0] MESSAGE =
        {"KLUSTERLAB2 UART_USB_RXD A17 115200 8N1", 8'h0d, 8'h0a},
    parameter integer REPEAT_GAP_BITS = 115_200
) (
    input  wire clk,
    input  wire reset,
    output wire tx
);
    // Rounding rather than truncating gives 434 clocks/bit at 50 MHz, or
    // 115207.37 baud (0.0064% fast), comfortably inside normal UART tolerance.
    localparam integer CLKS_PER_BIT = (CLOCK_HZ + BAUD / 2) / BAUD;
    localparam integer BAUD_COUNTER_BITS =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
    localparam integer MESSAGE_INDEX_BITS =
        (MESSAGE_BYTES <= 1) ? 1 : $clog2(MESSAGE_BYTES);
    localparam integer GAP_COUNTER_BITS =
        (REPEAT_GAP_BITS <= 1) ? 1 : $clog2(REPEAT_GAP_BITS);
    localparam logic [BAUD_COUNTER_BITS-1:0] BAUD_COUNTER_LIMIT =
        BAUD_COUNTER_BITS'(CLKS_PER_BIT - 1);
    localparam logic [MESSAGE_INDEX_BITS-1:0] LAST_MESSAGE_INDEX =
        MESSAGE_INDEX_BITS'(MESSAGE_BYTES - 1);
    localparam logic [GAP_COUNTER_BITS-1:0] GAP_COUNTER_LIMIT =
        GAP_COUNTER_BITS'(REPEAT_GAP_BITS - 1);

    reg [BAUD_COUNTER_BITS-1:0] baud_counter = '0;
    reg [MESSAGE_INDEX_BITS-1:0] message_index = '0;
    reg [GAP_COUNTER_BITS-1:0] gap_counter = GAP_COUNTER_LIMIT;
    reg [9:0] shift_register = 10'h3ff;
    reg [3:0] bits_remaining = 4'd0;

    assign tx = shift_register[0];

    function automatic [7:0] message_byte(input integer index);
        message_byte = MESSAGE[(MESSAGE_BYTES - 1 - index) * 8 +: 8];
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            baud_counter <= '0;
            message_index <= '0;
            gap_counter <= GAP_COUNTER_LIMIT;
            shift_register <= 10'h3ff;
            bits_remaining <= 4'd0;
        end
        else if (baud_counter == BAUD_COUNTER_LIMIT) begin
            baud_counter <= '0;
            if (bits_remaining != 0) begin
                if (bits_remaining == 1) begin
                    // The stop bit has completed. Start the next character at
                    // this boundary, or return to idle after the final byte.
                    if (message_index == LAST_MESSAGE_INDEX) begin
                        message_index <= '0;
                        gap_counter <= '0;
                        shift_register <= 10'h3ff;
                        bits_remaining <= 4'd0;
                    end
                    else begin
                        message_index <= message_index + 1'b1;
                        shift_register <= {
                            1'b1,
                            message_byte(integer'(message_index) + 1),
                            1'b0};
                        bits_remaining <= 4'd10;
                    end
                end
                else begin
                    shift_register <= {1'b1, shift_register[9:1]};
                    bits_remaining <= bits_remaining - 1'b1;
                end
            end
            else if (gap_counter == GAP_COUNTER_LIMIT) begin
                message_index <= '0;
                shift_register <= {1'b1, message_byte(0), 1'b0};
                bits_remaining <= 4'd10;
            end
            else begin
                gap_counter <= gap_counter + 1'b1;
            end
        end
        else begin
            baud_counter <= baud_counter + 1'b1;
        end
    end
endmodule

`default_nettype wire
