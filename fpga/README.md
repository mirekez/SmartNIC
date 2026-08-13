# KlusterLab r2.0 Kintex-7 target

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

Vivado 2024.2 cannot use the newer Ethernet 1/10/25G subsystem on Kintex-7, so
the project creates two AXI 10G Ethernet v3.1 instances. Lane 0 contains the
shared bank-115 QPLL/reset/clock logic and lane 1 consumes it. Both expose the
64-bit, 156.25 MHz AXI-stream MAC interface used by `SmartNIC`.

Run `./build.sh` (or set `VIVADO_ROOT` first) to recreate the project and build
`open_switch.bit`. See `CLOCKING.md` for the clock tree and optional Si5324
specification. `klusterlab_r2.xdc` is the active constraint file;
`klusterlab_pin_plan.xdc` is retained only as the original transceiver draft.

The FPGA profile uses 2 KiB instruction and 1 KiB data L1 caches per core and
a shared 64 KiB, four-way L2 (four 9 KiB jumbo frames plus 28 KiB reserve).
RV32 atomics, interrupt routing, and Sv32 MMU/TLB logic are disabled. To keep
Vivado synthesis practical on memory-limited build hosts, the bounded parser
captures 192 header bytes and accepts up to four IPv6 extension headers / 96
extension bytes; this does not limit packet or jumbo-frame payload length.
The FPGA files substitute `rtl/PacketParser_fpga.sv` at the same module
boundary because Vivado 2024.2 exhausts a 10 GiB host while elaborating the
CppHDL parser's unrolled functions. The compact implementation queues the
first 64 bytes and preserves RAW/framing signals; parsed metadata is
provisional until that parser is rewritten as a pipelined datapath.

Current hardware scope is 2x10G plus Processing. The board's PCIe pins and
clock are documented below, but the PCIe endpoint/System AXI bridge and the
DDR3 MIG are not instantiated by this top level yet; consequently the CPU's
external-memory AXI port is held in backpressure. Do not treat this bitstream
as bootable firmware until those two board subsystems are integrated.

## Validation status

The normal CMake build completes, including CppHDL generation and Verilator
lint of the two-clock SmartNIC. Vivado 2024.2 isolated synthesis confirms that
the shared L2 maps to 36 RAMB18 primitives and that the banked NIC buffering
maps to block RAM. Full-project synthesis repeatedly passed RTL elaboration
and netlist optimization, then the Linux OOM handler killed Vivado while it was
initializing the timing engine on this 10 GiB VM with exhausted swap. Therefore
`open_switch.bit` is not committed; rerun `./build.sh` on a host with more
memory to complete implementation and bitstream generation.
