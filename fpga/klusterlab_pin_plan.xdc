# XC7K160T-3FFG676E / KlusterLab 1.0 transceiver pin plan.
# Port names are the required names for the vendor-IP integration wrapper.

set_property PACKAGE_PIN P1 [get_ports {sfp_tx_n[0]}]
set_property PACKAGE_PIN P2 [get_ports {sfp_tx_p[0]}]
set_property PACKAGE_PIN R3 [get_ports {sfp_rx_n[0]}]
set_property PACKAGE_PIN R4 [get_ports {sfp_rx_p[0]}]

set_property PACKAGE_PIN M1 [get_ports {sfp_tx_n[1]}]
set_property PACKAGE_PIN M2 [get_ports {sfp_tx_p[1]}]
set_property PACKAGE_PIN N3 [get_ports {sfp_rx_n[1]}]
set_property PACKAGE_PIN N4 [get_ports {sfp_rx_p[1]}]

set_property PACKAGE_PIN H5 [get_ports eth_refclk_n]
set_property PACKAGE_PIN H6 [get_ports eth_refclk_p]
create_clock -name eth_refclk -period 6.400 [get_ports eth_refclk_p]

set_property PACKAGE_PIN A3 [get_ports pcie_tx_n]
set_property PACKAGE_PIN A4 [get_ports pcie_tx_p]
set_property PACKAGE_PIN B5 [get_ports pcie_rx_n]
set_property PACKAGE_PIN B6 [get_ports pcie_rx_p]
set_property PACKAGE_PIN D5 [get_ports pcie_refclk_n]
set_property PACKAGE_PIN D6 [get_ports pcie_refclk_p]
