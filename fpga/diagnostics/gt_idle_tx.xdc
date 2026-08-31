set_property PACKAGE_PIN H6 [get_ports eth_refclk_p]
set_property PACKAGE_PIN H5 [get_ports eth_refclk_n]
create_clock -name eth_refclk -period 6.400 [get_ports eth_refclk_p]

# GTX TXOUTCLK is line_rate/32 = 322.265625 MHz.  Vivado cannot infer this
# relationship through the transceiver primitive, so constrain the BUFG output
# explicitly or the custom PCS would be timed incorrectly at 156.25 MHz.
create_clock -name txusrclk -period 3.103030 \
    [get_pins clock_reset_inst/txoutclk_bufg_i/O]

# TXOUTCLK is frequency-related to the reference through the QPLL but its
# fabric phase is not defined.  All status crossings into the UART probe are
# diagnostic samplers, so do not let the router invent impossible synchronous
# setup/hold requirements between these domains.
set_clock_groups -asynchronous \
    -group [get_clocks eth_refclk] -group [get_clocks txusrclk]

# Reset deassertion is handled by the generated five-stage synchronizers.
set_false_path -to [get_pins -hierarchical -filter \
    {REF_PIN_NAME == PRE || REF_PIN_NAME == CLR}]

set_property PACKAGE_PIN P2 [get_ports {sfp_tx_p[0]}]
set_property PACKAGE_PIN P1 [get_ports {sfp_tx_n[0]}]
set_property PACKAGE_PIN R4 [get_ports {sfp_rx_p[0]}]
set_property PACKAGE_PIN R3 [get_ports {sfp_rx_n[0]}]
set_property PACKAGE_PIN M2 [get_ports {sfp_tx_p[1]}]
set_property PACKAGE_PIN M1 [get_ports {sfp_tx_n[1]}]
set_property PACKAGE_PIN N4 [get_ports {sfp_rx_p[1]}]
set_property PACKAGE_PIN N3 [get_ports {sfp_rx_n[1]}]
set_property PACKAGE_PIN K2 [get_ports {sfp_tx_p[2]}]
set_property PACKAGE_PIN K1 [get_ports {sfp_tx_n[2]}]
set_property PACKAGE_PIN L4 [get_ports {sfp_rx_p[2]}]
set_property PACKAGE_PIN L3 [get_ports {sfp_rx_n[2]}]
set_property PACKAGE_PIN H2 [get_ports {sfp_tx_p[3]}]
set_property PACKAGE_PIN H1 [get_ports {sfp_tx_n[3]}]
set_property PACKAGE_PIN J4 [get_ports {sfp_rx_p[3]}]
set_property PACKAGE_PIN J3 [get_ports {sfp_rx_n[3]}]

set_property PACKAGE_PIN T19 [get_ports {sfp_los[0]}]
set_property PACKAGE_PIN M19 [get_ports {sfp_los[1]}]
set_property PACKAGE_PIN R17 [get_ports {sfp_los[2]}]
set_property PACKAGE_PIN R16 [get_ports {sfp_los[3]}]
set_property PACKAGE_PIN R18 [get_ports {sfp_tx_en[0]}]
set_property PACKAGE_PIN N18 [get_ports {sfp_tx_en[1]}]
set_property PACKAGE_PIN N17 [get_ports {sfp_tx_en[2]}]
set_property PACKAGE_PIN P16 [get_ports {sfp_tx_en[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_los[*] sfp_tx_en[*]}]
set_property PULLUP true [get_ports {sfp_los[*]}]

set_property PACKAGE_PIN A17 [get_ports uart_usb_rxd]
set_property PACKAGE_PIN K15 [get_ports uart_usb_txd]
set_property PACKAGE_PIN B17 [get_ports uart_usb_rts]
set_property IOSTANDARD LVCMOS12 [get_ports {uart_usb_*}]
set_property DRIVE 4 [get_ports uart_usb_rxd]
set_property SLEW SLOW [get_ports uart_usb_rxd]

set_property PACKAGE_PIN V21 [get_ports main_i2c_scl]
set_property PACKAGE_PIN AE21 [get_ports main_i2c_sda]
set_property PACKAGE_PIN W21 [get_ports main_i2c_mux_reset_n]
set_property IOSTANDARD LVCMOS18 [get_ports {main_i2c_scl main_i2c_sda main_i2c_mux_reset_n}]
set_property PULLUP true [get_ports {main_i2c_scl main_i2c_sda}]
set_property DRIVE 4 [get_ports main_i2c_mux_reset_n]
set_property SLEW SLOW [get_ports main_i2c_mux_reset_n]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
