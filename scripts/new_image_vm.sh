#!/usr/bin/bash
#
# Creates a VirtualBox VM from a local .zip/.7z file containing an OVA, a
# VBOX (exported VM folder with its disks) or a loose VDI disk. Mirrors the
# workflow of new_vagrant.sh but for images that are not distributed as
# Vagrant boxes.

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m' # Reset

ZIP_NAME=""
VB_NAME=""
REMOTE_USER=""
REMOTE_PASSWORD=""
IMAGE_HASH=""
SOURCE=""
LINK=""

PATH_IMAGES="vm_images/"
PATH_SCRIPTS="scripts/"
PATH_INFO="vm_info/"
PATH_OS_INFO="os_info/"
vmuser="vmuser"

SSH_FWD_PORT=2222
WINRM_FWD_PORT=55985
ADB_PORT=5555

DEFAULT_MEMORY=2048
DEFAULT_CPUS=2

usage() {
    echo "Usage: $0 -z zip_name|--zip zip_name -b vbox_name|--virtualbox vbox_name -u user|--user user -p password|--password password -H hash|--hash hash -s source|--source source -l link|--link link"
    echo "Name the virtual machine in VirtualBox in the following format: <os>_<version>."
    echo "All parameters are required, except -u/--user and -p/--password for Android guests (VM name contains 'android'), which don't need remote access credentials."
    echo "-z, --zip:        Name of the .zip/.7z file inside the ${PATH_IMAGES} folder (must contain an .ova, a .vbox VM folder or a loose .vdi)"
    echo "-b, --virtualbox: Name to give the virtual machine in VirtualBox"
    echo "-u, --user:       Username used for remote access (SSH/WinRM) inside the guest (not needed for Android)"
    echo "-p, --password:   Password used for remote access (SSH/WinRM) inside the guest (not needed for Android)"
    echo "-H, --hash:       Hash of the zip file (format algo:hash, e.g. sha256:...)"
    echo "-s, --source:     Source of the image (e.g. osboxes.org, linuxvmimages.com)"
    echo "-l, --link:       Link from where the image was downloaded"
    echo "Example: $0 -z manjaro_21.0.zip -b manjaro_21.0 -u manjaro -p manjaro -H md5:daabd6555ad6c4776f6aa5f59dff05ea -s linuxvmimages.com -l https://www.linuxvmimages.com/images/manjaro-21/"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -z|--zip)
            ZIP_NAME="$2"
            shift 2
            ;;
        -b|--virtualbox)
            VB_NAME="$2"
            shift 2
            ;;
        -u|--user)
            REMOTE_USER="$2"
            shift 2
            ;;
        -p|--password)
            REMOTE_PASSWORD="$2"
            shift 2
            ;;
        -H|--hash)
            IMAGE_HASH="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -l|--link)
            LINK="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Detect guest family from the VM name (same heuristic as new_vagrant.sh).
# Done before the required-parameter check because Android guests don't need
# remote-access credentials (ADB doesn't use a user/password).
name_lc=$(echo "$VB_NAME" | tr '[:upper:]' '[:lower:]')
IS_WINDOWS=false
IS_ANDROID=false
IS_MACOS=false
if [[ "$name_lc" == *"windows"* ]]; then
    IS_WINDOWS=true
elif [[ "$name_lc" == *"android"* ]]; then
    IS_ANDROID=true
elif [[ "$name_lc" == "macos_"* || "$name_lc" == *"macos"* ]]; then
    IS_MACOS=true
fi

# Check required parameters
if [ -z "$ZIP_NAME" ] || [ -z "$VB_NAME" ] || [ -z "$IMAGE_HASH" ] || [ -z "$SOURCE" ] || [ -z "$LINK" ]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
fi

