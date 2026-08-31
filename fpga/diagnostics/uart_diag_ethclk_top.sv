`timescale 1ns/1ps
`default_nettype none

// Minimal UART-only image using the board's 156.25 MHz MGT reference clock.
module uart_diag_ethclk_top (
    input  wire eth_refclk_p,
    input  wire eth_refclk_n,
    input  wire uart_usb_txd,
    input  wire uart_usb_rts,
    output wire uart_usb_rxd,
    output wire uart_usb_cts
);
    wire eth_refclk_raw;
    wire eth_refclk;

    IBUFDS_GTE2 eth_refclk_ibuf (
        .CEB(1'b0),
        .I(eth_refclk_p),
        .IB(eth_refclk_n),
        .O(eth_refclk_raw),
        .ODIV2()
    );
    BUFG eth_refclk_bufg (.I(eth_refclk_raw), .O(eth_refclk));

    uart_banner_tx #(
        .CLOCK_HZ(156_250_000),
        .BAUD(115_200),
        .MESSAGE_BYTES(41),
        .MESSAGE({"KLUSTERLAB2 UART_USB_RXD A17 ETHCLK 8N1",
            8'h0d, 8'h0a}),
        .REPEAT_GAP_BITS(115_200)
    ) banner (
        .clk(eth_refclk),
        .reset(1'b0),
        .tx(uart_usb_rxd)
    );

    assign uart_usb_cts = 1'b0;

    wire unused_uart_inputs = uart_usb_txd ^ uart_usb_rts;
endmodule

`default_nettype wire
