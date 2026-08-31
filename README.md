# OpenSwitch2 2x10G SmartNIC

This branch targets the PCB Arts KlusterLab 2.0 board with an
`xc7k325tffg676-3` Kintex-7 FPGA.

The C++HDL design implements two 10GbE MAC-side interfaces, each
`64-bit @ 156.25 MHz`. The default board-bring-up image temporarily replaces
the Tribe CPU/PacketDMA Processing block with `rtl/processing/ProcessingStub.h`.
It reads every received packet through the real RxFIFO/RxRAM interfaces and
writes it to the opposite physical-port TxFIFO. Raw descriptor mode is enabled
so forwarding does not depend on recognizing a particular L3/L4 protocol. The PCIe/System shell remains
present but is disconnected from this packet loopback path.

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

## Building the Kintex-7 bitstream

The FPGA target is `xc7k325tffg676-3`. The supported build uses Vivado 2026.1
and creates the AXI 10G Ethernet, PCIe, and protocol-converter IP inside the
generated project. ChipScope/ILA is disabled because the target has no JTAG
connection. Make sure the Kintex-7 device files and those IP
cores are installed with Vivado.

The host also needs CMake 3.20 or newer and Python 3. No RISC-V firmware or
ELF-to-BRAM preparation is required for the default ProcessingStub image.

Configure the normal build tree from the repository root, then launch the FPGA
build from `fpga/`:

```sh
export VIVADO_ROOT=/tools/2026.1/Vivado

# Set this only when the license is not installed in Xilinx's default location.
export XILINXD_LICENSE_FILE=/root/Xilinx.lic

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cd fpga
./build.sh
```

To build the real Tribe/DescriptorFetcher/PacketDMA path instead, select CPU
mode. The build compiles `test/cpu_loopback.S`, converts its ELF load segment
to `fpga/build/cpu_loopback.mem`, and initializes the 128 KiB boot/scratch BRAM
before synthesis. Core 0 copies each packet coherently and transmits it on
`ingress XOR 1`; the other three harts park in `wfi`.

```sh
SMARTNIC_PROCESSING_MODE=cpu ./build.sh
```

`SMARTNIC_PROCESSING_MODE` accepts only `stub` (the default) or `cpu`.

Normal bitstreams honor received IEEE 802.3x PAUSE frames and generate PAUSE
independently for each ingress when its packet store crosses the hysteretic
watermark. For diagnosis of a peer with defective PAUSE behavior, reception
can be disabled at build time without changing source:

```sh
SMARTNIC_HONOR_RX_PAUSE=0 ./build.sh
```

This diagnostic setting is lossy if the downstream receiver cannot sustain
line rate and is not the default forwarding policy.

`VIVADO_ROOT` defaults to `/tools/2026.1/Vivado`, so its export can be omitted
on a machine using that installation. The CMake configure step prepares the
CppHDL converter in `cpphdl/build` when necessary. The two AXI 10G Ethernet
instances may use evaluation licenses, in which case Vivado produces a
time-limited bitstream.

The driver performs these steps in order:

1. Regenerates either ProcessingStub or the real Processing hierarchy, plus
   Network, System, and UARTProbe RTL from CppHDL C++ sources, then restores
   only the small synthesis-specific BRAM leaf primitives. CPU mode compiles
   and converts the boot ELF before Vivado reads the design.
2. Recreates `fpga/build/open_switch.xpr`, generates the Xilinx IP, and loads
   the KlusterLab pin and CDC constraints. The old build directory and output
   artifacts are deleted first so `build.sh` always performs a fresh build.
3. Runs synthesis, placement, routing, physical optimization, and bitstream
   generation.

Successful completion writes:

| File | Purpose |
|---|---|
| `fpga/open_switch.bit` | FPGA configuration bitstream |
| `fpga/open_switch.bin` | Raw configuration image |
| `fpga/build/utilization.rpt` | Implemented resource usage |
| `fpga/build/timing_summary.rpt` | Implemented timing results |
| `fpga/build/vivado.log` | Complete Vivado build log |

