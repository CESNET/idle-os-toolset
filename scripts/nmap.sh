#!/bin/bash

INTERFACE="vboxnet0"
VMUSER="vmuser"
VM_INFO_DIR="$(dirname "$(realpath "$0")")/../vm_info"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OUT_DIR="$SCRIPT_DIR/../nmap"
OUT_FILE="nmap_results_$(date +%Y%m%d_%H%M%S).csv"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --outdir)  OUT_DIR="$2";  shift 2 ;;
        --outfile) OUT_FILE="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; echo "Usage: $0 [--outdir <dir>] [--outfile <filename.csv>]"; exit 1 ;;
    esac
done

mkdir -p "$OUT_DIR"
CSV_OUT="$OUT_DIR/$OUT_FILE"

# Wrap a value in CSV double-quotes, escaping internal double-quotes
csv_field() { printf '"%s"' "${1//\"/\"\"}"; }

# Format raw VBoxManage MAC (0800275BE4C1) → 08:00:27:5B:E4:C1
format_mac() {
    echo "$1" | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/'
}

# Extract the best OS fingerprint from nmap output
# Priority: OS details > Aggressive guesses > TCP/IP fingerprint > No OS matches
extract_nmap_fingerprint() {
    local out="$1"
    local result

    result=$(echo "$out" | grep -oP '(?<=OS details: ).+')
    [[ -n "$result" ]] && { echo "$result"; return; }

    result=$(echo "$out" | grep -oP '(?<=Aggressive OS guesses: ).+' | sed 's/ ([0-9]\+%)//g')
    [[ -n "$result" ]] && { echo "$result"; return; }

    # TCP/IP fingerprint: lines prefixed with "OS:" (no space after colon)
    result=$(echo "$out" | grep '^OS:' | sed 's/^OS://' | tr -d '\n')
    [[ -n "$result" ]] && { echo "$result"; return; }

    echo "No OS matches"
}

# --- ARP scan: build MAC → IP map ---
echo "[*] ARP scan on $INTERFACE ..."
ARP_OUTPUT=$(sudo arp-scan --interface="$INTERFACE" --localnet 2>/dev/null)

declare -A MAC_TO_IP
while read -r ip mac _; do
    norm=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | tr -d ':')
    MAC_TO_IP["$norm"]="$ip"
done < <(echo "$ARP_OUTPUT" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}')

echo "[*] ${#MAC_TO_IP[@]} host(s) found"
echo ""

# --- Match each VirtualBox VM to an IP via its NIC 1 MAC ---
echo "[*] Mapping VMs to IPs ..."
declare -A VM_TO_IP
declare -A VM_TO_MAC

while read -r vm_name; do
    [[ -z "$vm_name" ]] && continue
    vm_mac=$(su "$VMUSER" -c "VBoxManage showvminfo \"$vm_name\"" 2>/dev/null \
             | grep 'NIC 1:' | grep -oP '(?<=MAC: )[0-9A-F]+')
    [[ -z "$vm_mac" ]] && continue
    ip="${MAC_TO_IP[$vm_mac]}"
    printf "  %-35s  MAC: %-12s  IP: %s\n" \
        "$vm_name" "$vm_mac" "${ip:-(not on network)}"
    if [[ -n "$ip" ]]; then
        VM_TO_IP["$vm_name"]="$ip"
        VM_TO_MAC["$vm_name"]="$vm_mac"
    fi
done < <(su "$VMUSER" -c "VBoxManage list vms" 2>/dev/null | awk -F'"' '{print $2}')

echo ""

# --- Nmap scan per matched VM ---
if [[ ${#VM_TO_IP[@]} -eq 0 ]]; then
    echo "[!] No VMs matched to active IPs. Exiting."
    exit 1
fi

# CSV header
echo "vm_name,ip,mac,Os_Family,Os_Type,Os_Version,fingerprint_nmap" > "$CSV_OUT"

for vm_name in "${!VM_TO_IP[@]}"; do
    ip="${VM_TO_IP[$vm_name]}"
    mac_fmt=$(format_mac "${VM_TO_MAC[$vm_name]}")

    echo "========================================"
    echo "  VM : $vm_name"
    echo "  IP : $ip"

    os_family=""; os_type=""; os_version=""
    json_file="$VM_INFO_DIR/${vm_name}.json"
    if [[ -f "$json_file" ]]; then
        os_family=$(jq -r '.os_family // ""'  "$json_file")
        os_type=$(jq -r   '.os_type // ""'    "$json_file")
        os_version=$(jq -r '.os_version // ""' "$json_file")
        echo "  --- Ground-truth fingerprint ---"
        echo "  OS family  : $os_family"
        echo "  OS type    : $os_type"
        echo "  OS version : $os_version"
    else
        echo "  [!] No vm_info fingerprint found for $vm_name"
    fi

    echo "  --- nmap -O output ---"
    echo "========================================"
    nmap_output=$(sudo nmap -O --host-timeout 5m "$ip")
    echo "$nmap_output"
    echo ""

    nmap_fingerprint=$(extract_nmap_fingerprint "$nmap_output")

    printf "%s,%s,%s,%s,%s,%s,%s\n" \
        "$(csv_field "$vm_name")" \
        "$(csv_field "$ip")" \
        "$(csv_field "$mac_fmt")" \
        "$(csv_field "$os_family")" \
        "$(csv_field "$os_type")" \
        "$(csv_field "$os_version")" \
        "$(csv_field "$nmap_fingerprint")" >> "$CSV_OUT"
        sleep 5
done

echo "[*] CSV saved to $CSV_OUT"
