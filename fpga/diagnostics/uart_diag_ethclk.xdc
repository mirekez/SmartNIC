set_property PACKAGE_PIN H6 [get_ports eth_refclk_p]
set_property PACKAGE_PIN H5 [get_ports eth_refclk_n]
create_clock -name eth_refclk -period 6.400 [get_ports eth_refclk_p]

# JTAG-SMT3 UART: TXD/RTS are outputs from the bridge; RXD/CTS are inputs.
set_property PACKAGE_PIN K15 [get_ports uart_usb_txd]
set_property PACKAGE_PIN B17 [get_ports uart_usb_rts]
set_property PACKAGE_PIN A17 [get_ports uart_usb_rxd]
set_property PACKAGE_PIN F18 [get_ports uart_usb_cts]
set_property IOSTANDARD LVCMOS12 [get_ports {uart_usb_*}]
set_property DRIVE 4 [get_ports {uart_usb_rxd uart_usb_cts}]
set_property SLEW SLOW [get_ports {uart_usb_rxd uart_usb_cts}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
