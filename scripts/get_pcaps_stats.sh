#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
VM_INFO_DIR="$SCRIPT_DIR/../vm_info"
MAX_SECONDS="${MAX_SECONDS:-30}"

ROOT_DIR="$SCRIPT_DIR/../traffic"
OUT_DIR="$SCRIPT_DIR"
OUT_FILE="pcap_results_$(date +%Y%m%d_%H%M%S).csv"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --outdir)  OUT_DIR="$2";  shift 2 ;;
        --outfile) OUT_FILE="$2"; shift 2 ;;
        -*) echo "Unknown option: $1"; echo "Usage: $0 [traffic_dir] [--outdir <dir>] [--outfile <filename.csv>]"; exit 1 ;;
        *)  ROOT_DIR="$1"; shift ;;
    esac
done

if ! command -v tshark >/dev/null 2>&1; then
    echo "Error: tshark is not installed or not in PATH" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed or not in PATH" >&2
    exit 1
fi

if command -v timeout >/dev/null 2>&1; then
    TSHARK_TIMEOUT=(timeout "${MAX_SECONDS}s")
else
    TSHARK_TIMEOUT=()
fi

if [ ! -d "$ROOT_DIR" ]; then
    echo "Error: directory '$ROOT_DIR' does not exist" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
CSV_OUT="$OUT_DIR/$OUT_FILE"

# Wrap a value in CSV double-quotes, escaping internal double-quotes
csv_field() { printf '"%s"' "${1//\"/\"\"}"; }

# Find the vm_info JSON whose traffic_folder basename matches the given folder name
find_vm_info() {
    local folder_name="$1"
    local json_file tf
    for json_file in "$VM_INFO_DIR"/*.json; do
        [[ -f "$json_file" ]] || continue
        tf=$(jq -r '.traffic_folder // ""' "$json_file" 2>/dev/null)
        [[ "${tf##*/}" == "$folder_name" ]] && { echo "$json_file"; return; }
    done
}

echo "vm_name,Os_Family,Os_Type,Os_Version,pcap_date,pcap_duration_s,packet_count,pcap_size,protocols" > "$CSV_OUT"

shopt -s nullglob

for folder in "$ROOT_DIR"/*/; do
    [[ -d "$folder" ]] || continue
    folder_name=$(basename "$folder")

    vm_name="$folder_name"
    Os_Family=""; Os_Type=""; Os_Version=""

    json_file=$(find_vm_info "$folder_name")
    if [[ -n "$json_file" ]]; then
        vm_name=$(jq -r   '.vm_name   // ""' "$json_file")
        Os_Family=$(jq -r '.os_family // ""' "$json_file")
        Os_Type=$(jq -r   '.os_type   // ""' "$json_file")
        Os_Version=$(jq -r '.os_version // ""' "$json_file")
    fi

    echo "[*] $folder_name  →  vm: $vm_name  Os_Family: ${Os_Family:-?}  Os_Type: ${Os_Type:-?}  Os_Version: ${Os_Version:-?}"

    mapfile -t pcap_files < <(find "$folder" -type f -iname '*.pcap' | sort)
    if [[ ${#pcap_files[@]} -eq 0 ]]; then
        echo "    (no pcap files)"
        echo
        continue
    fi

    for pcap in "${pcap_files[@]}"; do
        [[ -f "$pcap" ]] || continue

        pcap_file=$(basename "$pcap")
        pcap_size=$(stat -c '%s' "$pcap" 2>/dev/null | awk '{
            if ($1 < 1048576) printf "%.2f KB", $1/1024
            else              printf "%.2f MB", $1/1048576
        }')

        echo "    [*] $pcap_file  (${pcap_size:-?})"

        stats_output="$(${TSHARK_TIMEOUT[@]} tshark -r "$pcap" -n -q -z io,phs 2>/dev/null)"
        if [[ $? -ne 0 ]] || [[ -z "$stats_output" ]]; then
            echo "        [!] Could not read, empty, or tshark timed out"
            continue
        fi

        # Per-protocol frame counts with hierarchy path notation: "ip/tcp(396464), ip/tcp/tls(6994), ..."
        # Excludes eth, tcp.segments, and _ws.* pseudo-protocols. Sorted by frame count descending.
        protocols=$(printf '%s\n' "$stats_output" | \
            sed -n '/Protocol Hierarchy Statistics/,/^===\+/p' | \
            sed '1d;$d;/^Filter:/d;/^[[:space:]]*$/d' | \
            awk '
            BEGIN { max_depth = 20; exclude_from = -1 }
            {
                spaces = 0
                for (i = 1; i <= length($0); i++) {
                    if (substr($0, i, 1) == " ") spaces++
                    else break
                }
                depth = spaces / 2

                proto = $1
                if (proto == "") next
                match($0, /frames:([0-9]+)/, arr)
                frames = arr[1]+0
                if (frames == 0) next

                if (exclude_from >= 0 && depth <= exclude_from) exclude_from = -1

                stack[depth] = proto
                for (i = depth+1; i <= max_depth; i++) delete stack[i]

                if (depth == 0) next

                if (proto == "tcp.segments" || proto ~ /^_ws\./) {
                    exclude_from = depth
                    next
                }

                if (exclude_from >= 0 && depth > exclude_from) next

                path = ""
                for (i = 1; i <= depth; i++) {
                    if (i in stack && stack[i] != "") {
                        path = (path == "") ? stack[i] : path "/" stack[i]
                    }
                }

                if (!(path in seen)) {
                    seen[path] = 1
                    paths[++np] = path
                    frame_counts[path] = frames
                }
            }
            END {
                for (i = 2; i <= np; i++) {
                    key = paths[i]; kc = frame_counts[key]
                    j = i - 1
                    while (j >= 1 && frame_counts[paths[j]] < kc) {
                        paths[j+1] = paths[j]; j--
                    }
                    paths[j+1] = key
                }
                result = ""
                for (i = 1; i <= np; i++) {
                    p = paths[i]
                    result = result p "(" frame_counts[p] "), "
                }
                if (length(result) > 2) print substr(result, 1, length(result)-2)
            }')

        # Capture timestamps, duration, and total packet count (one pass over frame epochs)
        times_output="$(${TSHARK_TIMEOUT[@]} tshark -r "$pcap" -n -T fields -e frame.time_epoch 2>/dev/null)"
        read -r start_epoch end_epoch duration packet_count <<< "$(printf '%s\n' "$times_output" | awk '
            NF {
                count++
                if (min == "" || $1 < min) min = $1
                if (max == "" || $1 > max) max = $1
            }
            END {
                if (max != "") printf "%s %s %s %d", min, max, (max-min), count
            }')"

        pcap_date=$(basename "$(dirname "$pcap")" | grep -oP '^\d{4}-\d{2}-\d{2}')
        pcap_duration=""
        if [[ -n "${start_epoch:-}" ]]; then
            pcap_duration=$(awk -v d="$duration" 'BEGIN { printf "%.3f", d }')
        fi

        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$(csv_field "$vm_name")" \
            "$(csv_field "$Os_Family")" \
            "$(csv_field "$Os_Type")" \
            "$(csv_field "$Os_Version")" \
            "$(csv_field "${pcap_date:-}")" \
            "$(csv_field "${pcap_duration:-}")" \
            "$(csv_field "${packet_count:-}")" \
            "$(csv_field "${pcap_size:-}")" \
            "$(csv_field "${protocols:-}")" >> "$CSV_OUT"
    done

    echo
done

echo "[*] CSV saved to $CSV_OUT"
