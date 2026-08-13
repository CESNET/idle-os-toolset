#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'

user="vmuser"

usage() {
    echo "Usage: $0 vm_name [-c | --cpus <num_cpus>] [-r | --ram <ram_mb>] [-h | --help]"
    echo
    echo "Modifies the number of CPUs and/or RAM of one or more VirtualBox VMs."
    echo "Multiple VMs can be specified (names separated by ','). Use 'all' to resize all existing VMs."
    echo "The VM must be powered off before resizing."
    echo
    echo "  -c, --cpus <num_cpus>  Set the number of CPUs (must be >= 1)"
    echo "  -r, --ram  <ram_mb>    Set the RAM size in MB (must be >= 4)"
    echo "  -h, --help             Show this help message"
    exit 1
}

vm_names=$1
if [ -z "$vm_names" ]; then
    echo -e "${RED}Error: Missing required parameter.${NC}"
    usage
elif [ "$vm_names" = "all" ]; then
    vm_names=$(su - $user -c "vboxmanage list vms" | awk -F'"' '{print $2}' | paste -sd, -)
fi
shift

new_cpus=""
new_ram=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--cpus)
            new_cpus="$2"
            shift 2
            ;;
        -r|--ram)
            new_ram="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            usage
            ;;
    esac
done

# Validate that at least one option was given
if [ -z "$new_cpus" ] && [ -z "$new_ram" ]; then
    echo -e "${RED}Error: At least one of --cpus or --ram must be specified.${NC}"
    usage
fi

# Validate CPUs value
if [ -n "$new_cpus" ]; then
    if ! [[ "$new_cpus" =~ ^[0-9]+$ ]] || [ "$new_cpus" -lt 1 ]; then
        echo -e "${RED}Error: --cpus must be a positive integer (>= 1).${NC}"
        usage
    fi
fi

# Validate RAM value
if [ -n "$new_ram" ]; then
    if ! [[ "$new_ram" =~ ^[0-9]+$ ]] || [ "$new_ram" -lt 4 ]; then
        echo -e "${RED}Error: --ram must be a positive integer in MB (>= 4).${NC}"
        usage
    fi
fi

IFS=','
read -r -a vm_array <<< "$vm_names"

for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
    echo "Processing virtual machine: $vm_name"

    # Check if the VM exists
    if ! su - $user -c "vboxmanage list vms | grep -q '\"$vm_name\"'"; then
        echo -e "${RED}Error: Virtual machine '$vm_name' does not exist.${NC}"
        continue
    fi

    # Check if the VM is running
    if su - $user -c "vboxmanage list runningvms | grep -q '\"$vm_name\"'"; then
        echo -e "${RED}Error: Virtual machine '$vm_name' is currently running. Power it off before resizing.${NC}"
        continue
    fi

    # Show current values
    current_cpus=$(su - $user -c "vboxmanage showvminfo '$vm_name' --machinereadable" | grep '^cpus=' | cut -d'=' -f2)
    current_ram=$(su - $user -c "vboxmanage showvminfo '$vm_name' --machinereadable" | grep '^memory=' | cut -d'=' -f2)
    echo "  Current CPUs : ${current_cpus:-unknown}"
    echo "  Current RAM  : ${current_ram:-unknown} MB"

    # Apply CPU change
    if [ -n "$new_cpus" ]; then
        if su - $user -c "vboxmanage modifyvm '$vm_name' --cpus $new_cpus"; then
            echo -e "  ${GREEN}CPUs updated: ${current_cpus:-?} -> $new_cpus${NC}"
        else
            echo -e "  ${RED}Error: Failed to update CPUs for '$vm_name'.${NC}"
        fi
    fi

    # Apply RAM change
    if [ -n "$new_ram" ]; then
        if su - $user -c "vboxmanage modifyvm '$vm_name' --memory $new_ram"; then
            echo -e "  ${GREEN}RAM updated: ${current_ram:-?} MB -> $new_ram MB${NC}"
        else
            echo -e "  ${RED}Error: Failed to update RAM for '$vm_name'.${NC}"
        fi
    fi
done

echo "-----------------------------------------------------------------"
