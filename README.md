# OpenSwitch2 2x10G SmartNIC

This branch targets the PCB Arts KlusterLab 2.0 board with an
`xc7k325tffg676-3` Kintex-7 FPGA.

The C++HDL design implements two 10GbE MAC-side interfaces, each
`64-bit @ 156.25 MHz`. Network and the single Tribe processing cluster share
that clock and use synchronous packet-width converters. The System block has
one RX/TX queue pair and crosses to a `64-bit @ 125 MHz` PCIe Gen2 x1 host
interface.

The board reference material is in the
[PCB Arts hardware repository](https://github.com/PCB-Arts/fast-open-switch-hardware).
The 10G PCS dependency follows the approach documented by
[ZipCPU](https://zipcpu.com/blog/2023/11/25/eth10g.html).

Build and test:

```sh
cmake -S . -B build
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

Generated SystemVerilog is written under the build tree by each RTL target and
mirrored in `rtl/generated`. FPGA integration notes and the verified board pin
plan are in `fpga/`.
