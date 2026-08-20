#!/usr/bin/env bash
set -euo pipefail

fpga_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
configuration="400g"
flow_mode="synth"
part_name="xcu250-figd2104-2L-e"
jobs="${SMARTNIC_VIVADO_JOBS:-4}"
bank_depth="8192"
rx_fifo_depth="64"
tx_fifo_words="1024"
synthesis_directive="RuntimeOptimized"
build_root="$fpga_dir/build"
skip_generate=0

usage() {
    printf '%s\n' \
        "Usage: $0 [options]" \
        "" \
        "Options:" \
        "  --config 400g|800g|both   SmartNIC configuration (default: 400g)" \
        "  --mode synth|route         Stop after synthesis or route OOC core" \
        "  --part PART                Xilinx part (default: xcu250-figd2104-2L-e)" \
        "  --jobs N                   Vivado worker threads (default: 4)" \
        "  --bank-depth N             RxRAM bank depth (default: 8192)" \
        "  --rx-fifo-depth N          Receive FIFO depth (default: 64)" \
        "  --tx-fifo-words N          Per-stream TX FIFO words (default: 1024)" \
        "  --synth-directive NAME     Vivado synthesis directive" \
        "                             (default: RuntimeOptimized)" \
        "  --build-dir DIR            Artifact root (default: fpga/build)" \
        "  --skip-generate            Reuse existing generated SystemVerilog" \
        "  -h, --help                  Show this help" \
        "" \
        "Set VIVADO_ROOT to override /tools/Xilinx/Vivado/2022.2."
}

while (($#)); do
    case "$1" in
        --config) configuration="${2:?missing value for --config}"; shift 2 ;;
        --mode) flow_mode="${2:?missing value for --mode}"; shift 2 ;;
        --part) part_name="${2:?missing value for --part}"; shift 2 ;;
        --jobs) jobs="${2:?missing value for --jobs}"; shift 2 ;;
        --bank-depth) bank_depth="${2:?missing value for --bank-depth}"; shift 2 ;;
        --rx-fifo-depth) rx_fifo_depth="${2:?missing value for --rx-fifo-depth}"; shift 2 ;;
        --tx-fifo-words) tx_fifo_words="${2:?missing value for --tx-fifo-words}"; shift 2 ;;
        --synth-directive) synthesis_directive="${2:?missing value for --synth-directive}"; shift 2 ;;
        --build-dir) build_root="${2:?missing value for --build-dir}"; shift 2 ;;
        --skip-generate) skip_generate=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$configuration" in
    400g|800g) configurations=("$configuration") ;;
    both) configurations=(400g 800g) ;;
    *) printf 'Invalid --config: %s\n' "$configuration" >&2; exit 2 ;;
esac
case "$flow_mode" in
    synth|route) ;;
    *) printf 'Invalid --mode: %s\n' "$flow_mode" >&2; exit 2 ;;
esac
for numeric_value in "$jobs" "$bank_depth" "$rx_fifo_depth" "$tx_fifo_words"; do
    if [[ ! "$numeric_value" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Jobs and size parameters must be positive integers: %s\n' \
            "$numeric_value" >&2
        exit 2
    fi
done

vivado_root="${VIVADO_ROOT:-/tools/Xilinx/Vivado/2022.2}"
if [[ -x "$vivado_root/bin/vivado" ]]; then
    vivado_bin="$vivado_root/bin/vivado"
elif command -v vivado >/dev/null 2>&1; then
    vivado_bin="$(command -v vivado)"
else
    printf 'Vivado was not found. Set VIVADO_ROOT or add vivado to PATH.\n' >&2
    exit 1
fi

compat_lib="$vivado_root/lib/lnx64.o/SuSE"
if [[ -d "$compat_lib" ]]; then
    export LD_LIBRARY_PATH="$compat_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

for selected_config in "${configurations[@]}"; do
    config_dir="$build_root/$selected_config"
    generated_dir="$config_dir/generated"
    report_dir="$config_dir/$flow_mode"
    mkdir -p "$generated_dir" "$report_dir"

    if ((skip_generate == 0)); then
        "$fpga_dir/generate_rtl.sh" \
            --config "$selected_config" --output "$generated_dir"
    fi

    (
        cd "$report_dir"
        "$vivado_bin" -mode batch -notrace \
            -source "$fpga_dir/build.tcl" \
            -log "$report_dir/vivado.log" \
            -journal "$report_dir/vivado.jou" \
            -tclargs "$generated_dir" "$selected_config" "$report_dir" \
            "$part_name" "$flow_mode" "$jobs" "$bank_depth" \
            "$rx_fifo_depth" "$tx_fifo_words" "$synthesis_directive"
    )
done

printf 'SmartNIC %s build complete under %s\n' "$flow_mode" "$build_root"
