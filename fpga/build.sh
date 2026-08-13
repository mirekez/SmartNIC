#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_root="${VIVADO_ROOT:-/home/me/Xilinx/Vivado/2024.2}"
mkdir -p "$repo_dir/fpga/build"
exec "$vivado_root/bin/vivado" -mode batch -source "$repo_dir/fpga/build.tcl" \
    -log "$repo_dir/fpga/build/vivado.log" \
    -journal "$repo_dir/fpga/build/vivado.jou"
