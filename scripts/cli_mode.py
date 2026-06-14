import os
import json
import subprocess
import sys
import shlex


BASE_ROOT = os.path.expanduser("~")
OS_INFO_BASE = os.path.join(BASE_ROOT, "os_info")
TRAFFIC_BASE = os.path.join(BASE_ROOT, "traffic")


class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


def clear_screen():
    subprocess.run(['clear'] if os.name == 'posix' else ['cls'], check=False)


def print_header(text):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.CYAN}{text.center(60)}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.ENDC}\n")


def print_success(text):
    print(f"{Colors.GREEN}✓ {text}{Colors.ENDC}")


def print_error(text):
    print(f"{Colors.RED}✗ {text}{Colors.ENDC}")


def print_info(text):
    print(f"{Colors.YELLOW}ℹ {text}{Colors.ENDC}")


def load_vm_names():
    if not os.path.isdir(OS_INFO_BASE):
        return []
    names = []
    for entry in os.listdir(OS_INFO_BASE):
        full = os.path.join(OS_INFO_BASE, entry)
        if os.path.isdir(full):
            if (os.path.isfile(os.path.join(full, "os_info.json"))
                    or os.path.isfile(os.path.join(full, "commands_execute.json"))):
                names.append(entry)
    return sorted(names)


def display_vm_list(vm_names, current_idx=None):
    if not vm_names:
        print_error("No virtual machines found!")
        return
    
    print(f"{Colors.BOLD}Available Virtual Machines:{Colors.ENDC}\n")
    for idx, name in enumerate(vm_names):
        marker = f"{Colors.GREEN}>>>{Colors.ENDC}" if idx == current_idx else "   "
        print(f"{marker} {Colors.CYAN}[{idx+1}]{Colors.ENDC} {name}")
    print()


