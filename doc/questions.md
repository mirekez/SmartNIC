# FPGA integration boundary

The portable C++HDL/SystemVerilog hierarchy ends at MAC-side Ethernet streams
and the 64-bit PCIe user interface. Board implementation must instantiate AMD
10GBASE-R PCS/PMA and the 7-series PCIe Gen2 hard-block wrapper, then connect
their user interfaces to these RTL ports. The selected part, clocks, lane
locations, and package pins are recorded in `fpga/README.md`.
