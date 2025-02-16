#!/usr/bin/bash

user="vmuser"
traffic_path="/data/virtual_machines/traffic"
info_path="/data/virtual_machines/vm_info"

# get the parameters
usage() {
    echo "Usage: $0 vm_name"
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

# set seprator to comma 
IFS=','

# Split the string into an array    
read -r -a vm_array <<< "$vm_names"



for vm_name in "${vm_array[@]}"; do
    echo "-----------------------------------------------------------------"
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

    echo "Stopping the virtual machine $vm_name"

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

    # converting the pcap to flow file
    tmp_file="$(dirname $path_to_traffic)/tmp.trapcap"
    flows_file="$(dirname $path_to_traffic)/flows.csv"

    # Check if the pcap file is empty
    packet_count=$(tcpdump -r $path_to_traffic 2>/dev/null | wc -l)

    if [ "$packet_count" -le 1 ]; then
        echo "PCAP file is empty. No flow file will be created."
        continue
    fi

    su - $user -c "ipfixprobe -i \"pcap;file=$path_to_traffic\" -p basicplus -p http -p pstats -p tls -p dns -p quic -o \"unirec;i=f:$tmp_file;p=(basicplus,http,tls,dns,quic,pstats)\""
    su - $user -c "/usr/bin/nemea/traffic_repeater -i f:$tmp_file,u:$vm_name:buffer=off" & su - $user -c "/usr/bin/nemea/logger -i u:$vm_name -t -w $flows_file"
    su - $user -c "rm $tmp_file"

    echo "Virtual machine $vm_name stopped, traffic capture ended."
    echo "Getting only HTTP traffic from captured data"
    su - $user -c "python /data/virtual_machines/scripts/get_http.py -n $vm_name -a $path_to_traffic"
    
    echo "Getting TLS"
    su - $user -c "python /data/virtual_machines/scripts/get_tls.py -n $vm_name"
done
echo "-----------------------------------------------------------------"