def load_os_info(vm_name):
    vm_dir = os.path.join(OS_INFO_BASE, vm_name)
    os_info_path = os.path.join(vm_dir, "os_info.json")
    
    if not os.path.isfile(os_info_path):
        return None
    
    try:
        with open(os_info_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print_error(f"Could not read {os_info_path}: {e}")
        return None


def load_commands_execute(vm_name):
    vm_dir = os.path.join(OS_INFO_BASE, vm_name)
    commands_path = os.path.join(vm_dir, "commands_execute.json")
    
    if not os.path.isfile(commands_path):
        return None
    
    try:
        with open(commands_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print_error(f"Could not read {commands_path}: {e}")
        return None


def display_both_info(vm_name):
    print_header(f"Complete Info: {vm_name}")
    
    # Display OS Info
    os_info = load_os_info(vm_name)
    if os_info:
        print(f"{Colors.BOLD}{Colors.CYAN}━━━ OS INFORMATION ━━━{Colors.ENDC}\n")
        print(f"  {Colors.CYAN}OS Family    :{Colors.ENDC} {os_info.get('Os_Family', 'N/A')}")
        print(f"  {Colors.CYAN}OS Type      :{Colors.ENDC} {os_info.get('Os_Type', 'N/A')}")
        print(f"  {Colors.CYAN}OS Version   :{Colors.ENDC} {os_info.get('Os_Version', 'N/A')}")
    else:
        print(f"{Colors.YELLOW}⚠ No os_info.json found for this machine.{Colors.ENDC}")
    
    print(f"\n{Colors.BOLD}{Colors.CYAN}━━━ COMMAND OUTPUT ━━━{Colors.ENDC}\n")
    
    # Display Command Output
    commands = load_commands_execute(vm_name)
    if commands:
        json_str = json.dumps(commands, indent=4, ensure_ascii=False)
        # Check if Windows - if so, replace \n with actual newlines
        if os_info and "windows" in str(os_info.get("Os_Family", "")).lower():
            json_str = json_str.replace('\\n', '\n')
        print(json_str)
    else:
        print(f"{Colors.YELLOW}⚠ No commands_execute.json found for this machine.{Colors.ENDC}")
    
    print()


def edit_os_info(vm_name):
    vm_dir = os.path.join(OS_INFO_BASE, vm_name)
    os.makedirs(vm_dir, exist_ok=True)
    os_info_path = os.path.join(vm_dir, "os_info.json")
    
    # Load current data
    os_info = load_os_info(vm_name) or {}
    
    print_header(f"Edit OS Info: {vm_name}")
    
    print(f"{Colors.BOLD}Current values:{Colors.ENDC}")
    print(f"  1. OS Family  : {os_info.get('Os_Family', '')}")
    print(f"  2. OS Type    : {os_info.get('Os_Type', '')}")
    print(f"  3. OS Version : {os_info.get('Os_Version', '')}")
    print()

    traffic_folder = os.path.join(TRAFFIC_BASE, os_info.get('Os_Family', '')+"__"+os_info.get('Os_Type', '')+"__"+os_info.get('Os_Version', '')) 
    # Edit each field
    print(f"{Colors.YELLOW}Enter new values (press Enter to skip):{Colors.ENDC}\n")
    
    family = input(f"OS Family [{os_info.get('Os_Family', '')}]: ").strip()
    if family:
        os_info['Os_Family'] = family
    
    type_ = input(f"OS Type [{os_info.get('Os_Type', '')}]: ").strip()
    if type_:
        os_info['Os_Type'] = type_
    
    version = input(f"OS Version [{os_info.get('Os_Version', '')}]: ").strip()
    if version:
        os_info['Os_Version'] = version
    
    # Save
    try:
        with open(os_info_path, "w", encoding="utf-8") as f:
            json.dump(os_info, f, indent=4, ensure_ascii=False)
        print_success(f"Data saved to {os_info_path}")
    except Exception as e:
        print_error(f"Could not save {os_info_path}: {e}")
        return
    os.removedirs(traffic_folder) if os.path.isdir(traffic_folder) else None
    # After saving, run: su - vmuser -c "./${PATH_SCRIPTS}update_info_file.sh $VB_NAME -f '$OS_FAMILY' -t '$OS_TYPE' -v '$OS_VERSION'"
    vmuser = "vmuser"
    path_scripts = "scripts"
    os_family = os_info.get("Os_Family", "")
    os_type = os_info.get("Os_Type", "")
    os_version = os_info.get("Os_Version", "")

    inner_cmd = (
        f"./{path_scripts}/update_info_file.sh "
        f"{shlex.quote(vm_name)} "
        f"-f {shlex.quote(os_family)} "
        f"-t {shlex.quote(os_type)} "
        f"-v {shlex.quote(os_version)}"
    )

    try:
        result = subprocess.run(
            ["su", "-", vmuser, "-c", inner_cmd],
            check=True,
            text=True,
            capture_output=True,
        )
        print_success("update_info_file.sh executed successfully.")
    except subprocess.CalledProcessError as e:
        print_error(
            "os_info.json saved, but update_info_file.sh failed: "
            + (e.stderr or str(e))
        )


def main_menu():
    vm_names = load_vm_names()
    if not vm_names:
        print_error(f"No virtual machines found in {OS_INFO_BASE}")
        return
    
    current_idx = 0
    
    while True:
        clear_screen()
        vm_name = vm_names[current_idx]

        # Show info for the current VM immediately
        print_header("OS Info & Commands Viewer (CLI)")
        display_vm_list(vm_names, current_idx)
        display_both_info(vm_name)

        # Simple controls to navigate and edit
        print(f"{Colors.BOLD}Controls:{Colors.ENDC}")
        print(f"  {Colors.CYAN}[n]{Colors.ENDC} Next VM")
        print(f"  {Colors.CYAN}[p]{Colors.ENDC} Previous VM")
        print(f"  {Colors.CYAN}[e]{Colors.ENDC} Edit OS Info (.json)")
        print(f"  {Colors.CYAN}[q]{Colors.ENDC} Quit")
        print()

        choice = input(f"{Colors.BOLD}Choice:{Colors.ENDC} ").strip().lower()

        if choice == 'n':
            # Next VM, stop at the last one
            if current_idx < len(vm_names) - 1:
                current_idx += 1

        elif choice == 'p':
            # Previous VM, stop at the first one
            if current_idx > 0:
                current_idx -= 1

        elif choice == 'e':
            edit_os_info(vm_name)
            input(f"{Colors.YELLOW}Press Enter to continue...{Colors.ENDC}")

        elif choice == 'q':
            print_info("Goodbye!")
            break

        else:
            print_error("Invalid option. Please try again.")
            input(f"{Colors.YELLOW}Press Enter to continue...{Colors.ENDC}")
