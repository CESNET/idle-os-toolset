#!/usr/bin/bash

user="vmuser"
vagrant_path="/data/virtual_machines/vagrant"

# get the parameters
usage() {
    echo "Usage: $0 vm_name"
    exit 1
}

vm_name=$1
if [ -z "$vm_name" ]; then
    echo "Error: Missing required parameter"
    usage
fi

# Check if the virtual machine exists
if ! su - $user -c "vboxmanage list vms | grep -q '$vm_name'"; then
    echo "Error: Required virtual machine does not exist."
    # remove vagrant folder if it exists
    vagrant_path="${vagrant_path}/${vm_name}"
    if [ -d "$vagrant_path" ]; then
        echo "There is a vagrant folder for the virtual machine with this name ($vm_name). Do you want to delete it? (yes/no)"
        read answer
        if [ "$answer" == "yes" ]; then
            su - $user -c "rm -rf '$vagrant_path'"
            if [ $? -eq 0 ]; then
                echo "Vagrant folder deleted"
            else
                echo "Error: Could not delete the vagrant folder"
            fi
        fi
    fi
    exit 1
fi

# check if the virtual machine is running
if su - $user -c "vboxmanage list runningvms | grep -q '$vm_name'"; then
    echo "Error: The virtual machine is running. Do you want to stop it first? (yes/no)"
    read answer
    if [ "$answer" != "yes" ]; then
        echo "Aborted"
        exit 0
    fi
    su - $user -c "vboxmanage controlvm $vm_name poweroff"
fi

# confirm the deletion
echo "Are you sure you want to delete the virtual machine $vm_name? (yes/no)"
read answer
if [ "$answer" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

# remove the virtual machine
su - $user -c "vboxmanage unregistervm $vm_name --delete"

# remove vagrant folder if it exists
vagrant_path="${vagrant_path}/${vm_name}"
if [ -d "$vagrant_path" ]; then
    su - $user -c "rm -rf '$vagrant_path'"
fi