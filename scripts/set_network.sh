#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'

user="vmuser"
hostonly_adapter="vboxnet0"
mode=""

usage() {
    echo "Usage: $0 vm_name --hostonly | --nat"
    echo
    echo "  vm_name     Name of the VM to configure. Separate multiple names with comma (e.g. vm1,vm2,vm3)."
    echo "              Use 'all' to configure all existing VMs."
    echo
    echo "  --hostonly  Set NIC1 to host-only network (${hostonly_adapter})"
    echo "  --nat       Set NIC1 to NAT"
    echo "  -h, --help  Show this help message"
    echo
    echo "Note: VMs must be powered off before changing network configuration."
    exit 1
}

vm_names=$1
if [ -z "$vm_names" ]; then
    echo -e "${RED}Error: Missing required parameter.${NC}"
    usage
fi
if [[ "$vm_names" == -* ]]; then
    echo -e "${RED}Error: First argument must be a VM name or 'all'.${NC}"
    usage
fi
if [ "$vm_names" = "all" ]; then
    vm_names=$(su - $user -c "vboxmanage list vms" | awk -F'"' '{print $2}' | paste -sd, -)
    if [ -z "$vm_names" ]; then
        echo -e "${RED}Error: No virtual machines found.${NC}"
        exit 1
    fi
fi
shift

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --hostonly)
            mode="hostonly"
            shift
            ;;
        --nat)
            mode="nat"
            shift
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            usage
            ;;
    esac
done

if [ -z "$mode" ]; then
    echo -e "${RED}Error: You must specify --hostonly or --nat.${NC}"
    usage
fi

if [ "$mode" = "hostonly" ]; then
    if ! su - $user -c "VBoxManage list hostonlyifs" | grep -qE "^Name:[[:space:]]*${hostonly_adapter}\$"; then
        echo -e "${RED}Error: Host-only adapter '${hostonly_adapter}' does not exist. Create it first (e.g. 'VBoxManage hostonlyif create') or update hostonly_adapter in this script.${NC}"
        exit 1
    fi
fi

# set separator to comma
IFS=','

# Split the string into an array
read -r -a vm_array <<< "$vm_names"

for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
    echo "Configuring network for: ${vm_name}"

    # Check if the virtual machine exists
    if ! su - $user -c "vboxmanage list vms | grep -q '\"${vm_name}\"'"; then
        echo -e "${RED}Error: Virtual machine '${vm_name}' does not exist.${NC}"
        continue
    fi

    # Network config can only be changed on powered off VMs
    if su - $user -c "vboxmanage list runningvms | grep -q '\"${vm_name}\"'"; then
        echo -e "${RED}Error: Virtual machine '${vm_name}' is running. Power it off before changing network configuration.${NC}"
        continue
    fi

    if [ "$mode" = "hostonly" ]; then
        echo "Setting NIC1 to host-only network (${hostonly_adapter}) ..."
        if su - $user -c "vboxmanage modifyvm '${vm_name}' --nic1 hostonly --hostonlyadapter1 ${hostonly_adapter}"; then
            echo -e "${GREEN}Done: '${vm_name}' NIC1 is now host-only (${hostonly_adapter}).${NC}"
        else
            echo -e "${RED}Error: Failed to configure '${vm_name}'.${NC}"
        fi
    elif [ "$mode" = "nat" ]; then
        echo "Setting NIC1 to NAT ..."
        if su - $user -c "vboxmanage modifyvm '${vm_name}' --nic1 nat"; then
            echo -e "${GREEN}Done: '${vm_name}' NIC1 is now NAT.${NC}"
        else
            echo -e "${RED}Error: Failed to configure '${vm_name}'.${NC}"
        fi
    fi
done

echo "-----------------------------------------------------------------"
