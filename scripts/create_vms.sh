#!/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NC='\e[0m'

dry_run=false

usage() {
    echo "Usage: $0 [-n | --dry-run] [-h | --help]"
    echo
    echo "Reads vm_list.csv from the current directory and creates a VM for each row"
    echo "(vagrant box or image), via new_vagrant.sh / new_image_vm.sh."
    echo
    echo "  -n, --dry-run   Don't create any VM. Instead, validate that everything"
    echo "                  create_vms.sh needs is in place: the LLM provider used by"
    echo "                  get_vm_names.py/get_os_info.py is reachable, and every"
    echo "                  'vagrant' row's box exists on Vagrant Cloud."
    echo "  -h, --help      Show this help message"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            usage
            ;;
    esac
done

# Checks that the LLM provider used by get_vm_names.py/get_os_info.py (Groq, via
# litellm) is configured and reachable, by running the same completion call those
# scripts make, with a minimal prompt.
check_llm_provider() {
    echo "Checking LLM provider (Groq, via litellm)..."
    python3 - <<'EOF'
import os
import sys

from dotenv import load_dotenv

load_dotenv(dotenv_path=os.path.join(os.getcwd(), ".env"))

if not os.getenv("GROQ_API_KEY"):
    print("  FAIL: GROQ_API_KEY is not set (checked environment and .env).")
    sys.exit(1)

try:
    from litellm import completion

    completion(
        model="groq/openai/gpt-oss-120b",
        fallbacks=["groq/openai/gpt-oss-20b"],
        messages=[{"role": "user", "content": "ping"}],
        max_tokens=1,
    )
except Exception as e:
    print(f"  FAIL: could not reach the LLM provider: {e}")
    sys.exit(1)

print("  OK: LLM provider reachable and API key accepted.")
EOF
}

# Checks whether a Vagrant box exists on Vagrant Cloud (app.vagrantup.com), without
# downloading it.
check_vagrant_box() {
    local box="$1"
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' "https://app.vagrantup.com/api/v1/box/${box}")
    if [ "$status" = "200" ]; then
        echo -e "  ${GREEN}OK: Vagrant box '${box}' found on Vagrant Cloud.${NC}"
        return 0
    else
        echo -e "  ${RED}FAIL: Vagrant box '${box}' not found on Vagrant Cloud (HTTP ${status}).${NC}"
        return 1
    fi
}

if [ -f vm_list.csv ]; then
  failures=0

  if [ "$dry_run" = true ]; then
    echo "Dry run: no VM will be created, only validating vm_list.csv."
    echo "-----------------------------------------------------------------"
    check_llm_provider || failures=$((failures + 1))
    echo "-----------------------------------------------------------------"
  fi

  first_line=true
  while IFS= read -u 3 -r line; do
    if [ "$first_line" = true ]; then
      first_line=false
      continue
    fi
    if [ -n "$line" ]; then
      type=$(echo "$line" | awk -F "," '{print $1}')
      name=$(echo "$line" | awk -F "," '{print $2}')
      vm_name=$(echo "$line" | awk -F "," '{print $3}')
      hash=$(echo "$line" | awk -F "," '{print $4}')
      remote_user=$(echo "$line" | awk -F "," '{print $5}')
      remote_password=$(echo "$line" | awk -F "," '{print $6}')
      img_source=$(echo "$line" | awk -F "," '{print $7}')
      link=$(echo "$line" | awk -F "," '{print $8}')

      case "$type" in
        vagrant)
          if [ "$dry_run" = true ]; then
            echo "Vagrant box ${name} (${vm_name}):"
            check_vagrant_box "$name" || failures=$((failures + 1))
          else
            echo "Creating virtual machine for vagrant box ${name} with name ${vm_name}..."
            ./new_vagrant.sh -v "$name" -b "$vm_name"
          fi
          ;;
        image)
          if [ "$dry_run" = true ]; then
            echo "Image ${name} (${vm_name}): skipped, dry-run only checks the LLM provider and Vagrant boxes."
          else
            echo "Creating virtual machine for ${name} with name ${vm_name}..."
            ./new_image_vm.sh -z "$name" -b "$vm_name" -u "$remote_user" -p "$remote_password" -H "$hash" -s "$img_source" -l "$link"
          fi
          ;;
        *)
          echo "Unknown type '${type}' for entry '${name}'. Skipping (expected 'vagrant' or 'image')."
          ;;
      esac
    fi
  done 3< vm_list.csv

  if [ "$dry_run" = true ]; then
    echo "-----------------------------------------------------------------"
    if [ "$failures" -eq 0 ]; then
      echo -e "${GREEN}Dry run passed: all checks OK.${NC}"
    else
      echo -e "${RED}Dry run found ${failures} issue(s). Fix them before running without --dry-run.${NC}"
      exit 1
    fi
  fi
else
  echo "vm_list.csv not found. Please create a file named vm_list.csv with the list of VMs you want to create, with a header row followed by lines in the format: type,name,vm_name,hash,user,password,source,link"
  echo "For 'vagrant' rows, hash,user,password,source,link are not needed and can be left empty."
fi
