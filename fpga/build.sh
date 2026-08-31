#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_root="${VIVADO_ROOT:-/tools/2026.1/Vivado}"
processing_mode="${SMARTNIC_PROCESSING_MODE:-stub}"
case "$processing_mode" in
    stub|cpu) ;;
    *)
        echo "SMARTNIC_PROCESSING_MODE must be 'stub' or 'cpu'" >&2
        exit 2
        ;;
esac
cmake -E rm -rf "$repo_dir/fpga/build"
mkdir -p "$repo_dir/fpga/build"
cmake -E rm -f \
    "$repo_dir/fpga/open_switch.bit" \
    "$repo_dir/fpga/open_switch.bin" \
    "$repo_dir/fpga/open_switch.ltx"
cmake -E rm -rf "$repo_dir/rtl/generated"
cmake -E make_directory "$repo_dir/rtl/generated"

# Keep the bundled compatibility libraries available to Vivado on newer Linux
# distributions.  This is harmless for 2026.1 and remains useful with 2022.2.
vivado_compat_lib="$vivado_root/lib/lnx64.o/SuSE"

if [[ "$processing_mode" == stub ]]; then
    # The proven hardware loopback image removes Tribe, caches and PacketDMA
    # while preserving the real RxRAM/TxFIFO path.
    "$repo_dir/cpphdl/build/cpphdl" \
        --generated-dir "$repo_dir/rtl/generated" \
        --primary_clock clk 156250000 \
        "$repo_dir/rtl/processing/ProcessingStub.h" \
        -I "$repo_dir/cpphdl/include" \
        -I "$repo_dir/rtl/processing" \
        -I "$repo_dir/rtl/network" \
        -I "$repo_dir/fpga" \
        -I "$repo_dir"
else
    # Real one-cluster/four-hart Processing image. Core 0 boots from BRAM and
    # controls DescriptorFetcher plus PacketDMA through uncached AXI MMIO.
    "$repo_dir/cpphdl/build/cpphdl" \
        --generated-dir "$repo_dir/rtl/generated" \
        --primary_clock clk 156250000 \
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

    cmake --build "$repo_dir/build" --target cpu_loopback_firmware
    python3 "$repo_dir/fpga/elf_to_bram.py" \
        "$repo_dir/build/test/cpu_loopback.elf" \
        "$repo_dir/fpga/build/cpu_loopback.mem" \
        --size 131072 --word-bytes 32
fi

# ProcessingStub includes descriptor types through RxFifo/PacketParser, so its
# conversion also emits clock-specialized copies of several Network modules.
# Generate Network in isolation and copy it over the shared tree afterward;
# otherwise those incidental clk/l2_clock definitions can survive and conflict
# with the net_clk/l2_clk bindings in SmartNIC.
network_generated_dir="$repo_dir/fpga/build/generated_network"
cmake -E rm -rf "$network_generated_dir"
cmake -E make_directory "$network_generated_dir"
"$repo_dir/cpphdl/build/cpphdl" \
    --generated-dir "$network_generated_dir" \
    --primary_clock net_clk 156250000 \
    --secondary_clock l2_clk 156250000 \
    "$repo_dir/rtl/SmartNIC.h" \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/rtl/common" \
    -I "$repo_dir/rtl/network" \
    -I "$repo_dir/rtl" \
    -I "$repo_dir"
cmake -E copy_directory "$network_generated_dir" "$repo_dir/rtl/generated"
"$repo_dir/cpphdl/build/cpphdl" \
    --generated-dir "$repo_dir/rtl/generated" \
    --primary_clock l2_clock 156250000 \
    --secondary_clock system_clock 125000000 \
    "$repo_dir/rtl/system/System.h" \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/cpphdl/tribe_cpu/common" \
    -I "$repo_dir/rtl/common" \
    -I "$repo_dir/rtl/system" \
    -I "$repo_dir"

# Preserve the two deliberately small storage primitives after conversion.
# The converter owns every surrounding control module; only these inferred
# BRAM leaves are specialized for Vivado.
cmake -E copy_if_different \
    "$repo_dir/rtl/common/SmartNicMemoryPrimitive.sv" \
    "$repo_dir/rtl/generated/SmartNicMemory.sv"
cmake -E copy_if_different \
    "$repo_dir/rtl/common/SmartNicRAMPrimitive.sv" \
    "$repo_dir/rtl/generated/SmartNicRAM.sv"
cmake -E copy_if_different \
    "$repo_dir/rtl/common/TxEopMemoryPrimitive.sv" \
    "$repo_dir/rtl/generated/TxEopMemory.sv"
cmake -E copy_if_different \
    "$repo_dir/rtl/common/SystemMemoryPrimitive.sv" \
    "$repo_dir/rtl/generated/SystemMemory.sv"

# Generate the command-driven UART logic analyzer from its CppHDL source.
# This replaces ChipScope on boards where the JTAG pins are not accessible.
"$repo_dir/cpphdl/build/cpphdl" \
    --generated-dir "$repo_dir/rtl/generated" \
    "$repo_dir/fpga/UART_PROBE.h" \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/fpga"
cmake -E copy_if_different \
    "$repo_dir/fpga/rtl/UARTProbeMemoryPrimitive.sv" \
    "$repo_dir/rtl/generated/UARTProbeMemory.sv"

if [[ "${SMARTNIC_PREPARE_ONLY:-0}" == 1 ]]; then
    echo "Prepared generated RTL for SMARTNIC_PROCESSING_MODE=$processing_mode"
    exit 0
fi

export LD_LIBRARY_PATH="$vivado_compat_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SMARTNIC_PROCESSING_MODE="$processing_mode"
exec "$vivado_root/bin/vivado" -mode batch -source "$repo_dir/fpga/build.tcl" \
    -log "$repo_dir/fpga/build/vivado.log" \
    -journal "$repo_dir/fpga/build/vivado.jou"
