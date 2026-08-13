# KlusterLab r2.0 clocking specification

The board does not need a programmable clock chip for normal SmartNIC boot.
Three independent differential oscillators are wired directly to the FPGA:

| PCB net | Source | FPGA pins/resource | Use |
|---|---|---|---|
| `200MHz_SYSCLK_P/N` | `Y7`, AX3DCF1-200.0000 | AC9/AD9, bank-14 MRCC | unconditional startup clock |
| `156.25MHz_REFCLK_P/N` | `Y6`, AX3DCF1-156.2500 | H6/H5, MGTREFCLK1 bank 115 | 10G QPLL and MAC clock |
| `150MHz_REFCLK_P/N` | `Y5`, 511JBA150M000CAG | F6/F5, MGTREFCLK1 bank 116 | spare/PCIe-adjacent GTX reference |

The 200 MHz clock feeds an MMCM that produces the 50 MHz 10G reset/DRP clock.
Lane 0 of the Xilinx AXI 10G Ethernet subsystem owns the bank-115 QPLL and
exports the common 156.25 MHz MAC/L2 clock to lane 1.  A second MMCM multiplies
that clock to 312.5 MHz for the four Tribe cores and their private L1 caches.

PCIe uses its dedicated 100 MHz connector reference on D6/D5
(`PCIe_REFCLK_P/N`).  The 100 MHz signal is a dedicated MGT reference input,
not a fabric system clock. A future 7-series Integrated Block for PCIe Gen2 x1 must
use its generated 125 MHz `user_clk_out` for the System block; it must not use
the Ethernet-derived clocks.

`U23` (Si5324C) is the optional recovered-clock/jitter-cleaner path.  Its input
comes from `REC_CLOCK_P/N`, its output returns as `SI5324_REFCLK_P/N`, and it is
controlled through `SI5324_SCL/SDA`, reset and init pins.  This path is not in
the SmartNIC startup clock tree, so no Si5324 register program is required for
2x10G Ethernet or PCIe operation.
