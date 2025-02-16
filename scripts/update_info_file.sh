#!/usr/bin/bash

user="vmuser"
info_folder="/data/virtual_machines/vm_info"
traffic_folder="/data/virtual_machines/traffic"


# get the parameters
usage() {
    echo "Usage: $0 vm_name [-s source | --source source] [-l link | --link link] [-H hash | --hash hash] [-f os_family | --os_family os_family] [-t os_type | --os_type os_type] [-v os_version | --os_version os_version] [-i IPv4 | --IPv4 IPv4] [-m MAC | --MAC MAC] [-h | --help]"
    echo "-s, --source: Source of the image (vagrant/osboxes.org/linuxvmimages.com)"
    echo "-l, --link: Link from where the image was downloaded"
    echo "-H, --hash: Hash of the image (in format sha256:hash/md5:hash/etc.)"
    echo "-V, --vagrant_box: Name of the vagrant box"
    echo "-f, --os_family: Family of the operating system (windows/linux/andorid/macos)"
    echo "-t, --os_type: Type of the operating system (e.g. debian, ubuntu, centos, fedora, etc.)"
    echo "-v, --os_version: Version of the operating system"
    echo "-i, --IPv4: IPv4 address of the virtual machine"
    echo "-m, --MAC: MAC address of the virtual machine"
    echo "-h, --help: Show help"
    exit 1
}

vm_name=$1
if [ -z "$vm_name" ]; then
    echo "Error: Missing required parameter"
    usage
elif [[ "$vm_name" == "-h" || "$vm_name" == "--help" ]]; then
    usage
fi
shift

source=""
link=""
hash=""
vagrant_box=""
os_family=""
os_type=""
os_version=""
ipv4=""
mac=""
info_file="$info_folder/$vm_name.json"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -s|--source)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            source="$2"
            shift 2
            ;;
        -l|--link)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            link="$2"
            shift 2
            ;;
        -H|--hash)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            hash="$2"
            shift 2
            ;;
        -V|--vagrant_box)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            vagrant_box="$2"
            shift 2
            ;;
        -f|--os_family)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            os_family="$2"
            shift 2
            ;;
        -t|--os_type)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            os_type="$2"
            shift 2
            ;;
        -v|--os_version)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            os_version="$2"
            shift 2
            ;;
        -i|--IPv4)
            if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            ipv4="$2"
            shift 2
            ;;
        -m|--MAC)
        if [ -z "$2" ]; then
                echo "Error: Missing required parameter"
                usage
            fi
            mac="$2"
            shift 2
            ;;
        *)
            echo "Error: Invalid parameter"
            usage
            exit 1
            ;;
    esac
done

# Check if given VM exists
if ! su $user -c "vboxmanage list vms" | grep -q \"$vm_name\"; then
    echo "Error: Virtual machine with the name '$vm_name' does not exist."
    exit 1
fi

# Check if the info file exists
if [ -e "$info_file" ]; then
    echo "Info file already exists. Updating the info file..."

    if [ -z $source ]; then
        source=$(cat $info_file | jq -r '.source')
    fi
    if [ -z $link ]; then
        link=$(cat $info_file | jq -r '.link')
    fi
    if [ -z $hash ]; then
        hash=$(cat $info_file | jq -r '.hash')
    fi
    if [ -z $os_family ]; then
        os_family=$(cat $info_file | jq -r '.os_family')
    fi
    if [ -z $os_type ]; then
        os_type=$(cat $info_file | jq -r '.os_type')
    fi
    if [ -z $os_version ]; then
        os_version=$(cat $info_file | jq -r '.os_version')
    fi
    if [ -z $ipv4 ]; then
        ipv4=$(cat $info_file | jq -r '.IPv4')
    fi
    if [ -z $mac ]; then
        mac=$(cat $info_file | jq -r '.MAC')
    fi
    if [ -z $vagrant_box ]; then
        vagrant_box=$(cat $info_file | jq -r '.vagrant_box')
    fi
fi

# create traffic folder
if [[ $os_family == "" || $os_type == "" || $os_version == "" ]]; then
    echo "SOME REQUIRED PARAMETERS ARE MISSING!"
    echo "Before running the virtual machine, please provide the following information:"
    traffic_folder=""
else
    traffic_folder="$traffic_folder/${os_family}__${os_type}__${os_version}"
    if [ ! -d "$traffic_folder" ]; then
        echo "Creating folder for traffic..."
        su - $user -c "mkdir -p $traffic_folder"
    fi
fi

# Check if all the required parameters are given
if [[ $source == "" ]]; then
    echo "WARNING: Source of the image is not given. Please provide the source of the image. This information is required before running the VM."
    if [[ $vagrant_box == "" ]]; then
        echo "WARNING: Name of the vagrant box is not given. Please provide the name of the vagrant box."
    fi
    if [[ $link == "" ]]; then
        echo "WARNING: Link of the image is not given. Please provide the link of the image."
    fi
    if [[ $hash == "" ]]; then
        echo "WARNING: Hash of the image is not given. Please provide the hash of the image."
    fi
elif [[ $source == "vagrant" ]]; then
    if [[ $vagrant_box == "" ]]; then
        echo "WARNING: Name of the vagrant box is not given. Please provide the name of the vagrant box."
    fi
elif [[ $source == "osboxes.org" || $source == "linuxvmimages.com" ]]; then
    if [[ $link == "" ]]; then
        echo "WARNING: Link of the image is not given. Please provide the link of the image."
    fi
    if [[ $hash == "" ]]; then
        echo "WARNING: Hash of the image is not given. Please provide the hash of the image."
    fi
else
    echo "WARNING: Invalid source. Please provide a valid source (vagrant/osboxes.org/linuxvmimages.com)."
fi
if [[ $os_family == "" ]]; then
    echo "WARNING: Family of the operating system is not given. Please provide the family of the operating system. This information is required before running the VM."
fi
if [[ $os_type == "" ]]; then
    echo "WARNING: Type of the operating system is not given. Please provide the type of the operating system. This information is required before running the VM."
fi
if [[ $os_version == "" ]]; then
    echo "WARNING: Version of the operating system is not given. Please provide the version of the operating system. This information is required before running the VM."
fi
if [[ $ipv4 == "" ]]; then
    echo "WARNING: IPv4 address of the virtual machine is not given. Please provide the IPv4 address of the virtual machine."
fi
if [[ $mac == "" ]]; then
    echo "WARNING: MAC address of the virtual machine is not given. Please provide the MAC address of the virtual machine."
fi

json_content=$(cat <<EOF
{
    "vm_name": "$vm_name",
    "source": "$source", 
    "link": "$link", 
    "hash": "$hash", 
    "vagrant_box": "$vagrant_box",
    "os_family": "$os_family",   
    "os_type": "$os_type",                        
    "os_version": "$os_version", 
    "IPv4": "$ipv4",
    "MAC": "$mac",
    "traffic_folder": "$traffic_folder"
}
EOF
)

su - $user -c "echo '$json_content' > $info_file"