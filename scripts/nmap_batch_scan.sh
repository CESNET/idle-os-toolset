#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
NMAP_SCRIPT="$SCRIPT_DIR/nmap.sh"
START_SCRIPT="$SCRIPT_DIR/boot_vm.sh"
STOP_SCRIPT="$SCRIPT_DIR/shutdown_vm.sh"

NMAP_OUT_BASE="$SCRIPT_DIR/../nmap"
BOOT_WAIT=30

usage() {
    echo "Usage: $0 --ranges N-M[,N-M...] [--wait SECONDS]"
    echo ""
    echo "  --ranges  Comma-separated list of VM ranges to process (required)"
    echo "  --wait    Seconds to wait after starting VMs before scanning (default: $BOOT_WAIT)"
    echo "  -h, --help  Show this help"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ranges) IFS=',' read -r -a RANGES <<< "$2"; shift 2 ;;
        --wait)   BOOT_WAIT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
done

if [[ -z "${RANGES+x}" ]]; then
    echo "Error: --ranges is required"
    usage
fi

for range in "${RANGES[@]}"; do
    echo "========================================================"
    echo "  BATCH: VMs $range"
    echo "========================================================"

    mkdir -p "$NMAP_OUT_BASE"

    echo "[*] Starting VMs $range ..."
    bash "$START_SCRIPT" "$range"

    echo "[*] Waiting ${BOOT_WAIT}s for VMs to boot ..."
    sleep "$BOOT_WAIT"


    out_file="nmap_results_${range//-/_}_$(date +%Y%m%d_%H%M%S).csv"
    bash "$NMAP_SCRIPT" --outdir "$NMAP_OUT_BASE" --outfile "$out_file"


    echo ""
    echo "[*] Shutting down all VMs ..."
    bash "$STOP_SCRIPT" all

    echo "[*] Batch $range complete. Results in: $NMAP_OUT_BASE/$out_file"
    echo ""
done

echo "========================================================"
echo "  All batches complete."
echo "  Results in: $NMAP_OUT_BASE"
echo "========================================================"
