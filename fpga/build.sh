#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_root="${VIVADO_ROOT:-/tools/Xilinx/Vivado/2022.2}"
mkdir -p "$repo_dir/fpga/build"

# Vivado 2022.2's Ubuntu loader omits the bundled ncurses5 compatibility
# directory on newer distributions, although librdi_commontasks still needs it.
vivado_compat_lib="$vivado_root/lib/lnx64.o/SuSE"

# Keep the FPGA source set reproducible from the CppHDL implementation.  The
# only annotated replacements reached by these conversions are small inferred
# RAM/storage leaf primitives; all control and packet-processing blocks remain
# generated from their C++ modules.
"$repo_dir/cpphdl/build/cpphdl" \
    --generated-dir "$repo_dir/rtl/generated" \
    --primary_clock clk 312500000 \
    --secondary_clock l2_clock 156250000 \
    "$repo_dir/rtl/processing/Processing.h" \
    -DMULTICORE \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/cpphdl/tribe_cpu" \
    -I "$repo_dir/cpphdl/tribe_cpu/common" \
    -I "$repo_dir/cpphdl/tribe_cpu/spec" \
    -I "$repo_dir/cpphdl/tribe_cpu/cache" \
    -I "$repo_dir/cpphdl/tribe_cpu/devices" \
    -I "$repo_dir/rtl/processing" \
    -I "$repo_dir"
"$repo_dir/cpphdl/build/cpphdl" \
    --generated-dir "$repo_dir/rtl/generated" \
    --primary_clock net_clk 156250000 \
    --secondary_clock l2_clk 156250000 \
    "$repo_dir/rtl/SmartNIC.h" \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/rtl/common" \
    -I "$repo_dir/rtl/network" \
    -I "$repo_dir/rtl" \
    -I "$repo_dir"

# Until a host-side program loader exists, the CPU must see executable code at
# address zero on its very first cache fill.  Rebuild the RV32 capture worker
# and turn its ELF PT_LOAD segments into the 256-bit words used by boot BRAM.
cmake --build "$repo_dir/build" --target capture_firmware
python3 "$repo_dir/fpga/elf_to_bram.py" \
    "$repo_dir/build/test/capture.elf" \
    "$repo_dir/fpga/build/capture.mem" \
    --size 65536 --word-bytes 32

export LD_LIBRARY_PATH="$vivado_compat_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$vivado_root/bin/vivado" -mode batch -source "$repo_dir/fpga/build.tcl" \
    -log "$repo_dir/fpga/build/vivado.log" \
    -journal "$repo_dir/fpga/build/vivado.jou"
