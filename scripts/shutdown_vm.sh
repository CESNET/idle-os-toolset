#!/usr/bin/bash

user="vmuser"

usage() {
    echo "Usage:"
    echo "  $0 vm_name"
    echo
    echo "Multiple VMs can be specified (names separated by ','). Use 'all' to stop all running VMs."
    exit 1
}

vm_names=$1
if [ -z "$vm_names" ]; then
    echo "Error: Missing required parameter"
    usage
elif [ "$vm_names" = "all" ]; then
    vm_names=$(su - $user -c "vboxmanage list runningvms" | awk -F'"' '{print $2}' | paste -sd, -)
fi
shift

# set separator to comma
IFS=','

# Split the string into an array
read -r -a vm_array <<< "$vm_names"

for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
    echo "Stopping the virtual machine $vm_name ..."

    if ! su - $user -c "vboxmanage list vms | grep -q '\"$vm_name\"'"; then
        echo "Error: Required virtual machine does not exist."
        continue
    fi

    if ! su - $user -c "vboxmanage list runningvms" | grep -q "\"$vm_name\""; then
        echo "Virtual machine is not running."
        continue
    fi

    su - $user -c "vboxmanage controlvm '$vm_name' poweroff"
    su - $user -c "vboxmanage modifyvm '$vm_name' --nictrace1 off"

    echo "Virtual machine $vm_name stopped."
done

echo "-----------------------------------------------------------------"
