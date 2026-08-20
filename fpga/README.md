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

Vivado 2022.2 cannot use the newer Ethernet 1/10/25G subsystem on Kintex-7, so
the project creates two AXI 10G Ethernet v3.1 instances. Lane 0 contains the
shared bank-115 QPLL/reset/clock logic and lane 1 consumes it. Both expose the
64-bit, 156.25 MHz AXI-stream MAC interface used by `SmartNIC`.

Run `./build.sh` (or set `VIVADO_ROOT` first) to rebuild `capture.elf`, convert
its loadable segments into the 256-bit `build/capture.mem` image, recreate the
project, and build `open_switch.bit`, `open_switch.bin`, and the matching
`open_switch.ltx` ILA probe map. A 64 KiB initialized AXI block RAM at
address zero supplies the CPU reset image until a program-loading protocol and
external memory are integrated. See `CLOCKING.md` for the clock tree and
optional Si5324 specification. `klusterlab_r2.xdc` is the active constraint file;
`klusterlab_pin_plan.xdc` is retained only as the original transceiver draft.

The FPGA profile uses 2 KiB instruction and 1 KiB data L1 caches per core and
a shared 64 KiB, four-way L2 (four 9 KiB jumbo frames plus 28 KiB reserve).
RV32 atomics, interrupt routing, and Sv32 MMU/TLB logic are disabled. The
bounded parser captures 192 header bytes and accepts up to four IPv6 extension
headers / 96 extension bytes; this does not limit packet or jumbo-frame payload
length. The FPGA project uses `PacketParser.sv` generated directly from
`rtl/network/PacketParser.h`, so hardware and native CppHDL/Verilator tests
share the complete parser implementation.

Current hardware scope is 2x10G plus Processing. The board's PCIe pins and
clock are documented below, but the PCIe endpoint/System AXI bridge and the
DDR3 MIG are not instantiated by this top level yet. The CPU can execute the
embedded capture worker from boot BRAM, but it has no general-purpose external
memory beyond that 64 KiB window.

## Validation status

The normal CMake build completes, including CppHDL generation, Verilator lint,
and all 18 tests (including sustained 2x10G capture). Vivado 2022.2 completes
synthesis, placement, routing, DRC, and bitstream generation. The implemented
design occupies 89,282 LUTs and routes with no failed or unrouted nets. It does
not yet meet setup timing: the final report has -29.576 ns overall WNS, with
-28.643 ns in the 156.25 MHz Ethernet/system clock domain. The current image is
therefore a lab/debug artifact, not a timing-closed production image. The AXI
10G Ethernet IP also reports a design-linking/evaluation license warning.
