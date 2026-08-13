# Changelog

All notable changes in this repository are documented in this file.


## [PR #1] - 2026-06-14

### Added

- New documentation files for setup and dependency/version reference (`INSTALL.md`, `DEPENDENCIES.md`).
- New OS information automation pipeline:
  - `scripts/get_os_info.py` to generate OS-detection commands, execute them in VM contexts, and persist normalized OS metadata.
  - `scripts/os_info.py` as the main entrypoint for OS info review/edit workflows.
  - `scripts/cli_mode.py` for terminal-based inspection and editing of OS metadata and command outputs.
  - `scripts/gui_mode.py` for Tkinter-based visual inspection and editing.
- New VM creation helpers:
  - `scripts/get_vm_names.py` to generate suggested VM names from Vagrant box names.
  - `scripts/create_multiple_boxes.sh` to create multiple VMs from a `vagrant_list.txt` file.
  - `scripts/vagrant_list.txt` as list input for batch VM creation.

### Changed

- `scripts/new_vagrant.sh` now performs richer provisioning flow:
  - Creates guest-specific Vagrant configuration for Linux, Windows, Android, and macOS scenarios.
  - Adds Android-specific handling (ADB connectivity and port forwarding).
  - Adds macOS-specific VirtualBox customization settings.
  - Executes OS detection (`get_os_info.py`) after VM creation and updates VM info via `update_info_file.sh`.
- `scripts/remove_vm.sh` now also cleans associated metadata paths (`os_info` directories and `vm_info` files), not only VirtualBox/Vagrant artifacts.
- Data-processing helper scripts received incremental updates (`get_dns.py`, `get_http.py`, `get_tls.py`, `process_data.sh`, `merge_csv_files.sh`, `get_vms_info.py`, `start_vm.sh`, `update_info_file.sh`).
- `README.md` was expanded with usage and workflow guidance for the new automation scripts and OS info tooling.

### Fixed

- Improved handling around Android guest connectivity/workflow during automation.
- Corrected and refined documentation references and usage instructions across branch updates.

### Notes

- We sincerely thank the CESNET-idle-OS-traffic research authors for providing and curating this repository, which enables reproducible work on idle operating-system traffic analysis.
- This update focuses on improving usability and automation of the toolset so that creating and managing a set of virtual machines is more consistent and less manual.
- The main objective is to automate OS metadata collection during VM provisioning through LLM-assisted command generation/execution, followed by structured extraction of OS family, type, and version.
- Auxiliary CLI and GUI workflows were added to review and refine OS metadata after collection, supporting better data quality and easier validation.
- The network traffic capture set was also expanded by adding 19 new virtual machines, with notable growth in Windows and macOS coverage.


## [PR #2] - Unreleased

### Added

- New VM creation from non-Vagrant images:
  - `scripts/new_image_vm.sh` to create a VM from a local `.zip`/`.7z` file containing an OVA, an exported VBOX folder, or a VDI disk, mirroring the `new_vagrant.sh` workflow for images downloaded from sites like osboxes.org or linuxvmimages.com.
  - `scripts/get_os_info_images.py`, the OS-detection counterpart to `get_os_info.py` for image-based VMs, connecting via SSH/WinRM/ADB.
- New management scripts:
  - `scripts/boot_vm.sh` and `scripts/shutdown_vm.sh` to start/stop VMs without touching traffic capture or pcap processing, used in nmap scripts.
  - `scripts/resize_vm.sh` to change the CPU count and/or RAM of one or more powered-off VMs.
  - `scripts/set_network.sh` to switch a VM's NIC 1 between host-only and NAT networking.
  - `scripts/get_vms_config.sh` to list CPUs, memory, and NIC 1 mode for all registered VMs, with totals.
  - `scripts/check_vm_macs.sh` to detect duplicate NIC 1 MAC addresses across VMs and optionally randomize them.
- New nmap scripts:
  - `scripts/nmap.sh` to enumerate all registered VMs and match whichever ones are running to their IP (via ARP scan + MAC lookup), then run `nmap -O` against them, comparing the result to the VM's known ground-truth OS.
  - `scripts/nmap_batch_scan.sh` to orchestrate `nmap.sh` over VM ranges: boot the range, scan it, then shut it down before moving to the next range.
- New captured-data statistics helper: `scripts/get_pcaps_stats.sh`, computing per-pcap duration, packet count, size, and protocol hierarchy, matched against each VM's OS info.
- New script `scripts/capture_loop.sh` that allows to run `start_vm.sh` over several VM ranges one batch at a time, waiting for each batch to finish capturing and auto-stop before starting the next.
- New VM creation flow: `scripts/vm_list.csv` lists both Vagrant boxes and non-Vagrant images to create, distinguished by a `type` column. `scripts/get_vm_names.py` reads this file and picks the right prompt per row based on `type`, and `scripts/create_vms.sh` reads it and calls `new_vagrant.sh` or `new_image_vm.sh` per row, also based on `type`.

### Changed

- `scripts/start_vm.sh` can now also select VMs by position in the full VM list using an `N-M` range, and gained `-w`/`--wait` to control the delay between starting each VM in a batch (default: 5 seconds).
- `scripts/stop_vm.sh` now strips malformed, short, or unreassembled packets from the pcap (via `tshark`) before finalizing the capture.  
- `scripts/get_vm_names.py` now reads/writes `vm_list.csv` instead of `vagrant_list.txt`: it requests names for rows with a blank `vm_name` and preserves every other column when rewriting the file, and picks a Vagrant-box or image-zip prompt per row based on its `type` column instead of only handling Vagrant boxes.
- `README.md` and `INSTALL.md` were updated with usage instructions and installation requirements for all the new scripts.
- `scripts/get_os_info.py` had its prompt improved for generating the OS-detection commands.

### Removed

- `scripts/vagrant_list.txt` and `scripts/create_multiple_boxes.sh`.

### Notes

- The Nmap fingerprinting pipeline support evaluating how well Nmap's own OS detection compares to the toolset's known ground-truth OS metadata, and give visibility into the size/composition of already-captured traffic.
- The new fleet-management scripts (`resize_vm.sh`, `set_network.sh`, `get_vms_config.sh`, `check_vm_macs.sh`) make it practical to reconfigure and audit large numbers of VMs at once, instead of doing it VM by VM through the VirtualBox GUI.
- The network traffic capture set was expanded with 19 new Android virtual machines, and all VMs from previous commits were combined into a single fleet.

