# KlusterLab 1.0 Kintex-7 target

Target part: `xc7k160tffg676-3` (`XC7K160T-3FFG676E`).

The board pinout routes four SFP+ lanes through GTX bank 115 and one PCIe lane
through GTX bank 116. This design uses bank-115 channels 0 and 1 for 2x10GbE.
The on-board 156.25 MHz differential reference clock drives the 10G PCS/PMA.
PCIe uses bank-116 channel 3 and its dedicated differential reference clock.

| Function | Package pins | GTX site |
|---|---|---|
| 10G lane 0 TX N/P | P1 / P2 | MGTXTXN/P0_115 |
| 10G lane 0 RX N/P | R3 / R4 | MGTXRXN/P0_115 |
| 10G lane 1 TX N/P | M1 / M2 | MGTXTXN/P1_115 |
| 10G lane 1 RX N/P | N3 / N4 | MGTXRXN/P1_115 |
| 156.25 MHz refclk N/P | H5 / H6 | MGTREFCLK0N/P_115 |
| PCIe TX0 N/P | A3 / A4 | MGTXTXN/P3_116 |
| PCIe RX0 N/P | B5 / B6 | MGTXRXN/P3_116 |
| PCIe refclk N/P | D5 / D6 | MGTREFCLK0N/P_116 |

Use the AMD 10G/25G Ethernet Subsystem or an equivalent synthesizable
10GBASE-R PCS/PMA wrapper for the two serial lanes. Configure the 7-series
Integrated Block for PCI Express for Gen2 x1 with a 64-bit, 125 MHz user-side
bridge. `klusterlab_pin_plan.xdc` records the exact package bindings; adapt its
port names to the chosen vendor-IP wrapper.
