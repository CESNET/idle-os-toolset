#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m' # Reset

VAGRANT_NAME=""
VB_NAME=""
PATH_VAGRANT_BASE="/data/virtual_machines/vagrant/"
PATH_TRAFFIC="/data/virtual_machines/traffic/"
PATH_SCRIPTS="/data/virtual_machines/scripts/"
PATH_INFO="/data/virtual_machines/vm_info/"
vmuser="vmuser"

# Show help and usage
usage() {
    echo "Usage: $0 [-v vagrant_name|--vagrant vagrant_name] [-b vbox_name|--virtualbox vbox_name]"
    echo "Name the virtual machine in VirtualBox in the following format: <os>_<version>."
    echo "Example: $0 -v ubuntu/bionic64 -b ubuntu_bionic"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -v|--vagrant)
            VAGRANT_NAME="$2"
            shift 2
            ;;
        -b|--virtualbox)
            VB_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Check required parameters
if [ -z "$VB_NAME" ] || [ -z "$VAGRANT_NAME" ]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
fi

# Create paths
PATH_VAGRANT="${PATH_VAGRANT_BASE}${VB_NAME}"


# New folder for vagrant
# Check if directory exists
if [ -d "$PATH_VAGRANT" ]; then
  echo -e "${RED}Error: Directory '$PATH_VAGRANT' already exists. There is probably a virtual machine with the same name. If you want to create a new virtual machine, delete the existing directory first or choose a different name.${NC}"
  exit 1
else
  # Try to create the directory
  su - $vmuser -c "mkdir -p '$PATH_VAGRANT'" 
  # Check if the directory was created
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create directory '$PATH_VAGRANT'.${NC}"
    exit 1
  else
    echo "Directory '$PATH_VAGRANT' created successfully."
  fi
fi

# create Vagrantfile
su - $vmuser -c "cat > $PATH_VAGRANT/Vagrantfile <<EOF
Vagrant.configure('2') do |config|
  config.vm.box = '$VAGRANT_NAME'

  config.vm.provider 'virtualbox' do |vb|
    vb.name = '$VB_NAME'
    vb.check_guest_additions = false
  end
end
EOF
"

# check if the Vagrantfile was created
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to create Vagrantfile.${NC}"
  exit 1
else
  echo "Vagrantfile created successfully."
fi

su - $vmuser -c "cd $PATH_VAGRANT && vagrant up"


# check if vm is running
su - $vmuser -c "vboxmanage list runningvms" | grep -q "$VB_NAME"
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Virtual machine is not running and probably wasn't created.${NC}"
  exit 1
else
  echo "Virtual machine is running."
fi

# wait for the virtual machine to boot
echo "Waiting for machine to boot (60 seconds), then will get info about OS, MAC and IP addresses ..."
sleep 60

guest_os=$(su - $vmuser -c "VBoxManage showvminfo '$VB_NAME'" | grep "Guest OS" | awk -F': ' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
mac=$(su - $vmuser -c "VBoxManage guestproperty get '$VB_NAME' /VirtualBox/GuestInfo/Net/0/MAC")
if [ "$mac" = "No value set!" ]; then
  mac="unknown"
else 
  mac=$(echo $mac | awk -F'[ ]+' '{print $2}' | sed -E 's/(..)(..)(..)(..)(..)(..)/\1:\2:\3:\4:\5:\6/')
fi
ipv4=$(su - $vmuser -c "VBoxManage guestproperty get '$VB_NAME' /VirtualBox/GuestInfo/Net/0/V4/IP")
if [ "$ipv4" = "No value set!" ]; then
  ipv4="unknown"
else
  ipv4=$(echo $ipv4 | awk -F'[ ]+' '{print $2}')
fi

echo $guest_os
echo $mac
su - $vmuser -c "cat > ${PATH_INFO}${VB_NAME}.json <<EOF
{
  \"vm_name\": \"$VB_NAME\",
  \"source\": \"vagrant\",
  \"link\": \"\",
  \"hash\": \"\", 
  \"vagrant_box\": \"$VAGRANT_NAME\",
  \"os_family\": \"\",
  \"os_type\": \"\",                     
  \"os_version\": \"\",
  \"IPv4\": \"$ipv4\",
  \"MAC\": \"$mac\"
}
EOF
"

echo -e "${GREEN}Virtual machine created successfully.${NC}"
echo -e "${YELLOW}Please fill in the missing information in the ${PATH_INFO}${VB_NAME}.json file. Either manually or by running the script ${PATH_SCRIPTS}update_info_file.sh.${NC}"


# vm poweroff
su - $vmuser -c "vboxmanage controlvm '$VB_NAME' poweroff"
echo "Virtual machine powered off."

