#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m' # Reset

VAGRANT_NAME=""
VB_NAME=""
PATH_VAGRANT_BASE="vagrant/"
PATH_TRAFFIC="traffic/"
PATH_SCRIPTS="scripts/"
PATH_INFO="vm_info/"
PATH_OS_INFO="os_info/"
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
if [[ "$VB_NAME" == *"windows"* ]]; then
  # Windows guests
  su - $vmuser -c "cat > $PATH_VAGRANT/Vagrantfile <<EOF
Vagrant.configure('2') do |config|
  config.vm.box = '$VAGRANT_NAME'
  config.ssh.insert_key = true
  config.vm.communicator = 'winrm'
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.vm.provider 'virtualbox' do |vb|
    vb.name = '$VB_NAME'
    vb.check_guest_additions = false
    vb.gui = false
  end
end
EOF
"
elif [[ "$VB_NAME" == *"android"* || "$VAGRANT_NAME" == *"android"* ]]; then
  # Android guests
  su - $vmuser -c "cat > $PATH_VAGRANT/Vagrantfile <<EOF
Vagrant.configure('2') do |config|
  config.vm.box = '$VAGRANT_NAME'
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.ssh.insert_key = true
  # Not check ssh connectivity for Android guests, as it is not supported by default
  config.vm.communicator = 'dummy'
  # Forward adb port to connect to the Android guest via adb from the host
  config.vm.network 'forwarded_port', guest: 5555, host: 5555, auto_correct: true, id: 'adb', protocol: 'tcp'
  config.vm.provider 'virtualbox' do |vb|
    vb.name = '$VB_NAME'
    vb.check_guest_additions = false
  end
end
EOF
"
  if ! su - $vmuser -c "netstat -putona | grep -qi 'adb'"; then
    echo "ADB server is not running for $vmuser. Starting it..."
    su - $vmuser -c "adb start-server"
  else
    echo "ADB server is already running for $vmuser."
  fi

elif [[ "$VB_NAME" == macOS_* || "$VB_NAME" == *"macOS"* || "$VAGRANT_NAME" == *"macos"* || "$VAGRANT_NAME" == *"macOS"* ]]; then
  # macOS guests: apply VBox settings before first boot via vb.customize
  su - $vmuser -c "cat > $PATH_VAGRANT/Vagrantfile <<EOF
Vagrant.configure('2') do |config|
  config.vm.box = '$VAGRANT_NAME'
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.ssh.insert_key = true
  config.vm.provider 'virtualbox' do |vb|
    vb.name = '$VB_NAME'
    vb.check_guest_additions = false
    vb.customize ['modifyvm', :id, '--cpuidset', '00000001', '000106e5', '00100800', '00000209', '078bfbff']
    vb.customize ['setextradata', :id, 'VBoxInternal/Devices/efi/0/Config/DmiSystemProduct', 'iMac19,1']
    vb.customize ['setextradata', :id, 'VBoxInternal/Devices/efi/0/Config/DmiSystemVersion', '1.0']
    vb.customize ['setextradata', :id, 'VBoxInternal/Devices/efi/0/Config/DmiBoardProduct', 'Mac-AA95B1DDAB278B95']
    vb.customize ['setextradata', :id, 'VBoxInternal/Devices/smc/0/Config/DeviceKey', 'ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc']
    vb.customize ['setextradata', :id, 'VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC', '1']
    vb.customize ['modifyvm', :id, '--cpu-profile', 'Intel Core i7-6700K']
  end
end
EOF
"
else
  # Other guests (Linux, etc.)
  su - $vmuser -c "cat > $PATH_VAGRANT/Vagrantfile <<EOF
Vagrant.configure('2') do |config|
  config.vm.box = '$VAGRANT_NAME'
  config.vm.boot_timeout = 120
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.ssh.insert_key = true
  config.vm.provider 'virtualbox' do |vb|
    vb.name = '$VB_NAME'
    vb.check_guest_additions = false
  end
end
EOF
"
fi

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
sleep 30

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

su - $vmuser -c "cd $PATH_VAGRANT && python ~/${PATH_SCRIPTS}get_os_info.py -v $VAGRANT_NAME -b $VB_NAME"

echo -e "${GREEN}Virtual machine created successfully.${NC}"
#echo -e "${YELLOW}Please fill in the missing information in the ${PATH_INFO}${VB_NAME}.json file. Either manually or by running the script ${PATH_SCRIPTS}update_info_file.sh.${NC}"

OS_INFO_FILE="${PATH_OS_INFO}${VB_NAME}/os_info.json"

json_content=$(su - $vmuser -c "cat $OS_INFO_FILE")

if [ -z "$json_content" ]; then
  su - $vmuser -c "mkdir -p ${PATH_OS_INFO}${VB_NAME}/"
  su - $vmuser -c "touch ${OS_INFO_FILE}"
fi

OS_FAMILY=$(echo "$json_content" | jq -r '.Os_Family // empty' | tr ' ' '_' )
OS_TYPE=$(echo "$json_content" | jq -r '.Os_Type // empty' | tr ' ' '_' )
OS_VERSION=$(echo "$json_content" | jq -r '.Os_Version // empty' | tr ' ' '_' )
echo $VB_NAME
echo $OS_FAMILY
echo $OS_TYPE
echo $OS_VERSION

su - $vmuser -c "./${PATH_SCRIPTS}update_info_file.sh $VB_NAME -f '$OS_FAMILY' -t '$OS_TYPE' -v '$OS_VERSION'"


# if [ ! -z "$json_content" ]; then
#   OS_FAMILY=$(echo "$json_content" | jq -r '.Os_Family // empty' | tr ' ' '_' )
#   OS_TYPE=$(echo "$json_content" | jq -r '.Os_Type // empty' | tr ' ' '_' )
#   OS_VERSION=$(echo "$json_content" | jq -r '.Os_Version // empty' | tr ' ' '_' )
#   su - $vmuser -c "./${PATH_SCRIPTS}update_info_file.sh $VB_NAME -f '$OS_FAMILY' -t '$OS_TYPE' -v '$OS_VERSION'"
# else
#   echo -e "${RED}Error: OS info file not created or is empty. Cannot update vm info.${NC}"
# fi

# vm poweroff
su - $vmuser -c "vboxmanage controlvm '$VB_NAME' poweroff"
echo "Virtual machine powered off."