#!/usr/bin/env bash
set -euo pipefail

fpga_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$fpga_dir/.." && pwd)"
configuration="400g"
output_dir=""

usage() {
    printf '%s\n' \
        "Usage: $0 [--config 400g|800g] [--output DIR]" \
        "" \
        "Build the CppHDL converter and generate the complete SmartNIC RTL." \
        "The default output is fpga/build/<config>/generated."
}

while (($#)); do
    case "$1" in
        --config)
            configuration="${2:?missing value for --config}"
            shift 2
            ;;
        --output)
            output_dir="${2:?missing value for --output}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$configuration" in
    400g)
        primary_clock=(net_clk 312500000)
        secondary_clock=(l2_clk 312500000)
        enable_800g=0
        ;;
    800g)
        primary_clock=(l2_clk 390625000)
        secondary_clock=(net_clk 312500000)
        enable_800g=1
        ;;
    *)
        printf 'Configuration must be 400g or 800g, got %s\n' \
            "$configuration" >&2
        exit 2
        ;;
esac

if [[ -z "$output_dir" ]]; then
    output_dir="$fpga_dir/build/$configuration/generated"
fi
mkdir -p "$output_dir"

if [[ -x "$repo_dir/cpphdl/.conda/bin/cmake" ]]; then
    cmake_bin="$repo_dir/cpphdl/.conda/bin/cmake"
else
    cmake_bin="${CMAKE:-cmake}"
fi

converter="$repo_dir/cpphdl/build/cpphdl"
if [[ ! -f "$repo_dir/cpphdl/build/CMakeCache.txt" ]]; then
    "$cmake_bin" -S "$repo_dir/cpphdl" -B "$repo_dir/cpphdl/build"
fi
"$cmake_bin" --build "$repo_dir/cpphdl/build" --target cpphdl --parallel

"$converter" \
    --generated-dir "$output_dir" \
    --primary_clock "${primary_clock[0]}" "${primary_clock[1]}" \
    --secondary_clock "${secondary_clock[0]}" "${secondary_clock[1]}" \
    "$repo_dir/rtl/SmartNIC.h" \
    "-DENABLE_800G=$enable_800g" \
    -I "$repo_dir/cpphdl/include" \
    -I "$repo_dir/rtl/common" \
    -I "$repo_dir/rtl/network" \
    -I "$repo_dir/rtl" \
    -I "$repo_dir"

printf 'SMARTNIC_GENERATED_RTL=%s\n' "$output_dir"

