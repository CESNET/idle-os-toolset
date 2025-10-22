#!/usr/bin/bash

user="vmuser"
info_path="/data/virtual_machines/vm_info"
script_path="/data/virtual_machines/scripts"

usage() {
    echo "Usage:"
    echo "  $0 vm_name [vm_name ...]"
    echo
    echo "Pass 'all' to process data of all VMs specified in \"$info_path\"."
    echo
    echo "Use --list to get list of all available VM names."
}
help() {
    echo "Process captured traffic of given VM (extract flows, and details of HTTP and TLS traffic)"
    echo
    usage
}

# Get parameters
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 2
elif [[ "$1" == "--list" ]]; then
    echo "Available VMs:"
    for vm in $info_path/*.json; do
      echo "  $(basename ${vm%.json})   ($(jq -r '[.os_family,.os_type,.os_version]|join(",")' "$vm"))"
    done
    exit 0
elif [ -z "$1" ]; then
    echo "Error: Missing required parameter - VM name"
    usage
    exit 1
elif [ "$1" = "all" ]; then
    # Get list of all VMs from their info files (<vm_name>.json)
    vm_names=$(ls "$info_path" | sed -n 's/\.json$//p')
else
    vm_names="$*"
fi

# Loop over all VMs  (FIXME: Doesnt work if there are spaces in names)
for vm_name in $vm_names; do
    echo "-----------------------------------------------------------------"
    echo "Processing captured traffic of the virtual machine $vm_name ..."

    traffic_dir="$(jq -r .traffic_folder "$info_path/$vm_name.json")"
    if [[ "$traffic_dir" == "" ]]; then echo "ERROR: Can't find info for $vm_name"; continue; fi

    # Loop over all runs/traffic captures (stored in directories named "YYYY-MM-DD__imagesource__imagename")
    capture_dirs="$(find "$traffic_dir" -type d -name '????-??-??__*__*')"
    if [[ "$traffic_dir" == "" ]]; then echo "WARNING: No captures files found!"; continue; fi
    for capture_dir in $capture_dirs; do
      pcap_file="$capture_dir/traffic.pcap"

      # Convert the pcap to a flow file
      echo "Converting pcap to flows: \"$pcap_file\""
      tmp_file="$capture_dir/tmp.trapcap"
      flows_file="$capture_dir/flows.csv"

      # Check if the pcap file is empty
      packet_count=$(tcpdump -r "$pcap_file" 2>/dev/null | wc -l)
      if [ "$packet_count" -le 1 ]; then
          echo "PCAP file is empty. No flow file will be created."
          continue 2
      fi

      su - $user -c "ipfixprobe -i \"pcap;file=$pcap_file\" -p basicplus -p http -p pstats -p tls -p dns -o \"unirec;i=f:$tmp_file;p=(basicplus,http,tls,dns,pstats)\""
      #su - $user -c "/usr/bin/nemea/traffic_repeater -i f:$tmp_file,u:$vm_name:buffer=off" & su - $user -c "/usr/bin/nemea/logger -i u:$vm_name -t -w $flows_file"
      su - $user -c "/usr/bin/nemea/logger -i f:$tmp_file -t -w $flows_file"
      su - $user -c "rm $tmp_file"
    done

    echo "Extracting HTTP request info from all the captured data"
    su - $user -c "python $script_path/get_http.py -n $vm_name"
    
    echo "Extracting TLS request info from all the captured data"
    su - $user -c "python $script_path/get_tls.py -n $vm_name"

    echo "Extracting DNS request info from all the captured data"
    su - $user -c "python $script_path/get_dns.py -n $vm_name"
done
echo "-----------------------------------------------------------------"
