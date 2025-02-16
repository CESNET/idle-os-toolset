#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'

user="vmuser"
traffic_path="/data/virtual_machines/traffic"
info_path="/data/virtual_machines/vm_info"  
capture_time=0
minutes=true
seconds=false
hours=false
days=false
date_format="%F"

# get the parameters
usage() {
    echo "Usage: $0 vm_name [-t capture_time | --time capture_time] [-g | --graphic] [-h | --help] [-m | --minutes] [-s | --seconds] [-H | --hours] [-d | --days]"
    echo "For starting multiple VMs at once separate names with comma. E.g. vm1,vm2,vm3. Do not use spaces. If you want to start all existing VMs, use all as the name."      
    echo "If time to capture traffic is not given, traffic will be captured until the virtual machine is stopped."
    echo "If time to capture traffic is given, virtual machine will be running and traffic will be captured for the given time."
    echo "-t, --time: Time to capture traffic in minutes"
    echo "-m, --minutes: Given time is in minutes (default)"
    echo "-s, --seconds: Given time is in seconds"
    echo "-H, --hours: Given time is in hours"
    echo "-d, --days: Given time is in days"
    echo "-h, --help: Show help"
    exit 1
}

vm_names=$1
if [ -z "$vm_names" ]; then
    echo -e "${RED}Error: Missing required parameter${NC}"
    usage
elif [ "$vm_names" = "all" ]; then
    vm_names=$(su - $user -c "vboxmanage list vms" | awk -F'"' '{print $2}' | tr '\n' ',')
fi
shift

# set seprator to comma 
IFS=','

# Split the string into an array    
read -r -a vm_array <<< "$vm_names"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -t|--time)
            capture_time="$2"
            shift 2
            ;;
        -m|--minutes)
            minutes=true
            seconds=false
            hours=false
            days=false
            shift
            ;;
        -s|--seconds)  
            minutes=false
            seconds=true
            hours=false
            days=false
            shift
            ;;
        -H|--hours)
            minutes=false
            seconds=false
            hours=true
            days=false
            shift
            ;;
        -d|--days)
            minutes=false
            seconds=false
            hours=false
            days=true
            shift
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

