# Changelog

All notable changes in this repository are documented in this file.

## [Unreleased]

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

- We sincerely thank the CESNET-idle-OS-traffic research authos for providing and curating this repository, which enables reproducible work on idle operating-system traffic analysis.
- This update focuses on improving usability and automation of the toolset so that creating and managing a set of virtual machines is more consistent and less manual.
- The main objective is to automate OS metadata collection during VM provisioning through LLM-assisted command generation/execution, followed by structured extraction of OS family, type, and version.
- Auxiliary CLI and GUI workflows were added to review and refine OS metadata after collection, supporting better data quality and easier validation.
- The network traffic capture set was also expanded by adding new virtual machines (19) listed in `vm_list_added.md`, with notable growth in Windows and macOS coverage.

