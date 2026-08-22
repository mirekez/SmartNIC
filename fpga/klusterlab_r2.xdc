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

# Direct FPGA-side SFP management nets are in 3.3 V bank 13.
set_property PACKAGE_PIN T19 [get_ports {sfp_los[0]}]
set_property PACKAGE_PIN M19 [get_ports {sfp_los[1]}]
set_property PACKAGE_PIN R18 [get_ports {sfp_tx_en[0]}]
set_property PACKAGE_PIN N18 [get_ports {sfp_tx_en[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_los[*] sfp_tx_en[*]}]
set_property PULLUP true [get_ports {sfp_los[*]}]

# The retained system ILA is clocked by net_clk.  These registers are the
# first stage of explicit two-flop synchronizers for diagnostic-only status
# and clock-activity signals originating in startup/GTX domains.  Timing an
# asynchronous source to the metastability-catching D pin is meaningless and
# made the router trade setup against hold on exactly these pins.  Keep this
# exception deliberately narrow: the second synchronizer stages and all
# functional datapaths remain timed normally.
set debug_cdc_first_stage_cells [get_cells -quiet -hier -filter \
    {NAME =~ *dclk_toggle_meta_reg || \
     NAME =~ *txusr_toggle_meta_reg || \
     NAME =~ *ila_*_meta_reg*}]
set debug_cdc_first_stage_pins [get_pins -quiet -of_objects \
    $debug_cdc_first_stage_cells -filter {REF_PIN_NAME == D}]
set_false_path -to $debug_cdc_first_stage_pins

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