if [ "$IS_ANDROID" = false ] && { [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASSWORD" ]; }; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
fi

ZIP_PATH="${PATH_IMAGES}${ZIP_NAME}"

if ! su - $vmuser -c "[ -f '$ZIP_PATH' ]"; then
    echo -e "${RED}Error: File '$ZIP_PATH' does not exist.${NC}"
    exit 1
fi

if su - $vmuser -c "vboxmanage list vms" | grep -q "\"$VB_NAME\""; then
    echo -e "${RED}Error: A virtual machine named '$VB_NAME' already exists.${NC}"
    exit 1
fi

# Hash verification
hash_algo=$(echo "$IMAGE_HASH" | cut -d ':' -f1 | tr '[:upper:]' '[:lower:]')
given_hash_value=$(echo "$IMAGE_HASH" | cut -d ':' -f2)
if ! command -v "${hash_algo}sum" > /dev/null 2>&1; then
    echo -e "${RED}Error: Unsupported hash algorithm '$hash_algo'. Expected format is algo:hash (e.g. sha256:...).${NC}"
    exit 1
fi
computed_hash=$(su - $vmuser -c "${hash_algo}sum '$ZIP_PATH'" | awk '{print $1}')
if [ "$given_hash_value" != "$computed_hash" ]; then
    echo -e "${YELLOW}WARNING: Given hash does not match the ${hash_algo} of '$ZIP_PATH'. Continuing anyway.${NC}"
    echo -e "${YELLOW}  Given:    $IMAGE_HASH${NC}"
    echo -e "${YELLOW}  Computed: ${hash_algo}:$computed_hash${NC}"
fi

# Guess VBoxManage --ostype from .vdi with no OVA/VBOX metadata).
guess_ostype() {
    case "$name_lc" in
        *windows*server*) echo "Windows2019_64" ;;
        *windows*11*) echo "Windows11_64" ;;
        *windows*10*) echo "Windows10_64" ;;
        *windows*) echo "Windows10_64" ;;
        *macos*)
            ver=$(echo "$name_lc" | grep -oE '1[0-9]\.[0-9]+' | head -n1 | tr -d '.')
            if [ -n "$ver" ] && su - $vmuser -c "VBoxManage list ostypes" | grep -q "MacOS${ver}_64"; then
                echo "MacOS${ver}_64"
            else
                echo "MacOS_64"
            fi
            ;;
        *android*) echo "Linux_64" ;;
        *ubuntu*) echo "Ubuntu_64" ;;
        *debian*) echo "Debian_64" ;;
        *centos*|*rhel*) echo "RedHat_64" ;;
        *fedora*) echo "Fedora_64" ;;
        *freebsd*) echo "FreeBSD_64" ;;
        *openbsd*) echo "OpenBSD_64" ;;
        *) echo "Linux_64" ;;
    esac
}

DEFAULT_VM_FOLDER=$(su - $vmuser -c "VBoxManage list systemproperties" | grep "Default machine folder:" | sed -E 's/^Default machine folder:[ \t]*//')
if [ -z "$DEFAULT_VM_FOLDER" ]; then
    echo -e "${RED}Error: Could not determine VirtualBox's default machine folder.${NC}"
    exit 1
fi

# Staging directory for extraction only for the OVA case; for
# VBOX/VDI cases its contents are moved into VirtualBox's
# default machine folder.
su - $vmuser -c "mkdir -p '${PATH_IMAGES}.tmp'"
STAGING_DIR=$(su - $vmuser -c "mktemp -d '${PATH_IMAGES}.tmp/${VB_NAME}_XXXXXX'")
if [ -z "$STAGING_DIR" ]; then
    echo -e "${RED}Error: Failed to create staging directory for extraction.${NC}"
    exit 1
fi

echo "Extracting '$ZIP_PATH' into '$STAGING_DIR' ..."
case "$ZIP_NAME" in
    *.zip|*.ZIP)
        su - $vmuser -c "unzip -q '$ZIP_PATH' -d '$STAGING_DIR'"
        ;;
    *.7z|*.7Z)
        su - $vmuser -c "7z x -y -o'$STAGING_DIR' '$ZIP_PATH'" > /dev/null
        ;;
    *)
        echo -e "${RED}Error: Unsupported archive format for '$ZIP_NAME'. Only .zip and .7z are supported.${NC}"
        su - $vmuser -c "rm -rf '$STAGING_DIR'"
        exit 1
        ;;
esac

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to extract '$ZIP_PATH'.${NC}"
    su - $vmuser -c "rm -rf '$STAGING_DIR'"
    exit 1
fi

OVA_FILE=$(su - $vmuser -c "find '$STAGING_DIR' -iname '*.ova'" | head -n1)
VBOX_FILE=$(su - $vmuser -c "find '$STAGING_DIR' -iname '*.vbox'" | head -n1)
VDI_FILE=$(su - $vmuser -c "find '$STAGING_DIR' -iname '*.vdi'" | head -n1)

FINAL_VM_DIR="${DEFAULT_VM_FOLDER}/${VB_NAME}"



# Create the virtual machine from a .ova file
if [ -n "$OVA_FILE" ]; then
    echo "Found OVA file '$OVA_FILE'. Importing ..."
    su - $vmuser -c "VBoxManage import '$OVA_FILE' --vsys 0 --vmname '$VB_NAME' --eula accept"
    import_status=$?
    if [ "$import_status" -ne 0 ] || ! su - $vmuser -c "vboxmanage list vms" | grep -q "\"$VB_NAME\""; then
        echo -e "${RED}Error: Failed to import '$OVA_FILE'.${NC}"
        su - $vmuser -c "rm -rf '$STAGING_DIR'"
        exit 1
    fi
    su - $vmuser -c "rm -rf '$STAGING_DIR'"

