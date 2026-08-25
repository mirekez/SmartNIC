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

## Building the Kintex-7 bitstream

The FPGA target is `xc7k325tffg676-3`. The supported build uses Vivado 2026.1
and creates the AXI 10G Ethernet, PCIe, protocol-converter, and system ILA IP
inside the generated project. Make sure the Kintex-7 device files and those IP
cores are installed with Vivado.

The host also needs CMake 3.20 or newer and Python 3. A
`riscv32-unknown-elf-gcc` toolchain may be supplied through `PATH` or
`RISCV_HOME`; when it is absent, the CMake configuration uses the RISC-V
Clang/LLD toolchain prepared with CppHDL.

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

`VIVADO_ROOT` defaults to `/tools/2026.1/Vivado`, so its export can be omitted
on a machine using that installation. The CMake configure step prepares the
CppHDL converter in `cpphdl/build` when necessary. A Vivado Basic license is
enough for the single packed system ILA used by this project; the two AXI 10G
Ethernet instances may use evaluation licenses, in which case Vivado produces
a time-limited bitstream.

The driver performs these steps in order:

1. Regenerates Processing, Network, and System RTL from the CppHDL C++ sources
   into `rtl/generated` and restores the small inferred-BRAM primitives.
2. Builds `build/test/capture.elf` and converts all loadable ELF segments into
   `fpga/build/capture.mem`. This step is mandatory: there is no CPU program
   loading protocol yet, so the capture program must be present in boot BRAM
   when the FPGA leaves reset.
3. Recreates `fpga/build/open_switch.xpr`, generates the Xilinx IP, and loads
   the KlusterLab pin and CDC constraints.
4. Runs synthesis, placement, routing, physical optimization, and bitstream
   generation.

Successful completion writes:

| File | Purpose |
|---|---|
| `fpga/open_switch.bit` | FPGA configuration bitstream |
| `fpga/open_switch.bin` | Raw configuration image |
| `fpga/open_switch.ltx` | Probe map for the system-clock ILA |
| `fpga/build/utilization.rpt` | Implemented resource usage |
| `fpga/build/timing_summary.rpt` | Implemented timing results |
| `fpga/build/vivado.log` | Complete Vivado build log |

Bitstream generation does not by itself prove timing closure. Check WNS/TNS in
`fpga/build/timing_summary.rpt` before programming hardware.

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

Run `fpga/build.sh` again instead when any source, generated RTL, IP setting,
or synthesis constraint has changed. Do not run two builds against
`fpga/build/open_switch.xpr` concurrently.
