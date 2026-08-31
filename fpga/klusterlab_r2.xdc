# KlusterLab r2.0, XC7K325T-3FFG676E.  Pin/net correlation was checked
# against the imported KiCad PCB and the MGT/System Clocks schematics.

set_property PACKAGE_PIN AC9 [get_ports sys_clk_200_p]
set_property PACKAGE_PIN AD9 [get_ports sys_clk_200_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_200_p sys_clk_200_n}]
create_clock -name sys_clk_200 -period 5.000 [get_ports sys_clk_200_p]

set_property PACKAGE_PIN H6 [get_ports eth_refclk_p]
set_property PACKAGE_PIN H5 [get_ports eth_refclk_n]
# The AXI 10G Ethernet master IP owns the 6.400 ns refclk_p constraint.
# Duplicating it here overrides the IP clock and disables incremental reuse.

# PCIe Gen2 x1 = GTX bank 116 channel 3.  The PCIe bridge IP owns the 100 MHz
# reference-clock timing constraint.
set_property PACKAGE_PIN A4 [get_ports pcie_tx_p]
set_property PACKAGE_PIN A3 [get_ports pcie_tx_n]
set_property PACKAGE_PIN B6 [get_ports pcie_rx_p]
set_property PACKAGE_PIN B5 [get_ports pcie_rx_n]
set_property PACKAGE_PIN D6 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN D5 [get_ports pcie_refclk_n]

# Active-low PCIe reset from the CM4/host, in 3.3 V bank 13.
set_property PACKAGE_PIN P18 [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS33 [get_ports pcie_perst_n]
set_property PULLUP true [get_ports pcie_perst_n]

# The two logical SmartNIC ports use the cages connected to the test PCs.
# Logical port 0 = board SFP+ 2 = GTX bank 115 channel 2 (fpga2).
set_property PACKAGE_PIN K2 [get_ports {sfp_tx_p[0]}]
set_property PACKAGE_PIN K1 [get_ports {sfp_tx_n[0]}]
set_property PACKAGE_PIN L4 [get_ports {sfp_rx_p[0]}]
set_property PACKAGE_PIN L3 [get_ports {sfp_rx_n[0]}]

# Logical port 1 = board SFP+ 3 = GTX bank 115 channel 3 (fpga1).
set_property PACKAGE_PIN H2 [get_ports {sfp_tx_p[1]}]
set_property PACKAGE_PIN H1 [get_ports {sfp_tx_n[1]}]
set_property PACKAGE_PIN J4 [get_ports {sfp_rx_p[1]}]
set_property PACKAGE_PIN J3 [get_ports {sfp_rx_n[1]}]

# Direct FPGA-side SFP management nets are in 3.3 V bank 13.
set_property PACKAGE_PIN R17 [get_ports {sfp_los[0]}]
set_property PACKAGE_PIN R16 [get_ports {sfp_los[1]}]
set_property PACKAGE_PIN N17 [get_ports {sfp_tx_en[0]}]
set_property PACKAGE_PIN P16 [get_ports {sfp_tx_en[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_los[*] sfp_tx_en[*]}]
set_property PULLUP true [get_ports {sfp_los[*]}]

# On-board JTAG-SMT3 USB-UART.  Signal names are from the bridge perspective:
# A17 drives its RXD input and F18 drives its active-low CTS input.  K15 TXD
# and B17 RTS are bridge outputs and therefore remain FPGA inputs.  Bank 15
# and the bridge VREF_UART share the adjustable CRUVI rail; with no VSEL pins
# driven in this image its hardware default is 1.2 V.
set_property PACKAGE_PIN K15 [get_ports uart_usb_txd]
set_property PACKAGE_PIN B17 [get_ports uart_usb_rts]
set_property PACKAGE_PIN A17 [get_ports uart_usb_rxd]
set_property PACKAGE_PIN F18 [get_ports uart_usb_cts]
set_property IOSTANDARD LVCMOS12 [get_ports {uart_usb_*}]
set_property DRIVE 4 [get_ports {uart_usb_rxd uart_usb_cts}]
set_property SLEW SLOW [get_ports {uart_usb_rxd uart_usb_cts}]

# startup_reset is generated in the 50 MHz startup domain.  Its functional
# release into net_clk is synchronized by net_reset_sync; time only the second
# and later stages.  The PCIe core consumes the same signal solely as an
# asynchronous reset assertion, so its asynchronous control pins likewise do
# not have a meaningful setup/hold relationship to userclk1.
set startup_reset_source [get_cells -quiet -hier -filter \
    {IS_SEQUENTIAL == 1 && NAME =~ *por_shift_reg[7]}]
set net_reset_first_d [get_pins -quiet -hier -filter \
    {NAME =~ *net_reset_sync_reg[0]/D}]
set pcie_async_reset_pins [get_pins -quiet -hier -filter \
    {NAME =~ host_system/* && (REF_PIN_NAME == R || REF_PIN_NAME == CLR || \
        REF_PIN_NAME == PRE)}]
set_false_path -from $startup_reset_source -to $net_reset_first_d
set_false_path -from $startup_reset_source -to $pcie_async_reset_pins

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
