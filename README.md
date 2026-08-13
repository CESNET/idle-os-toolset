
# CESNET-IDLE-OS-TRAFFIC Toolset

This is a set of tools used to create the [CESNET Idle OS traffic](https://zenodo.org/records/15004765) dataset.
The dataset contains captured network traffic of various operating systems (OS) in their idle state, i.e. without any user activity.

The toolset allows you to create a set of virtual machines (VM) in VirtualBox, run them for a specified amount of time, and capture the traffic they generate.
There are also scripts to process the data -- convert raw packet captures (PCAPs) to rich flow records using [ipfixprobe](https://cesnet.github.io/ipfixprobe/) and extract details of DNS, HTTP and TLS traffic.

Installation guide in [INSTALL.md](INSTALL.md).

Versions of the packages and tools are listed in [DEPENDENCIES.md](DEPENDENCIES.md).

---

**VM provider:** VirtualBox

For a list of available VMs, run the command `list_vms.sh`. To list only running VMs, run `list_vms.sh -r`. All scripts can be found in the `/data/virtual_machines/scripts/` folder. Captured traffic can be found in the `/data/virtual_machines/traffic/` folder (see the *Captured Data* section).


## Add or update information about a VM

Before running any VM and capturing its network traffic, the info file must be configured. To configure this file, you can use the script `scripts/update_info_file.sh`. Alternatively, you can configure this file manually. All files with information about VMs are stored in the folder `/data/virtual_machines/vm_info/`. In this folder, there is a JSON file for each VM; this file must have the same name as the VM in VirtualBox. The file must contain the following information:

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
./update_info_file.sh <vm_name> [-s source | --source source] [-l link | --link link] [-H hash | --hash hash] [-V vagrant_box | --vagrant_box vagrant_box] [-f os_family | --os_family os_family] [-t os_type | --os_type os_type] [-v os_version | --os_version os_version] [-i IPv4 | --IPv4 IPv4] [-m MAC | --MAC MAC] [-h | --help]
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

If the time to capture traffic is not given, traffic will be captured until the virtual machine is stopped. The `stop_vm.sh` script should be used to stop the capture because it also processes the captured data. Otherwise, the captured data will not be processed correctly.
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

You can also start VMs by position in the full VM list instead of by name, using an `N-M` range (1-based, e.g. `5-10`). This is handy for splitting a large fleet of VMs into smaller batches. Use `-w | --wait` to control the number of seconds to wait between starting each VM in the batch (default: 5 seconds), which helps avoid overloading the host when starting many VMs at once.

## Stop VM and capture

If the VM wasn't scheduled to power off when it was started, this script should be used to stop the VM and end capturing network traffic. Captured traffic is then available in the `traffic.pcap` file in corresponding VM directory. Before the capture is finalized, the script also uses `tshark` to strip malformed, short, or unreassembled packets from the pcap.

### Usage of the `stop_vm.sh` script:

```bash
stop_vm.sh <vm_name>
```

This script allows you to stop multiple virtual machines with a single command. You can specify the names of the virtual machines separated by commas (without spaces) as the `<vm_name>` argument. If you want to stop all running virtual machines, pass `all` as the `<vm_name>` argument.

## Capture traffic in batches

`capture_loop.sh` automates running `start_vm.sh` over several VM ranges, one batch at a time: it starts each range with a fixed capture time, waits until every VM in the batch has finished capturing and auto-stopped, and then moves on to the next range.

### Usage

```bash
capture_loop.sh --ranges N-M[,N-M...] -t capture_time (-m|-s|-H|-d) [-w wait_seconds] [-g] [-h]
```

| Short Option | Long Option | Description |
|--------------|-------------|-------------|
| -h           | --help      | Show help   |
| --ranges     | --ranges    | Comma-separated list of VM ranges to process, e.g. `1-20,21-40` |
| -t           | --time      | Time to capture traffic before each VM auto-stops, passed to `start_vm.sh` |
| -m           | --minutes   | Given time is in minutes (default) |
| -s           | --seconds   | Given time is in seconds |
| -H           | --hours     | Given time is in hours |
| -d           | --days      | Given time is in days |
| -w           | --wait      | Seconds to wait between starting each VM within a batch, passed to `start_vm.sh` |
| -g           | --graphic   | Start VMs in graphic mode |

## Start/stop a VM without capturing traffic

`boot_vm.sh` and `shutdown_vm.sh` start and stop VMs the same way as `start_vm.sh`/`stop_vm.sh`, but without capturing traffic or pcap processing. They're mainly used to boot and shut down VMs for Nmap OS fingerprinting scans where no traffic capture is needed.

### Usage

```bash
boot_vm.sh <vm_name|all|N-M> [-g | --graphic] [-h | --help]
shutdown_vm.sh <vm_name|all>
```

Both scripts accept the same `vm_name` forms as `start_vm.sh`/`stop_vm.sh`: a single name, a comma-separated list, `all`, or (for `boot_vm.sh`) an `N-M` position range.

## OS fingerprinting with Nmap

`nmap.sh` enumerates all registered VirtualBox VMs and, via an `arp-scan`, matches each one to the IP address of whichever VMs are currently running and reachable on the network, then runs `nmap -O` against each matched VM to get an OS fingerprint. Results, together with the ground-truth OS info from the corresponding `vm_info/<vm_name>.json` file, are appended to a CSV file. This script evaluates how well Nmap's OS detection matches the real, known OS of each VM.

### Usage

```bash
nmap.sh [--outdir <dir>] [--outfile <filename.csv>]
```

| Option    | Description                                  |
|-----------|-----------------------------------------------|
| --outdir  | Output directory for the CSV (default: `nmap/` directory) |
| --outfile | Output CSV filename (default: `nmap_results_<timestamp>.csv`) |

The output CSV contains: `vm_name, ip, mac, Os_Family, Os_Type, Os_Version, fingerprint_nmap`.

`nmap_batch_scan.sh` automates running `nmap.sh` over batches of VMs: for each VM range it boots the VMs and runs `nmap.sh` once, then shuts the VMs down before moving to the next range.

### Usage

```bash
nmap_batch_scan.sh --ranges N-M[,N-M...] [--wait SECONDS]
```

| Option    | Description                                                    |
|-----------|------------------------------------------------------------------|
| --ranges  | Comma-separated list of VM ranges to process (required) |
| --wait    | Seconds to wait after starting VMs before scanning, to let them boot (default: 30) |

## Check for duplicate VM MAC addresses

Cloning or importing VM images can leave duplicate NIC 1 MAC addresses across VMs, breaking ARP-based IP matching in `nmap.sh` and potentially confusing the host-only network. `check_vm_macs.sh` detects these duplicate MACs across all registered VMs and can regenerate a random MAC for each one.

### Usage

```bash
check_vm_macs.sh
```

## Resize a VM

`resize_vm.sh` changes the number of CPUs and/or the RAM of one or more powered-off VMs.

### Usage

```bash
resize_vm.sh <vm_name|all> [-c | --cpus <num_cpus>] [-r | --ram <ram_mb>] [-h | --help]
```

| Short Option | Long Option | Description |
|--------------|-------------|-------------|
| -c           | --cpus      | Set the number of CPUs |
| -r           | --ram       | Set the RAM size in MB |
| -h           | --help      | Show help |

Multiple VMs can be specified separated by commas, or `all` to resize every existing VM. The VM must be powered off before resizing.

## Set VM network mode

`set_network.sh` switches NIC 1 of one or more powered-off VMs between host-only (`vboxnet0`, used for Nmap fingerprinting) and NAT (used for giving the VM internet access and for capturing its network traffic).

### Usage

```bash
set_network.sh <vm_name|all> --hostonly | --nat
```

## VM configuration overview

`get_vms_config.sh` lists all registered VMs with their number of CPUs, memory size, and NIC 1 attachment mode, plus totals across all VMs.

### Usage

```bash
get_vms_config.sh
```

## Captured pcap statistics

`get_pcaps_stats.sh` walks the `traffic` folder and, for each `.pcap` file found, uses `tshark` to compute its duration, packet count, size, and protocol hierarchy. Each capture is matched to its VM to also record OS family, type, and version, and all results are written to a CSV file.

### Usage

```bash
get_pcaps_stats.sh [traffic_dir] [--outdir <dir>] [--outfile <filename.csv>]
```

## Data processing

After raw data was captured for one or all VMs, the `process_data.sh` script can be used to compute flow records and extract DNS, HTTP and TLS data from it.

```bash
process_data.sh <vm_name> [<vm_name> ...]
```

Specify one or more VMs whose data should be processed (`traffic.pcap` files in individual capture subdirectories). The script always processes all captures of the given VM.
To process data of all VMs, pass `all` as the `<vm_name>` argument.
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


## Generate VM Names for Vagrant Boxes or VM Images

When you have a list of Vagrant boxes and/or a list of VM images, and need suggested VM names, `get_vm_names.py` can help. It uses an AI model to suggest VM names in the `<os_family>_<os_version>` format. It reads `vm_list.csv` and, based on each row's `type` column (`vagrant` or `image`), automatically builds the right prompt for that row — no mode flag needed.

### Usage

```bash
python3 get_vm_names.py
```

The script reads `vm_list.csv` from the current directory and overwrites it, keeping the header and every column, only filling in blank `vm_name` values. Rows with `type` set to `vagrant` are suggested a name based on the Vagrant box (e.g. `ubuntu/bionic64` → `ubuntu_bionic`); rows with `type` set to `image` are suggested a name based on the zip file name (e.g. `manjaro_21.0.zip` → `manjaro_21.0`).

## Create Multiple VMs (Vagrant and Images)

To create multiple VMs at once from a list, use `create_vms.sh`. It reads `vm_list.csv` from the current directory and, for each row, calls `new_vagrant.sh` (if `type` is `vagrant`) or `new_image_vm.sh` (if `type` is `image`).

### Usage

```bash
./create_vms.sh [-n | --dry-run] [-h | --help]
```

Use `-n`/`--dry-run` to validate `vm_list.csv` without creating any VM: it checks that the LLM provider used by `get_vm_names.py`/`get_os_info.py` (Groq, via `litellm`) is reachable with the configured `GROQ_API_KEY`, and that every `vagrant` row's box actually exists on [Vagrant Cloud](https://app.vagrantup.com). `image` rows aren't checked further in dry-run mode.

The `vm_list.csv` file must exist in the current directory, with a header row followed by one row per VM in the following format:

```
type,name,vm_name,hash,user,password,source,link
```

| Column   | Description |
|----------|-------------|
| type     | `vagrant` or `image` |
| name     | For `vagrant`: the Vagrant box name (e.g. `ubuntu/focal64`). For `image`: name of the `.zip`/`.7z` file inside `vm_images/` |
| vm_name  | Name to give the virtual machine in VirtualBox (`<os>_<version>` format), can be left empty and filled in by `get_vm_names.py` |
| hash     | Hash of the zip file (format `algo:hash`, e.g. `sha256:...`). Not needed for `vagrant` rows |
| user     | Username for remote access (SSH/WinRM) inside the guest. Not needed for `vagrant` rows or Android images |
| password | Password for remote access (SSH/WinRM) inside the guest. Not needed for `vagrant` rows or Android images |
| source   | Source of the image (e.g. `osboxes.org`, `linuxvmimages.com`). Not needed for `vagrant` rows |
| link     | Link from where the image was downloaded. Not needed for `vagrant` rows |

For `vagrant` rows, `hash`, `user`, `password`, `source` and `link` can be left empty.

Example rows:
```
vagrant,ubuntu/focal64,ubuntu_focal,,,,,
image,manjaro_21.0.zip,manjaro_21.0,md5:daabd6555ad6c4776f6aa5f59dff05ea,manjaro,manjaro,linuxvmimages.com,https://www.linuxvmimages.com/images/manjaro-21/
```

## Add a New VM via Vagrant

 To add a new VM via Vagrant, the script `new_vagrant` can be used. This script will create a folder and `Vagrantfile` with configuration for the VM, and then the VM will be created. The script also creates a folder for storing files containing captured network traffic and a file with information about the VM, such as the used VagrantBox, IP address, MAC address, and OS. The script uses get_os_info.py to retrieve OS information and update_info_file.sh to include this information in the file.

### Usage:

```bash
new_vagrant [-v vagrant_name|--vagrant <vagrant_name>] [-b vbox_name|--virtualbox <vbox_name>]
```

Name the virtual machine in VirtualBox in the following format: `<os>_<version>`.

Example: `new_vagrant -v ubuntu/bionic64 -b ubuntu_bionic`

## Add a New VM from an Image (non-Vagrant)

For OS images that aren't distributed as Vagrant boxes (e.g. downloaded OVA/VBOX/VDI files from sites like osboxes.org or linuxvmimages.com), use `new_image_vm.sh` instead. It extracts a `.zip`/`.7z` file from the `vm_images/` folder, imports/registers it in VirtualBox, verifies the given hash, sets up NAT networking and remote-access port forwarding, then boots the VM. It then calls `get_os_info_images.py`, which connects to the guest to retrieve OS information, and `update_info_file.sh` to fill in the VM's OS information, before powering it off.

### Usage

```bash
new_image_vm.sh -z zip_name|--zip zip_name -b vbox_name|--virtualbox vbox_name -u user|--user user -p password|--password password -H hash|--hash hash -s source|--source source -l link|--link link
```

| Short Option | Long Option    | Description |
|--------------|----------------|-------------|
| -z           | --zip          | Name of the `.zip`/`.7z` file inside `vm_images/` (must contain an `.ova`, a `.vbox` VM folder, or a loose `.vdi`) |
| -b           | --virtualbox   | Name to give the virtual machine in VirtualBox |
| -u           | --user         | Username for remote access (SSH/WinRM) inside the guest (not needed for Android) |
| -p           | --password     | Password for remote access (SSH/WinRM) inside the guest (not needed for Android) |
| -H           | --hash         | Hash of the zip file (format `algo:hash`, e.g. `sha256:...`) |
| -s           | --source       | Source of the image (e.g. `osboxes.org`, `linuxvmimages.com`) |
| -l           | --link         | Link from where the image was downloaded |

All parameters are required except `-u`/`--user` and `-p`/`--password`, which aren't needed when the VM name contains `android`.

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

## Get OS Information of a VM

`get_os_info.py` uses an AI model to automatically determine the OS family, type, and version of a Vagrant VM. It generates the appropriate commands for the given box, executes them inside the VM (via `vagrant ssh`, `vagrant winrm`, or `adb` for Android), and then asks the AI to interpret the output and save the result.

The output files are stored in `~/data/virtual_machines/os_info/<vm_name>/`:
- `commands.json` – list of commands generated for the VM
- `commands_execute.json` – raw output of those commands
- `os_info.json` – final OS family, type, and version

### Usage of `get_os_info.py`

```bash
python3 get_os_info.py -v <vagrant_box> -b <vm_name>
```

| Short Option | Long Option      | Description                                              |
|--------------|------------------|----------------------------------------------------------|
| -v           | --vagrant_box    | Vagrant box name (e.g., `ubuntu/bionic64`)               |
| -b           | --vm_name        | Virtual machine name (e.g., `ubuntu_bionic`)             |

## View and Edit OS Information

`os_info.py` provides an interactive tool to view and edit the OS information and command outputs gathered by `get_os_info.py`. It can be launched in GUI mode (default, requires a graphical environment) or in CLI mode for terminal use. Once OS information is confirmed or edited and saved, the script automatically calls `update_info_file.sh` to update the VM info file.

### Usage of `os_info.py`

```bash
python3 os_info.py              # Launch GUI (default)
python3 os_info.py --gui        # Launch GUI (explicit)
python3 os_info.py --cli        # Launch CLI (terminal mode)
python3 os_info.py -h           # Show help
```

| Option  | Description                    |
|---------|--------------------------------|
| --gui   | Launch GUI mode (default)      |
| --cli   | Launch CLI mode (terminal)     |

## Funding

[FUNDING_CESNET]

This work was supported by project PID2025-175049OB-I00, funded by MICIU/AEI/10.13039/501100011033 and by ERDF/EU, and by the grant ED431C 2026/56 - Competitive Reference Groups GRC - funded by Xunta de Galicia (Spain). This work was also supported by CITIC, as a center accredited for excellence within the Galician University System and a member of the CIGUS Network, which receives subsidies from the Department of Education, Science, Universities, and Vocational Training of the Xunta de Galicia. Additionally, CITIC is co-financed by the EU through the FEDER Galicia 2021–27 operational program (Ref. ED431G 2023/01). This work was also supported by the “Formación de Profesorado Universitario” (FPU) grant from the Spanish Ministry of Universities to Rubén Pérez-Jove (Grant FPU22/04418).