Bitstream generation does not by itself prove timing closure. Check WNS/TNS in
`fpga/build/timing_summary.rpt` before programming hardware.

The full SmartNIC image uses the on-board USB UART as a replacement for
ChipScope. FPGA ball A17 transmits and K15 receives at 115200 baud, 8 data
bits, no parity, and one stop bit. The stub image's `PLBK` probe runs on
`net_clk`, captures
one record every 6.4 ns, and automatically freezes/transmits the preceding
1024-cycle history after an incoming packet's EOP is accepted by the loopback
engine. While idle it transmits `UART_PROBE_READY` approximately once per
second. Start the host receiver before injecting a packet; `--wait-trigger`
deliberately sends neither RTS nor `DUMP`, so it cannot freeze an empty trace.

The CPU image uses schema `PCPU` and samples cumulative descriptor, RxRAM,
PacketDMA TX-word, and TX-packet counters every 100 us. It also records live
ready/valid state, DMA busy/error/reason, QPLL, and both PCS links. Because it
is a continuous circular capture, initiate its dump after traffic:

```sh
python3 fpga/uart_probe.py --port /dev/ttyUSB1 --timeout 30 \
    --output cpu_probe_dump.bin --text cpu_probe_dump.txt
```

For initial 10G bring-up, the much smaller
`fpga/diagnostics/uart_10g_probe.bit` image contains the same two 10G IP
instances and UART capture path without the CPU/PCIe/packet-storage logic. It
uses the same host command below and reports schema `ETHD`. This diagnostic
image is preferable when the full SmartNIC is still undergoing congestion or
timing repair.

For the main `open_switch.bit`, start a packet-triggered capture from the
confirmed USB port, then inject one Ethernet packet into either SFP+ port:

```sh
python3 fpga/uart_probe.py --port /dev/ttyUSB1 \
    --wait-trigger --timeout 60 \
    --output uart_probe_dump.bin --text uart_probe_dump.txt
```

For the standalone `ETHD` diagnostic image, initiate a dump immediately with
the UART/RTS command path:

```sh
python3 fpga/uart_probe.py --port /dev/ttyUSB1 \
    --output uart_probe_dump.bin --text
```

An existing binary capture can be converted without hardware. Supplying a
filename after `--text` writes the report there instead of standard output:

```sh
python3 fpga/uart_probe.py --input uart_probe_dump.bin \
    --text uart_probe_dump.txt
```

Each capture contains up to 1024 chronological 16-byte records followed by a
CRC32. `PLBK` records contain the low six packet bytes, RxRAM and both TxFIFO
ready/valid/SOP/EOP state, selected source/destination ports, stream word,
protocol error, and startup/QPLL/PCS/SFP/System health. The decoder summarizes
the channel swap and prints only active packet/engine samples. `ETHD` records
instead contain measured clocks, raw PCS/PMA status, and per-lane activity.
The generated RTL is sourced from `fpga/UART_PROBE.h`; its binary protocol and
host decoder are covered by the `fpga_uart_probe` and `fpga_uart_probe_host`
tests.

If Vivado was interrupted during placement or routing, `synth_1` is complete,
and no RTL, IP configuration, or synthesis constraint changed, implementation
can be restarted without recreating the project. Run this from the repository
root:

```sh
export VIVADO_ROOT=/tools/2026.1/Vivado
export LD_LIBRARY_PATH="$VIVADO_ROOT/lib/lnx64.o/SuSE${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$VIVADO_ROOT/bin/vivado" -mode batch \
    -source fpga/implement_current.tcl \
    -log fpga/build/implement_current.log \
    -journal fpga/build/implement_current.jou
```

If only handwritten RTL changed and the generated CppHDL/IP products remain
current, set `RESYNTHESIZE=1` for the same command. This resets top-level
synthesis before implementation while retaining the expensive IP products.

Run `fpga/build.sh` again instead when any source, generated RTL, IP setting,
or synthesis constraint has changed. Do not run two builds against
`fpga/build/open_switch.xpr` concurrently.
