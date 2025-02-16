import argparse
import csv
import os
import subprocess
import json

user = "vmuser"

# parse arguments
parser = argparse.ArgumentParser(description='Get VMs info')
parser.add_argument('-p', '--path', type=str, help='Path to the folder with VMs info', required=True)
parser.add_argument('-o', '--output', type=str, help='Output file', required=True)
args = parser.parse_args()

if not args.path:
    print("Please provide path to the folder with VMs info")
    exit()

# check if path exists
if not os.path.exists(args.path):
    print(f"Path {args.path} does not exist")
    exit()

# get VMs
vms = subprocess.run(['su', '-', user, '-c', 'vboxmanage list vms'], capture_output=True, text=True)    

# parse lines
lines = vms.stdout.split('\n')

vm_info = []

for line in lines:
    if line:
        info = {
            'name': '',
            'vm_hash': '',
            'os_family': '',
            'os_type': '',
            'os_version': '',
            'traffic_folder': '',
            'source': '',
            'vagrant_box': '',
            'hash': '',
            'link': ''

        }
        info['name'] = line.split()[0].replace('"', '')
        info['vm_hash'] = line.split()[1].replace('{', '').replace('}', '')


        try:
            with open(args.path + '/' + info['name'] + '.json') as f:
                data = json.load(f)
                info['os_family'] = data['os_family']
                info['os_type'] = data['os_type']
                info['os_version'] = data['os_version'] 
                info['traffic_folder'] = data['traffic_folder']
                info['source'] = data['source']
                if data['source'] == 'vagrant':
                    info['vagrant_box'] = data['vagrant_box']
                else:
                    info['hash'] = data['hash']
                    info['link'] = data['link']
                info
        except (FileNotFoundError, json.decoder.JSONDecodeError, KeyError):
            print(f"File {args.path + '/' + info['name'] + '.json'} not found or not valid")
            continue
        vm_info.append(info)

# order list by name
vm_info = sorted(vm_info, key=lambda x: x['name'])

# Determine the fieldnames (header)
fieldnames = vm_info[0].keys()

# Write to CSV file
with open(args.output, 'w', newline='') as f:
    f.write("|" + "|".join(fieldnames) + "|\n")
    f.write("|" + "|".join(["---"] * len(fieldnames)) + "|\n")
    for row in vm_info:
        f.write("| " + " | ".join(row.values()) + " |\n")

