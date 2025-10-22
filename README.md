
# CESNET-IDLE-OS-TRAFFIC Toolset

This is a set of tools used to create the [CESNET Idle OS traffic](https://zenodo.org/records/15004765) dataset.
The dataset contains captured network traffic of various operating systems (OS) in their idle state, i.e. without any user activity.

The toolset allows to create a set of virtual machines (VM) in VirtualBox, run them for a specified amount of time and capture the traffic they generate.
There are also scripts to process the data -- convert raw packet captures (PCAPs) to rich flow records using [ipfixprobe](https://cesnet.github.io/ipfixprobe/) and extract details of DNS, HTTP and TLS traffic.


---

**VM provider:** VirtualBox

For a list of available VMs, run the command `list_vms.sh`. To list only running VMs, run `list_vms.sh -r`. All scripts can be found in the `/data/virtual_machines/scripts/` folder. Captured traffic can be found in the `/data/virtual_machines/traffic/` folder (see the *Captured Data* section).


## Add or update information about a VM

Before running any VM and capturing its network traffic, the info file must be configured. To configure this file, you can use the script `scripts/update_vm_info.sh`. Alternatively, you can configure this file manually. All files with information about VMs are stored in the folder `/data/virtual_machines/vm_info/`. In this folder, there is a JSON file for each VM; this file must have the same name as the VM in VirtualBox. The file must contain the following information:

```json
{
	"vm_name": <vm_name>,
	"source": <source>, 
	"link": <link>,
	"hash": <hash_algorithm>:<hash>,
	"vagrant_box": <vagrant_box>,
	"os_family": <os_family>,
	"os_type": <os_type>,
	"os_version": <os_version>,
	"IPv4": <ipv4>,
	"MAC": <mac>,
	"traffic_folder": <traffic_folder>
}
```

Fields `vm_name`, `source`, `os_family`, `os_type`, and `os_version` are required. VM traffic capture cannot be started without this information. If the source is Vagrant, `vagrant_box` is required, but `link` and `hash` can be empty. If the source is anything else, `link` and `hash` must be filled in before running the machine.

### Usage of `update_info_file.sh` Script

This script automatically adds the given information to the info file of a particular VM.

```bash
./update_info_file.sh vm_name [-s source | --source source] [-l link | --link link] [-H hash | --hash hash] [-f os_family | --os_family os_family] [-t os_type | --os_type os_type] [-v os_version | --os_version os_version] [-i IPv4 | --IPv4 IPv4] [-m MAC | --MAC MAC] [-h | --help]
```

| Short Option | Long Option        | Description                                           |
|--------------|---------------------|-------------------------------------------------------|
| -s           | --source            | Source of the image (e.g., vagrant, osboxes.org)    |
| -l           | --link              | Link from where the image was downloaded             |
| -H           | --hash              | Hash of the image (e.g., sha256:hash, md5:hash)      |
| -V           | --vagrant_box       | Name of the vagrant box                              |
| -f           | --os_family         | Family of the operating system (e.g., windows, linux, android, macos) |
| -t           | --os_type           | Type of the operating system (e.g., debian, ubuntu, centos, fedora) |
| -v           | --os_version        | Version of the operating system                      |
| -i           | --IPv4              | IPv4 address of the virtual machine                  |
| -m           | --MAC               | MAC address of the virtual machine                   |
| -h           | --help              | Show help                                            |

## Start VM and capture traffic

To capture the network traffic of a VM, there is a script that starts the VM and stores the captured traffic in a file. There are multiple options for running this script and starting the VM:
 - Starting the VM and capturing traffic
 - Starting the VM with a GUI and capturing traffic
 - Starting the VM and capturing traffic, with a planned end of running and capturing

### Usage of the script: 

```bash
start_vm <vm_name> [-t capture_time | --time capture_time] [-g | --graphic] [-h | --help] [-m | --minutes] [-s | --seconds] [-H | --hours] [-d | --days]
```

This script allows you to start multiple virtual machines with a single command. You can specify the names of the virtual machines separated by commas (without spaces) as the `<vm_name>` argument. If you want to start all available virtual machines, pass `all` as the `<vm_name>` argument.

If the time to capture traffic is not given, traffic will be captured until the virtual machine is stopped. A script `stop_vm.sh` should be used to stop the capture because it also processes the captured data.  Otherwise, the captured data will not be processed correctly.
If the time to capture traffic is given, the virtual machine will run and traffic will be captured for the given time.
        
| Short Option | Long Option | Description |
|--------------|-------------|-------------|
| -h           | --help      | Show help   |
| -g           | --graphic   | VM will be started with a GUI in a new window |
| -t           | --time      | Time to capture traffic in minutes |
| -s           | --seconds   | Given time is in seconds |
| -m           | --minutes   | Given time is in minutes (default) |
| -H           | --hours     | Given time is in hours |
| -d           | --days      | Given time is in days |

## Stop VM and capture

If the power-off of the VM wasn't planned when starting the VM, this script should be used to stop the VM and end capturing network traffic. Captured traffic is then available in the `traffic.pcap` file in corresponding VM directory.

### Usage of the `stop_vm.sh` script:

```bash
stop_vm.sh <vm_name>
```

This script allows you to stop multiple virtual machines with a single command. You can specify the names of the virtual machines separated by commas (without spaces) as the `<vm_name>` argument. If you want to stop all running virtual machines, pass `all` as the `<vm_name>` argument.


## Data processing

After raw data was captured for one or all VMs, the `process_data.sh` script can be used to compute flow records and extract DNS, HTTP and TLS data from it.

```bash
process_data.sh <vm_name> [<vm_name> ...]
```

Specify one or more VMs whose data should be processed (`traffic.pcap` files in individual capture subdirectories). The script always processes all captures of given VM.
To process data of all VMs, pass `all` the `<vm_name>` argument.
To list names of all defined VMs, pass `--list`.

The script first computes flow data from each capture (`traffic.pcap` file) of given VM(s). The [ipfixprobe](https://ipfixprobe.cesnet.cz/) exporter with several plugins is used.

Then, `get_dns.py`, `get_http.py` and `get_tls.py` scripts are called to extract data about selected application-layer requests made by the VM, which get written into `dns.csv`, `http.csv` and `tls.csv` files. If there are multiple captures (`.pcap` files) from one VM, these CSV files contain requests from all of them (unique entries only).

The `get_*.py` scripts normally aren't run directly. If you need them, the `--help` parameter will tell you how to use them.

## Merging CSV files

When data from all VMs are processed, the `merge_csv_files.sh` script can be used to merge data of application-layer requests of individual OSes (VMs) into a single one.

Files `merged_dns.csv`, `merged_http.csv` and `merged_tls.csv` are created, containing the following fields:

```
merged_dns.csv:
  os_family, os_type, os_version, DNS_NAME

merged_http.csv:
  os_family, os_type, os_version, user-agent, host, uri

merged_tls.csv:
  os_family, os_type, os_version, TLS_VERSION, TLS_ALPN, TLS_JA3, TLS_SNI
```


## Add a New VM via Vagrant

A new virtual machine can be added manually via the VirtualBox manager or via Vagrant. To add a new VM via Vagrant, the script `new_vagrant` can be used. This script will create a folder and `Vagrantfile` with configuration for the VM, and then the VM will be created. The script also creates a folder for storing files containing captured network traffic and a file with information about the VM, such as the used VagrantBox, IP address, MAC address, and OS.

### Usage:

```bash
new_vagrant [-v vagrant_name|--vagrant <vagrant_name>] [-b vbox_name|--virtualbox <vbox_name>]
```

Name the virtual machine in VirtualBox in the following format: `<os>_<version>`.

Example: `new_vagrant -v ubuntu/bionic64 -b ubuntu_bionic`

## Remove a VM

To remove an existing VM, use the script `remove_vm`. The VM will be removed from VirtualBox along with all files. If the VM has a folder with a `Vagrantfile`, this folder will be removed as well.

### Usage

```bash
remove_vm <vm_name>
```

## Captured Data

Files storing captured network traffic of the VM are stored in the `/data/virtual_machines/traffic/` folder. In this folder, there is also a separate folder for each OS. Folders are named `<os_family>__<os_type>__<os_version>`. In each folder, there are folders for each traffic capture `<data>__<source>__<identifier>`. If source is Vagrant then identifier is name of Vagrant box otherwise it's first 6 characters of hash.In each of these folders, there is also a file `info.json` where the basic information about the VM and traffic capture is stored. In these folders are also stored files with captured traffic. After capturing the network traffic from PCAP file is processed and `http.csv` and `tls.csv` files are created.

Example of folder hierarchy:
```
 - /data/virtual_machines/traffic/
	 - linux__ubuntu__23.10/
		 - 2024-07-01__vagrant__ubuntu_mantic64/
		 	 - info.json
			 - flows.csv
			 - traffic.pcap
		 - 2024-08-01__vagrant__ubuntu_mantic64/
		 	 - info.json
			 - flows.csv
			 - traffic.pcap
		 - tls.csv
		 - http.csv
	 - linux__manjaro__22.0/
		 - 2024-07-01__linuxvmimages.com__fc7a69/
		 	 - info.json
			 - flows.csv
			 - traffic.pcap
		 - tls.csv
		 - http.csv
```

## List of available VMs

`list_vms.sh` is a script listing available virtual machines. Use `-r` to list currently running virtual machines.

### Usage

```bash
list_vms.sh <vm_name> [-r | --running]
```

## Information about available virtual machines

All available virtual machines are listed in file `vm_list.md` with all available information. To update this file `get_vms_info.py` can be used. Script gets names of all available VirtualBox VMs and loads information about them from their info files.

### Usage of `get_vms_info.py`

```bash
python3 get_vms_info.py [-p | --path] [-o | --output]
```

| Short Option | Long Option | Description |
|--------------|-------------|-------------|
| -p           | --path      | Path to the folder with VMs info files |
| -o           | --output    | Output Markdown file |



