#!/usr/bin/bash

user="vmuser"
vagrant_path="vagrant"
os_info_path="os_info"
vm_info_path="vm_info"

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
    # remove vagrant , os_info folder and vm_info file if it exists
    vagrant_path="${vagrant_path}/${vm_name}"
    os_info_file="${os_info_path}/${vm_name}"
    vm_info_file="${vm_info_path}/${vm_name}.json"
    echo $vagrant_path
    if su - "$user" -c "[ -d '$vagrant_path' ]"; then
        echo "There are leftover files/folders for virtual machine ($vm_name). Do you want to delete vagrant, os_info and vm_info? (yes/no)"
        read answer
        if [ "$answer" == "yes" ]; then
            su - $user -c "rm -rf '$vagrant_path'"
            if [ $? -eq 0 ]; then
                echo "Vagrant folder deleted"
            else
                echo "Error: Could not delete the vagrant folder"
            fi

            if su - "$user" -c "[ -d '$os_info_file' ]"; then
                su - $user -c "rm -rf '$os_info_file'"
                if [ $? -eq 0 ]; then
                    echo "os_info removed"
                else
                    echo "Error: Could not remove os_info"
                fi
            fi

            if su - "$user" -c "[ -f '$vm_info_file' ]"; then
                su - $user -c "rm -f '$vm_info_file'"
                if [ $? -eq 0 ]; then
                    echo "vm_info removed"
                else
                    echo "Error: Could not remove vm_info"
                fi
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


if su - "$user" -c "[ -d '$vagrant_path' ]"; then
    su - $user -c "rm -rf '$vagrant_path'"
fi


# remove the os_info file if it exists
os_info_file="${os_info_path}/${vm_name}"


if su - "$user" -c "[ -d '$os_info_file' ]"; then
    su - $user -c "rm -rf '$os_info_file'"
fi

# remove the vm_info file if it exists
vm_info_file="${vm_info_path}/${vm_name}.json"


if su - "$user" -c "[ -f '$vm_info_file' ]"; then
    su - $user -c "rm -f '$vm_info_file'"
fi