# Check parameters
# is capture_time a number?
if ! [[ "$capture_time" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: capture_time must be a number.${NC}"
    usage
fi




for vm_name in "${vm_array[@]}"; do   
    echo "-----------------------------------------------------------------"
    # Check if the virtual machine exists
    if ! su - $user -c "vboxmanage list vms | grep -q '$vm_name'"; then
        echo -e "${RED}Error: Virtual machine $vm_name does not exist.${NC}"
        continue
    fi

    if  su - $user -c "vboxmanage list runningvms | grep -q '$vm_name'"; then
        echo -e "${RED}Error: Virtual machine $vm_name is already running.${NC}"
        continue
    fi

    echo "Starting the virtual machine $vm_name"

    # variables for traffic capture
    info_path_vm="${info_path}/${vm_name}.json"
    date_name=$(date +$date_format)
    file_name="traffic.pcap"

    # get/create folder for traffic of this vm
    traffic_folder="$(jq -r '.traffic_folder' $info_path_vm)"

    if [ -z "$traffic_folder" ]; then
        family=$( jq -r '.os_family' $info_path_vm)
        if [ -z "$family" ]; then
            echo -e "${YELLOW}Error: os_family is missing in the info file. Please fill in the missing information before running the VM.${NC}"
            echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
            continue
        fi
        type=$(jq -r '.os_type' $info_path_vm)
        if [ -z "$type" ]; then
            echo -e "${YELLOW}Error: os_type is missing in the info file. Please fill in the missing information before running the VM.${NC}"
            echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
            continue
        fi
        version=$(jq -r '.os_version' $info_path_vm)
        if [ -z "$version" ]; then
            echo -e "${YELLOW}Error: os_version is missing in the info file. Please fill in the missing information before running the VM.${NC}"
            echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
            continue
        fi
        traffic_folder="${traffic_path}/${family}__${type}__${version}"
    fi

    # create folder path for this capture
    source=$(jq -r '.source' $info_path_vm)
    if [ -z "$source" ]; then
        echo -e "${YELLOW}Error: source is missing in the info file. Please fill in the missing information before running the VM.${NC}"
        echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
        continue
    else
        if [ "$source" == "vagrant" ]; then
            id=$(cat $info_path_vm | jq -r '.vagrant_box' | tr '/' '_')
            if [ -z "$id" ]; then
                echo -e "${YELLOW}Error: vagrant_box is missing in the info file. Please fill in the missing information before running the VM.${NC}"
                echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
                continue
            fi
        else
            id=$(cat $info_path_vm | jq -r '.hash' | cut -d ':' -f 2 | cut -c 1-6) # split on : and take the second part and take the first 6 characters
            if [ -z "$id" ]; then
                echo -e "${YELLOW}Error: hash is missing in the info file. Please fill in the missing information before running the VM.${NC}"
                echo -e "${YELLOW}The info file is located at $info_path_vm. You can fill in the missing information manually or use script /data/virtual_machines/scripts/update_info_file.sh.${NC}"
                continue
            fi
        fi
    fi
    traffic_folder="${traffic_folder}/${date_name}__${source}__${id}"

    # create info file for this capture
    counter=1 # if folder exists, add counter to the folder name
    folder_name=$traffic_folder
    while [ -d "$traffic_folder" ]; do
        traffic_folder="${folder_name}__${counter}"
        counter=$((counter+1))
    done

    su - $user -c "mkdir -p ${traffic_folder}"
    info_file="${traffic_folder}/info.json"
    su - $user -c "touch ${info_file}"
    su - $user -c "chmod 644 ${info_file}"

    # get info from the info file
    ipv4=$(jq -r '.IPv4' $info_path_vm)
    mac=$(jq -r '.MAC' $info_path_vm)
    os_family=$(jq -r '.os_family' $info_path_vm)   
    os_type=$(jq -r '.os_type' $info_path_vm)
    os_version=$(jq -r '.os_version' $info_path_vm)  
    source=$(jq -r '.source' $info_path_vm)
    link=$(jq -r '.link' $info_path_vm)
    hash=$(jq -r '.hash' $info_path_vm)
    vagrant_box=$(jq -r '.vagrant_box' $info_path_vm)

    if [ -z "$ipv4" ]; then
        ipv4=$(su - $user -c "VBoxManage guestproperty get "$vm_name" /VirtualBox/GuestInfo/Net/0/V4/IP")
        if [ "$ipv4" = "No value set!" ]; then
            ipv4=""
            note="IP address could not be obtained. The IP adress is probably 10.0.2.15, if NAT is used."
        else
            ipv4=$(echo $ipv4 | awk -F'[ ]+' '{print $2}')
        fi
    fi

    if [ -z "$mac" ]; then
        mac=$(su - $user -c "VBoxManage guestproperty get '$vm_name' /VirtualBox/GuestInfo/Net/0/MAC")
        if [ "$mac" = "No value set!" ]; then
            mac=""
            mac2=$(su - $user -c "VBoxManage showvminfo '$vm_name'" | grep 'MAC' | awk -F'[ ,]+' '{print $4}' | sed -E 's/(..)(..)(..)(..)(..)(..)/\1:\2:\3:\4:\5:\6/')
            if [ -n "$mac2" ]; then
                mac=$mac2
            fi
        else 
            mac=$(echo $mac | awk -F'[ ]+' '{print $2}' | sed -E 's/(..)(..)(..)(..)(..)(..)/\1:\2:\3:\4:\5:\6/')
        fi
    fi

    # write info to the info file
    su - $user -c "cat > $info_file <<EOF
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
    \"start_time\": \"$(date -u "+%Y-%m-%dT%H:%M:%S%z")\"
}
EOF
"

    # set end time of traffic capture
    end_time=""
    sleep_time=0
    # Capture traffic for the given time
    if [ "$capture_time" -ne 0 ]; then
        if [ "$minutes" = true ]; then
            sleep_time=$((capture_time * 60))
        elif [ "$seconds" = true ]; then
            sleep_time=$capture_time
        elif [ "$hours" = true ]; then
            sleep_time=$((capture_time * 3600))
        elif [ "$days" = true ]; then
            sleep_time=$((capture_time * 86400))
        fi
    fi

    # set traffic capture
    traffic_file="${traffic_folder}/${file_name}"
    su - $user -c "touch ${traffic_file}"
    su - $user -c "chmod 666 ${traffic_file}"
    su - $user -c "VBoxManage modifyvm ${vm_name} --nictrace1 on --nictracefile1 ${traffic_file}"

    # Start the virtual machine
    if [ "$graphic" = true ]; then
        su - $user -c "vboxmanage startvm $vm_name"
    else
        su - $user -c "vboxmanage startvm $vm_name --type headless"
    fi

    # Capture traffic for the given time
    if [ "$capture_time" -ne 0 ]; then
        (sleep $sleep_time
        /data/virtual_machines/scripts/stop_vm.sh $vm_name > /dev/null 2>&1) &
    fi

    
done

echo "-----------------------------------------------------------------"


