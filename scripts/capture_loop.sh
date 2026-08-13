#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
START_SCRIPT="$SCRIPT_DIR/start_vm.sh"

user="vmuser"
poll_interval=10

RANGES=()
START_ARGS=()
HAS_TIME=false

usage() {
    echo "Usage: $0 --ranges N-M[,N-M...] -t|--time N (-m|-s|-H|-d) [-w|--wait SECONDS] [-g|--graphic] [-h|--help]"
    echo ""
    echo "  --ranges       Comma-separated list of VM ranges to process"
    echo "  -t, --time     Time to capture traffic before each VM auto-stops"
    echo "  -m, --minutes  Given time is in minutes (default)"
    echo "  -s, --seconds  Given time is in seconds"
    echo "  -H, --hours    Given time is in hours"
    echo "  -d, --days     Given time is in days"
    echo "  -w, --wait     Seconds to wait between starting each VM within a batch"
    echo "  -g, --graphic  Start VMs in graphic mode"
    echo "  -h, --help     Show this help"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ranges)     IFS=',' read -r -a RANGES <<< "$2"; shift 2 ;;
        -t|--time)    HAS_TIME=true; START_ARGS+=(-t "$2"); shift 2 ;;
        -m|--minutes) START_ARGS+=(-m); shift ;;
        -s|--seconds) START_ARGS+=(-s); shift ;;
        -H|--hours)   START_ARGS+=(-H); shift ;;
        -d|--days)    START_ARGS+=(-d); shift ;;
        -w|--wait)    START_ARGS+=(-w "$2"); shift 2 ;;
        -g|--graphic) START_ARGS+=(-g); shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
done

if [ "${#RANGES[@]}" -eq 0 ]; then
    echo "Error: --ranges is required."
    usage
fi

if [ "$HAS_TIME" = false ]; then
    echo "Error: -t|--time is required."
    usage
fi

for range in "${RANGES[@]}"; do
    echo "========================================================"
    echo "  BATCH: VMs $range"
    echo "========================================================"

    # Resolve this batch's own VM names so we only wait on them, not on VMs from other batches
    all_vms=$(su - "$user" -c "vboxmanage list vms" | awk -F'"' '{print $2}')
    mapfile -t all_vms_array <<< "$all_vms"
    if [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        range_start=${BASH_REMATCH[1]}
        range_end=${BASH_REMATCH[2]}
        batch_vms=("${all_vms_array[@]:$((range_start - 1)):$((range_end - range_start + 1))}")
    else
        IFS=',' read -r -a batch_vms <<< "$range"
    fi

    echo "[*] Starting VMs $range with traffic capture ..."
    bash "$START_SCRIPT" "$range" "${START_ARGS[@]}"

    echo "[*] Waiting for VMs $range to finish capturing and auto-stop ..."
    batch_running=true
    while $batch_running; do
        batch_running=false
        running_vms=$(su - "$user" -c "vboxmanage list runningvms")
        for vm in "${batch_vms[@]}"; do
            if grep -q "\"$vm\"" <<< "$running_vms"; then
                batch_running=true
                break
            fi
        done
        [ "$batch_running" = true ] && sleep "$poll_interval"
    done

    echo "[*] Batch $range complete."
    echo ""
done

echo "========================================================"
echo "  All batches complete."
echo "========================================================"
