#!/usr/bin/bash

user="vmuser"

home_dir=$(su - $user -c "pwd")

info_path="$home_dir/vm_info"
script_path="$home_dir/scripts"
logger_bin=""


find_logger_bin() {
    if [[ -x "/usr/local/bin/logger" ]]; then
        echo "/usr/local/bin/logger"
        return
    fi

    if [[ -x "/usr/bin/nemea/logger" ]]; then
        echo "/usr/bin/nemea/logger"
        return
    fi

    echo ""
}

check_requirements() {
    logger_bin="$(find_logger_bin)"
    if [[ -z "$logger_bin" ]]; then
        echo "ERROR: NEMEA logger binary not found."
        echo "       Expected one of: /usr/local/bin/logger, /usr/bin/nemea/logger"
        exit 1
    fi
}

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

check_requirements

# Loop over all VMs  (FIXME: Doesnt work if there are spaces in names)
for vm_name in $vm_names; do
    echo "-----------------------------------------------------------------"
    echo "Processing captured traffic of the virtual machine $vm_name ..."

    traffic_dir="$(jq -r .traffic_folder "$info_path/$vm_name.json")"
    traffic_dir="${home_dir}/${traffic_dir}"
    if [[ "$traffic_dir" == "" ]]; then echo "ERROR: Can't find info for $vm_name"; continue; fi

    # Loop over all runs/traffic captures (stored in directories named "YYYY-MM-DD__imagesource__imagename")
    capture_dirs="$(find "$traffic_dir" -type d -name '????-??-??__*__*')"
        if [[ -z "$capture_dirs" ]]; then echo "WARNING: No captures files found!"; continue; fi
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
      if [[ $? -ne 0 ]]; then
          echo "ERROR: Failed to convert PCAP to UniRec for '$pcap_file'."
          [[ -f "$tmp_file" ]] && su - $user -c "rm -f \"$tmp_file\""
          continue
      fi
      #su - $user -c "/usr/bin/nemea/traffic_repeater -i f:$tmp_file,u:$vm_name:buffer=off" & su - $user -c "/usr/bin/nemea/logger -i u:$vm_name -t -w $flows_file"
      su - $user -c "$logger_bin -i f:$tmp_file -t -w $flows_file"
      if [[ $? -ne 0 ]]; then
          echo "ERROR: Failed to export flows to '$flows_file'."
          [[ -f "$tmp_file" ]] && su - $user -c "rm -f \"$tmp_file\""
          continue
      fi
      su - $user -c "rm -f \"$tmp_file\""
    done

    echo "Extracting HTTP request info from all the captured data"
    su - $user -c "python $script_path/get_http.py -n $vm_name"
    
    echo "Extracting TLS request info from all the captured data"
    su - $user -c "python $script_path/get_tls.py -n $vm_name"

    echo "Extracting DNS request info from all the captured data"
    su - $user -c "python $script_path/get_dns.py -n $vm_name"
done
echo "-----------------------------------------------------------------"
