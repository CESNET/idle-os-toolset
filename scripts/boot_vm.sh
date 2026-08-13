#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'

user="vmuser"

usage() {
    echo "Usage: $0 <vm_name|all|N-M> [-g | --graphic] [-h | --help]"
    echo ""
    echo "  vm_name       Single VM or comma-separated list: vm1,vm2,vm3"
    echo "  all           Start all existing VMs"
    echo "  N-M           Start VMs from position N to M in the full list (1-based)"
    echo ""
    echo "  -g, --graphic  Start VM(s) in graphic mode"
    echo "  -h, --help     Show help"
    exit 1
}

first_arg=$1
if [ -z "$first_arg" ]; then
    echo -e "${RED}Error: Missing required parameter${NC}"
    usage
fi
shift

# Get full VM list (always needed for range and all)
all_vms=$(su - $user -c "vboxmanage list vms" | awk -F'"' '{print $2}')

if [ "$first_arg" = "all" ]; then
    mapfile -t vm_array <<< "$all_vms"
elif [[ "$first_arg" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    range_start=${BASH_REMATCH[1]}
    range_end=${BASH_REMATCH[2]}
    if [[ "$range_start" -lt 1 || "$range_end" -lt "$range_start" ]]; then
        echo -e "${RED}Error: Invalid range ${first_arg}. Start must be >= 1 and <= end.${NC}"
        exit 1
    fi
    mapfile -t all_vms_array <<< "$all_vms"
    vm_array=("${all_vms_array[@]:$((range_start - 1)):$((range_end - range_start + 1))}")
    if [ "${#vm_array[@]}" -eq 0 ]; then
        echo -e "${RED}Error: Range ${first_arg} is out of bounds (total VMs: ${#all_vms_array[@]}).${NC}"
        exit 1
    fi
else
    IFS=',' read -r -a vm_array <<< "$first_arg"
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -g|--graphic)
            graphic=true
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
    if ! su - $user -c "vboxmanage list vms | grep -q '\"$vm_name\"'"; then
        echo -e "${RED}Error: Virtual machine $vm_name does not exist.${NC}"
        continue
    fi

    if su - $user -c "vboxmanage list runningvms | grep -q '\"$vm_name\"'"; then
        echo -e "${RED}Error: Virtual machine $vm_name is already running.${NC}"
        continue
    fi

    echo "Starting the virtual machine $vm_name"

    # Ensure NIC trace is off
    su - $user -c "VBoxManage modifyvm ${vm_name} --nictrace1 off"

    if [ "$graphic" = true ]; then
        su - $user -c "vboxmanage startvm $vm_name"
    else
        su - $user -c "vboxmanage startvm $vm_name --type headless"
    fi
    sleep 5
done

echo "-----------------------------------------------------------------"
