# KlusterLab 2.0 SFP+ lane mapping test

Test date: 2026-08-30

The source design instantiates the Xilinx 10G Ethernet PCS/PMA on all four
GTXE2 channels.  `build_xilinx_gtx_onehot_tests.tcl` opens the proven routed
checkpoint, leaves all SFP modules enabled, and makes exactly one GTX transmit
channel active by forcing the other primitive `TXINHIBIT` inputs high.

| Active GTX | FPGA location | fpga1/enp1s0 | fpga2/enp1s0 |
|---|---|---|---|
| 0 | GTXE2_CHANNEL_X0Y0 | no link | no link |
| 1 | GTXE2_CHANNEL_X0Y1 | no link | no link |
| 2 | GTXE2_CHANNEL_X0Y2 | no link | 10000 Mb/s, link yes |
| 3 | GTXE2_CHANNEL_X0Y3 | 10000 Mb/s, link yes | no link |

With all four GTX transmitters active, both PCs report 10000 Mb/s and link yes.
Thus fpga2 is cabled to board SFP2/GTX2 and fpga1 is cabled to board SFP3/GTX3.
This agrees with the schematic and XDC ordering; it is not a lane swap in the
FPGA pinout.

The routed baseline uses the Xilinx-generated GTX values on every channel:

- `TXDIFFCTRL = 4'b1110`
- `TXPRECURSOR = 5'b00000`
- `TXPOSTCURSOR = 5'b00000`
- `TXPOLARITY = 1'b0`
- normal external operation, with PCS configuration and loopback controls zero

The module-enable-only test was not used to infer the high-speed lane mapping.
SFP2 enable controls whether fpga2 links, but fpga1 remained linked when other
individual enable pins were selected.  Primitive `TXINHIBIT` provides the
unambiguous electrical-lane isolation shown above.
