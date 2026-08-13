#!/usr/bin/bash
# Checks for duplicate MACs across all VirtualBox VMs and randomizes the duplicates.

set -euo pipefail

VMUSER="vmuser"

# Format raw VBoxManage MAC (0800275BE4C1) → 08:00:27:5B:E4:C1
format_mac() {
    echo "$1" | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/'
}

command -v VBoxManage &>/dev/null || { echo "Error: VBoxManage not found. Is VirtualBox installed?" >&2; exit 1; }

declare -A mac_owner   # MAC (raw) -> "vm<TAB>adapter_num"
declare -a to_fix      # entries: "vm<TAB>adapter_num<TAB>mac"

TAB=$'\t'

echo "=== VirtualBox MAC Checker ==="
echo ""

mapfile -t vms < <(su - "$VMUSER" -c "VBoxManage list vms" 2>/dev/null | awk -F'"' '{print $2}')

if [[ ${#vms[@]} -eq 0 ]]; then
    echo "No registered VMs found for user '$VMUSER'."
    exit 0
fi

echo "Scanning ${#vms[@]} VM(s)..."
echo ""

for vm in "${vms[@]}"; do
    [[ -z "$vm" ]] && continue

    info=$(su - "$VMUSER" -c "VBoxManage showvminfo \"$vm\"" 2>/dev/null) || {
        echo "  WARNING: Could not get info for '$vm', skipping." >&2
        continue
    }

    # Parse the first NIC "NIC 1: MAC: XXXX, ..." if not disabled
    while IFS= read -r nic_line; do
        n=$(echo   "$nic_line" | grep -oP '(?<=NIC )\d+')
        mac=$(echo "$nic_line" | grep -oP '(?<=MAC: )[0-9A-Fa-f]+')
        [[ -z "$n" || -z "$mac" ]] && continue

        mac="${mac^^}"
        printf "  %-35s  MAC: %s\n" "$vm" "$(format_mac "$mac")"

        if [[ -n "${mac_owner[$mac]+x}" ]]; then
            prev="${mac_owner[$mac]}"
            prev_vm="${prev%%$TAB*}"
            prev_n="${prev##*$TAB}"
            echo "    *** DUPLICATE with VM='$prev_vm' NIC $prev_n ***"
            to_fix+=("${vm}${TAB}${n}${TAB}${mac}")
        else
            mac_owner["$mac"]="${vm}${TAB}${n}"
        fi
    done < <(echo "$info" | grep -P '^NIC 1:' | grep -v 'disabled')
done

echo ""

if [[ ${#to_fix[@]} -eq 0 ]]; then
    echo "All MACs are unique. Nothing to do."
    exit 0
fi

echo "Found ${#to_fix[@]} duplicate MAC(s):"
for entry in "${to_fix[@]}"; do
    IFS=$'\t' read -r vm n mac <<< "$entry"
    echo "  VM='$vm'  MAC=$(format_mac "$mac")"
done

echo ""
read -rp "Randomize these MACs now? [y/N] " ans
if [[ ! "${ans,,}" =~ ^(y|yes)$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Randomizing duplicate MACs..."
echo ""

fixed=0
skipped=0

for entry in "${to_fix[@]}"; do
    IFS=$'\t' read -r vm n old_mac <<< "$entry"

    # Check state by reading the "State:" line from showvminfo
    state_line=$(su - "$VMUSER" -c "VBoxManage showvminfo \"$vm\"" 2>/dev/null \
        | grep -i '^State:' | head -1)

    if echo "$state_line" | grep -qiE 'running|paused|saved'; then
        echo "  SKIPPED '$vm' — VM is active: $state_line"
        (( skipped++ )) || true
        continue
    fi

    printf "  %-35s %s -> " "$vm" "$(format_mac "$old_mac")"

    # Equivalent to the "Generate a new random MAC address" button
    su - "$VMUSER" -c "VBoxManage modifyvm \"$vm\" --macaddress${n} auto"

    new_mac=$(su - "$VMUSER" -c "VBoxManage showvminfo \"$vm\"" 2>/dev/null \
        | grep -P "^NIC ${n}:" | grep -oP '(?<=MAC: )[0-9A-Fa-f]+')
    echo "$(format_mac "${new_mac^^}")"
    (( fixed++ )) || true
done

echo ""
echo "Result: $fixed MAC(s) randomized, $skipped skipped due to active VM."
