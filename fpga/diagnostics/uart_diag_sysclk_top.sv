`timescale 1ns/1ps
`default_nettype none

// Minimal UART-only image using the board's 200 MHz system oscillator.
module uart_diag_sysclk_top (
    input  wire sys_clk_200_p,
    input  wire sys_clk_200_n,
    input  wire uart_usb_txd,
    input  wire uart_usb_rts,
    output wire uart_usb_rxd,
    output wire uart_usb_cts
);
    wire sys_clk_200_ibuf;
    wire sys_clk_200;

    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("FALSE"),
        .IOSTANDARD("LVDS")
    ) sys_clk_ibuf (
        .I(sys_clk_200_p),
        .IB(sys_clk_200_n),
        .O(sys_clk_200_ibuf)
    );
    BUFG sys_clk_bufg (.I(sys_clk_200_ibuf), .O(sys_clk_200));

    uart_banner_tx #(
        .CLOCK_HZ(200_000_000),
        .BAUD(115_200),
        .MESSAGE_BYTES(41),
        .MESSAGE({"KLUSTERLAB2 UART_USB_RXD A17 115200 8N1",
            8'h0d, 8'h0a}),
        .REPEAT_GAP_BITS(115_200)
    ) banner (
        .clk(sys_clk_200),
        .reset(1'b0),
        .tx(uart_usb_rxd)
    );

    assign uart_usb_cts = 1'b0;

    wire unused_uart_inputs = uart_usb_txd ^ uart_usb_rts;
endmodule

`default_nettype wire
