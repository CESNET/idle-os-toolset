#!/usr/bin/bash

user="vmuser"

# get the parameters
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
    vm_names=$(su - $user -c "vboxmanage list runningvms" | awk -F'"' '{print $2}' | tr '\n' ',')
fi
shift

# set separator to comma
IFS=','

# Split the string into an array    
read -r -a vm_array <<< "$vm_names"



for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
    echo "Stopping the virtual machine $vm_name ..."

    # Check if the virtual machine exists
    if ! su - $user -c "vboxmanage list vms | grep -q '$vm_name'"; then
        echo "Error: Required virtual machine does not exist."
        continue
    fi

    # Check if the virtual machine is running
    if ! su - $user -c "vboxmanage list runningvms" | grep -q "$vm_name"; then
        echo "Virtual machine is not running."
        continue
    fi

    # Stop the virtual machine and stop traffic capture
    su - $user -c "vboxmanage controlvm '$vm_name' poweroff"
    su - $user -c "vboxmanage modifyvm '$vm_name' --nictrace1 off"

    # set the end time in the capture info file
    path_to_traffic=$(su - $user -c "vboxmanage showvminfo '$vm_name'"| grep "Trace: " | awk -F ': ' '{print $7}' | awk -F ')' '{print $1}')
    if ! [ -f "$path_to_traffic" ]; then
        echo "Error: Path to traffic not found."
        continue
    fi
    capture_info_file="$(dirname $path_to_traffic)/info.json"
    end_time=$(date -u "+%Y-%m-%dT%H:%M:%S%z")

    # get info from the info file
    ipv4=$(cat $capture_info_file | jq -r '.IPv4')
    mac=$(cat $capture_info_file | jq -r '.MAC')
    os_family=$(cat $capture_info_file | jq -r '.os_family')   
    os_type=$(cat $capture_info_file | jq -r '.os_type')
    os_version=$(cat $capture_info_file | jq -r '.os_version')  
    source=$(cat $capture_info_file | jq -r '.source')
    link=$(cat $capture_info_file | jq -r '.link')
    hash=$(cat $capture_info_file | jq -r '.hash')
    vagrant_box=$(cat $capture_info_file | jq -r '.vagrant_box')
    start_time=$(cat $capture_info_file | jq -r '.start_time')

    # write info to the info file
    su - $user -c "cat > $capture_info_file <<EOF
{
    \"vm_name\": \"$vm_name\",
    \"source\": \"$source\",
    \"link\": \"$link\",
    \"hash\": \"$hash\",
    \"vagrant_box\": \"$vagrant_box\",
    \"os_family\": \"$os_family\",
    \"os_type\": \"$os_type\",
    \"os_version\": \"$os_version\",
    \"IPv4\": \"$ipv4\",
    \"MAC\": \"$mac\",
    \"start_time\": \"$start_time\",
    \"end_time\": \"$end_time\"
}
EOF
"

    echo "Virtual machine $vm_name stopped, traffic capture ended."

done
echo "-----------------------------------------------------------------"
