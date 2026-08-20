# KlusterLab r2.0, XC7K160T-3FFG676E.  Pin/net correlation was checked
# against the imported KiCad PCB and the MGT/System Clocks schematics.

set_property PACKAGE_PIN AC9 [get_ports sys_clk_200_p]
set_property PACKAGE_PIN AD9 [get_ports sys_clk_200_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_200_p sys_clk_200_n}]
create_clock -name sys_clk_200 -period 5.000 [get_ports sys_clk_200_p]

set_property PACKAGE_PIN H6 [get_ports eth_refclk_p]
set_property PACKAGE_PIN H5 [get_ports eth_refclk_n]
# The AXI 10G Ethernet master IP owns the 6.400 ns refclk_p constraint.
# Duplicating it here overrides the IP clock and disables incremental reuse.

# SFP+ 0 = GTX bank 115 channel 0.
set_property PACKAGE_PIN P2 [get_ports {sfp_tx_p[0]}]
set_property PACKAGE_PIN P1 [get_ports {sfp_tx_n[0]}]
set_property PACKAGE_PIN R4 [get_ports {sfp_rx_p[0]}]
set_property PACKAGE_PIN R3 [get_ports {sfp_rx_n[0]}]

# SFP+ 1 = GTX bank 115 channel 1.
set_property PACKAGE_PIN M2 [get_ports {sfp_tx_p[1]}]
set_property PACKAGE_PIN M1 [get_ports {sfp_tx_n[1]}]
set_property PACKAGE_PIN N4 [get_ports {sfp_rx_p[1]}]
set_property PACKAGE_PIN N3 [get_ports {sfp_rx_n[1]}]

# Direct FPGA-side SFP management nets are in 1.8 V bank 14.
set_property PACKAGE_PIN T19 [get_ports {sfp_los[0]}]
set_property PACKAGE_PIN M19 [get_ports {sfp_los[1]}]
set_property PACKAGE_PIN R18 [get_ports {sfp_tx_en[0]}]
set_property PACKAGE_PIN N18 [get_ports {sfp_tx_en[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sfp_los[*] sfp_tx_en[*]}]
set_property PULLUP true [get_ports {sfp_los[*]}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