# Create the virtual machine from a .vbox file
elif [ -n "$VBOX_FILE" ]; then
    echo "Found VBOX file '$VBOX_FILE'. Registering ..."
    if su - $vmuser -c "[ -e '$FINAL_VM_DIR' ]"; then
        echo -e "${RED}Error: '$FINAL_VM_DIR' already exists.${NC}"
        su - $vmuser -c "rm -rf '$STAGING_DIR'"
        exit 1
    fi
    VBOX_DIR=$(su - $vmuser -c "dirname '$VBOX_FILE'")
    su - $vmuser -c "mv '$VBOX_DIR' '$FINAL_VM_DIR'"
    NEW_VBOX_FILE="${FINAL_VM_DIR}/$(basename "$VBOX_FILE")"
    if su - $vmuser -c "grep -q '</DVDImages>' '$NEW_VBOX_FILE'"; then
        echo "Removing <DVDImages> section from '$NEW_VBOX_FILE' ..."
        su - $vmuser -c "perl -0777 -pi -e 's/<DVDImages>.*?<\/DVDImages>//s' '$NEW_VBOX_FILE'"
    fi
    su - $vmuser -c "VBoxManage registervm '$NEW_VBOX_FILE'"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to register '$NEW_VBOX_FILE'.${NC}"
        su - $vmuser -c "rm -rf '$STAGING_DIR'"
        exit 1
    fi
    CURRENT_NAME=$(su - $vmuser -c "VBoxManage showvminfo '$NEW_VBOX_FILE' --machinereadable" | grep '^name=' | cut -d'"' -f2)
    if [ -n "$CURRENT_NAME" ] && [ "$CURRENT_NAME" != "$VB_NAME" ]; then
        su - $vmuser -c "VBoxManage modifyvm '$CURRENT_NAME' --name '$VB_NAME'"
    fi
    su - $vmuser -c "rm -rf '$STAGING_DIR'"

# Create the virtual machine from a .vdi file
elif [ -n "$VDI_FILE" ]; then
    echo "Found VDI file '$VDI_FILE'. Creating a new virtual machine for it ..."
    if su - $vmuser -c "[ -e '$FINAL_VM_DIR' ]"; then
        echo -e "${RED}Error: '$FINAL_VM_DIR' already exists.${NC}"
        su - $vmuser -c "rm -rf '$STAGING_DIR'"
        exit 1
    fi
    su - $vmuser -c "mkdir -p '$FINAL_VM_DIR'"
    su - $vmuser -c "mv '$VDI_FILE' '$FINAL_VM_DIR/'"
    FINAL_VDI="${FINAL_VM_DIR}/$(basename "$VDI_FILE")"
    su - $vmuser -c "rm -rf '$STAGING_DIR'"

    OSTYPE=$(guess_ostype)
    echo "Guessed VBoxManage ostype: $OSTYPE"

    su - $vmuser -c "VBoxManage createvm --name '$VB_NAME' --ostype '$OSTYPE' --basefolder '$DEFAULT_VM_FOLDER' --register"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create virtual machine '$VB_NAME'.${NC}"
        exit 1
    fi
    su - $vmuser -c "VBoxManage storagectl '$VB_NAME' --name 'SATA Controller' --add sata --controller IntelAhci"
    su - $vmuser -c "VBoxManage storageattach '$VB_NAME' --storagectl 'SATA Controller' --port 0 --device 0 --type hdd --medium '$FINAL_VDI'"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to attach '$FINAL_VDI' to '$VB_NAME'.${NC}"
        exit 1
    fi

    # Baseline resources (only for VMs created from a loose .vdi)
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --memory $DEFAULT_MEMORY --cpus $DEFAULT_CPUS --nic1 nat"
else
    echo -e "${RED}Error: No .ova, .vbox or .vdi file found inside '$ZIP_NAME'.${NC}"
    su - $vmuser -c "rm -rf '$STAGING_DIR'"
    exit 1
fi

# All VMs get their network set to NAT mode
su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --nic1 nat"

# macOS guests: apply VBox settings before first boot via vb.customize
if [ "$IS_MACOS" = true ]; then
    echo "Applying macOS-specific VirtualBox customizations ..."
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --cpuidset 00000001 000106e5 00100800 00000209 078bfbff"
    su - $vmuser -c "VBoxManage setextradata '$VB_NAME' 'VBoxInternal/Devices/efi/0/Config/DmiSystemProduct' 'iMac19,1'"
    su - $vmuser -c "VBoxManage setextradata '$VB_NAME' 'VBoxInternal/Devices/efi/0/Config/DmiSystemVersion' '1.0'"
    su - $vmuser -c "VBoxManage setextradata '$VB_NAME' 'VBoxInternal/Devices/efi/0/Config/DmiBoardProduct' 'Mac-AA95B1DDAB278B95'"
    su - $vmuser -c "VBoxManage setextradata '$VB_NAME' 'VBoxInternal/Devices/smc/0/Config/DeviceKey' 'ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc'"
    su - $vmuser -c "VBoxManage setextradata '$VB_NAME' 'VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC' '1'"
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --cpu-profile 'Intel Core i7-6700K'"
fi

