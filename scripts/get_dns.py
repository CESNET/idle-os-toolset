import csv
import os
import subprocess
import sys
import argparse
import json
import pandas as pd

INFO_PATH = '/data/virtual_machines/vm_info'

# parse arguments
parser = argparse.ArgumentParser(description='Extract DNS requests from VM traffic (from CSV flow files)')
parser.add_argument('-n','--name', help='Name of the virtual machine to process.', required=True)
parser.add_argument('-o', '--output', help='Path to output .csv file, not required, default is "dns.csv" in the VM\'s traffic folder')
parser.add_argument('-f', '--flow-files', nargs="*",
                    help='Use given CSV file(s) with flwo data (default is to search all "flows.csv" files in the VM\'s traffic folder')
args = parser.parse_args()


def find_files(filename, search_path): # FIXME: use GLOB "????-??-??__*__*/traffic.pcap", so it's the same as in process_data.sh
    result = []
    for root, dirs, files in os.walk(search_path):
        if filename in files:
            result.append(os.path.join(root, filename))
    #print(f'Files: {result}')
    return result

# find info file
info_file_path = os.path.join(INFO_PATH, args.name + '.json')
if not os.path.exists(info_file_path):
    print('Info file not found:', info_file_path)
    sys.exit(1)
info = json.load(open(info_file_path))

# load information about VM from json file
os_family = info['os_family']
os_type = info['os_type']
os_version = info['os_version']
traffic_folder = info['traffic_folder']

# find flow files
if args.flow_files:
    flow_files = args.flow_files
else:
    flow_files = find_files('flows.csv', traffic_folder)

if args.output:
    output_file = args.output
else:
    output_file = os.path.join(traffic_folder, 'dns.csv')

# test write permission
try:
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
except Exception as e:
    print(e)
    sys.exit(1)

# Extract the DNS data
all_data = pd.DataFrame()
columns = ['string DNS_NAME']

for flow_file in flow_files:
    print(f"processing {flow_file} ...")
    df = pd.read_csv(flow_file, usecols=columns)
    # rename columns - remove data types (e.g. "string DNS_NAME" -> "DNS_NAME"
    df.rename(lambda x: x.split()[1], axis='columns', inplace=True)
    df = df.dropna().drop_duplicates()
    all_data = pd.concat([all_data, df])

all_data.drop_duplicates(inplace=True)

# Add labels
all_data.insert(0, 'os_version', os_version)
all_data.insert(0, 'os_type', os_type)
all_data.insert(0, 'os_family', os_family)

all_data.to_csv(output_file, index=False)

print(f'Finished, {len(all_data)} unique DNS requests saved to {output_file}')
