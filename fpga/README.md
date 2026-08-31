# KlusterLab r2.0 Kintex-7 target

Target part: `xc7k325tffg676-3` (`XC7K325T-3FFG676E`).

The board pinout routes four SFP+ lanes through GTX bank 115 and one PCIe lane
through GTX bank 116. This build uses bank-115 channels 2 and 3 for 2x10GbE,
because those are the cages connected to fpga2 and fpga1 respectively.
The on-board 156.25 MHz differential reference clock drives the 10G PCS/PMA.
PCIe uses bank-116 channel 3 and its dedicated differential reference clock.

| Function | Package pins | GTX site |
|---|---|---|
| Logical lane 0 / SFP2 TX N/P | K1 / K2 | MGTXTXN/P2_115 |
| Logical lane 0 / SFP2 RX N/P | L3 / L4 | MGTXRXN/P2_115 |
| Logical lane 1 / SFP3 TX N/P | H1 / H2 | MGTXTXN/P3_115 |
| Logical lane 1 / SFP3 RX N/P | J3 / J4 | MGTXRXN/P3_115 |
| 156.25 MHz refclk N/P | H5 / H6 | MGTREFCLK0N/P_115 |
| PCIe TX0 N/P | A3 / A4 | MGTXTXN/P3_116 |
| PCIe RX0 N/P | B5 / B6 | MGTXRXN/P3_116 |
| PCIe refclk N/P | D5 / D6 | MGTREFCLK0N/P_116 |

Vivado 2026.1 cannot use the newer Ethernet 1/10/25G subsystem on Kintex-7, so
the project creates two AXI 10G Ethernet v3.1 instances. Logical lane 0/SFP2
contains the shared bank-115 QPLL/reset/clock logic and logical lane 1/SFP3
consumes it. Both expose the
64-bit, 156.25 MHz AXI-stream MAC interface used by `SmartNIC`.

Run `./build.sh` (or set `VIVADO_ROOT` first) to generate the CppHDL RTL,
recreate the project, and build `open_switch.bit` and `open_switch.bin`. The
current bring-up build instantiates `ProcessingStub`, not the CPU, and therefore
has no ELF-to-BRAM step. See `CLOCKING.md` for the clock tree and
optional Si5324 specification. `klusterlab_r2.xdc` is the active constraint file;
`klusterlab_pin_plan.xdc` is retained only as the original transceiver draft.
All ChipScope/ILA cores are disabled for the no-JTAG target.

The board has one proven FPGA-to-PC UART data output. FPGA A17 is schematic net
`UART_USB_RxD`; K15 (`UART_USB_TxD`) and B17 (`UART_USB_RTS`) are FPGA inputs,
and F18 drives active-low CTS low. ProcessingStub's 115200 8N1 `PLBK` probe
records every `net_clk` cycle and emits a 16 KiB framed/CRC-checked trace after
an accepted packet EOP. Run `uart_probe.py --wait-trigger` before injecting the
packet so the host waits for that hardware trigger.

The temporary `ProcessingStub` consumes the five-word receive descriptor,
issues the real RxRAM handle/length command, preserves backpressure and packet
boundaries, and writes each complete packet into TxFIFO `source_port XOR 1`.
Network raw-descriptor mode is forced for this image, so arbitrary valid
Ethernet frames are forwarded without requiring a parser-supported protocol.
This removes Tribe, its caches, DescriptorFetcher, PacketDMA, and boot firmware
from the elaborated image while retaining the complete Network storage path.

Current hardware scope is 2x10G packet loopback plus the disconnected PCIe/
System shell. DDR3 MIG is not instantiated.

## Validation status

The ProcessingStub channel-swap/backpressure/probe Verilator regression is
`fpga_processing_stub`; the host `PLBK` decoder is covered by
`fpga_uart_probe_host`. Consult the reports from the most recent build under
`fpga/build/` for implemented utilization and timing rather than the obsolete
CPU-image figures. The two 10G MAC/PCS instances use Design_Linking evaluation
licenses, so the generated bitstream is time-limited.