# Forward the remote-access port
if [ "$IS_WINDOWS" = true ]; then
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --natpf1 'winrm,tcp,,${WINRM_FWD_PORT},,5985'"
elif [ "$IS_ANDROID" = true ]; then
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --natpf1 'adb,tcp,,${ADB_PORT},,5555'"
    if ! su - $vmuser -c "netstat -putona | grep -qi 'adb'"; then
        echo "ADB server is not running for $vmuser. Starting it..."
        su - $vmuser -c "adb start-server"
    else
        echo "ADB server is already running for $vmuser."
    fi
else
    su - $vmuser -c "VBoxManage modifyvm '$VB_NAME' --natpf1 'ssh,tcp,,${SSH_FWD_PORT},,22'"
fi

echo "Starting the virtual machine '$VB_NAME' ..."
su - $vmuser -c "vboxmanage startvm '$VB_NAME' --type headless"

su - $vmuser -c "vboxmanage list runningvms" | grep -q "\"$VB_NAME\""
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Virtual machine is not running and probably wasn't created correctly.${NC}"
    exit 1
else
    echo "Virtual machine is running."
fi

echo "Waiting for machine to boot, then will get info about OS, MAC and IP addresses ..."
boot_timeout=90
boot_interval=10
boot_waited=0
ipv4=$(su - $vmuser -c "VBoxManage guestproperty get '$VB_NAME' /VirtualBox/GuestInfo/Net/0/V4/IP")
while [ "$ipv4" = "No value set!" ] && [ "$boot_waited" -lt "$boot_timeout" ]; do
    sleep "$boot_interval"
    boot_waited=$((boot_waited + boot_interval))
    ipv4=$(su - $vmuser -c "VBoxManage guestproperty get '$VB_NAME' /VirtualBox/GuestInfo/Net/0/V4/IP")
done

mac=$(su - $vmuser -c "VBoxManage guestproperty get '$VB_NAME' /VirtualBox/GuestInfo/Net/0/MAC")
if [ "$mac" = "No value set!" ]; then
    mac="unknown"
else
    mac=$(echo $mac | awk -F'[ ]+' '{print $2}' | sed -E 's/(..)(..)(..)(..)(..)(..)/\1:\2:\3:\4:\5:\6/')
fi
if [ "$ipv4" = "No value set!" ]; then
    ipv4="unknown"
else
    ipv4=$(echo $ipv4 | awk -F'[ ]+' '{print $2}')
fi

echo $mac
echo $ipv4

su - $vmuser -c "cat > ${PATH_INFO}${VB_NAME}.json <<EOF
{
  \"vm_name\": \"$VB_NAME\",
  \"source\": \"$SOURCE\",
  \"link\": \"$LINK\",
  \"hash\": \"$IMAGE_HASH\",
  \"vagrant_box\": \"\",
  \"os_family\": \"\",
  \"os_type\": \"\",
  \"os_version\": \"\",
  \"IPv4\": \"$ipv4\",
  \"MAC\": \"$mac\"
}
EOF
"

su - $vmuser -c "python3 ~/${PATH_SCRIPTS}get_os_info_images.py -b '$VB_NAME' -u '$REMOTE_USER' -p '$REMOTE_PASSWORD' --ssh-port $SSH_FWD_PORT --winrm-port $WINRM_FWD_PORT --adb-port $ADB_PORT"

echo -e "${GREEN}Virtual machine created successfully.${NC}"

OS_INFO_FILE="${PATH_OS_INFO}${VB_NAME}/os_info.json"

json_content=$(su - $vmuser -c "cat $OS_INFO_FILE" 2>/dev/null)

if [ -z "$json_content" ]; then
    su - $vmuser -c "mkdir -p ${PATH_OS_INFO}${VB_NAME}/"
    su - $vmuser -c "touch ${OS_INFO_FILE}"
fi

OS_FAMILY=$(echo "$json_content" | jq -r '.Os_Family // empty' | tr ' ' '_')
OS_TYPE=$(echo "$json_content" | jq -r '.Os_Type // empty' | tr ' ' '_')
OS_VERSION=$(echo "$json_content" | jq -r '.Os_Version // empty' | tr ' ' '_')
echo $VB_NAME
echo $OS_FAMILY
echo $OS_TYPE
echo $OS_VERSION

su - $vmuser -c "./${PATH_SCRIPTS}update_info_file.sh $VB_NAME -f '$OS_FAMILY' -t '$OS_TYPE' -v '$OS_VERSION'"

su - $vmuser -c "vboxmanage controlvm '$VB_NAME' poweroff"
echo "Virtual machine powered off."
