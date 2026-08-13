#!/usr/bin/bash

user="vmuser"

vm_names=$(su - $user -c "vboxmanage list vms" | awk -F'"' '{print $2}')

if [ -z "$vm_names" ]; then
    echo "No virtual machines found."
    exit 0
fi

printf "%-4s %-30s %6s %10s  %s\n" "#" "VM NAME" "CPUs" "MEMORY" "NIC1"
echo "--------------------------------------------------------------------------------"

total_cpus=0
total_memory=0
total_vms=0

while IFS= read -r vm_name; do
    info=$(su - $user -c "vboxmanage showvminfo '$vm_name'")

    cpus=$(echo "$info" | grep "Number of CPUs:" | awk -F': +' '{print $2}' | tr -d ' ')
    memory=$(echo "$info" | grep "Memory size:" | awk -F': +' '{print $2}' | tr -d ' ')
    nic1=$(echo "$info" | grep "^NIC 1:" | awk -F'Attachment: ' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')

    if [ -z "$nic1" ]; then
        nic1="disabled"
    fi

    total_vms=$((total_vms + 1))

    printf "%-4s %-30s %6s %10s  %s\n" "$total_vms" "$vm_name" "$cpus" "$memory" "$nic1"

    total_cpus=$((total_cpus + ${cpus:-0}))
    mem_value=${memory//MB/}
    total_memory=$((total_memory + ${mem_value:-0}))
done <<< "$vm_names"

echo "--------------------------------------------------------------------------------"
printf "%-4s %-30s %6s %10s\n" "$total_vms" "TOTAL" "$total_cpus" "${total_memory}MB"
