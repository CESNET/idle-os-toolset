import csv
import os
import subprocess
import sys
import argparse
import json
import pandas as pd



INFO_PATH = '/data/virtual_machines/vm_info'
update_all = False
output_file = None
output_file_all = "/data/virtual_machines/traffic/merged_tls_info.csv"

# parse arguments
parser = argparse.ArgumentParser(description='Extract TLS information from virtual machines managed by VirtualBox and save to CSV files.')
parser.add_argument('-n','--name', help='Name of the virtual machine to process. If not provided, all VMs will be processed.', default=None)
parser.add_argument('-o', '--output', help='Path to output .csv file, not required, default is traffic folder')
args = parser.parse_args()


def find_files(filename, search_path):
    result = []
    for root, dirs, files in os.walk(search_path):
        if filename in files:
            result.append(os.path.join(root, filename))
    print(f'Files: {result}')
    return result

def get_tls_info(name):
    global output_file, update_all

    # find info file
    info_file_path = os.path.join(INFO_PATH, name + '.json')
    if not os.path.exists(info_file_path):
        print('Info file not found:', info_file_path)
        sys.exit(1)
    info = json.load(open(info_file_path))
    traffic_folder = info['traffic_folder']

    # find flow files
    flow_files = find_files('flows.csv', traffic_folder)

    if not update_all:
        if args.output:
            output_file = args.output
        else:
            output_file = os.path.join(traffic_folder, 'tls.csv')

        if output_file==args.output and os.path.exists(output_file):
            print('Output file already exists:', output_file)
            sys.exit(1)

        # test write permission
        try:
            with open(output_file, 'w', newline='') as f:
                writer = csv.writer(f)
        except Exception as e:
            print(e)
            sys.exit(1)


    tls = pd.DataFrame()
    columns = ['uint16 TLS_VERSION', 'string TLS_ALPN', 'bytes TLS_JA3', 'string TLS_SNI']

    for flow_file in flow_files:
        df = pd.read_csv(flow_file, usecols=columns)
        df['uint16 TLS_VERSION'] = df['uint16 TLS_VERSION'].replace(0, pd.NA)
        df = df.dropna(how='all', subset=columns) 
        tls = pd.concat([tls, df])

    # load information about VM from json file
    os_family = info['os_family']
    os_type = info['os_type']
    os_version = info['os_version']

    tls.insert(0, 'os_version', os_version)
    tls.insert(0, 'os_type', os_type)
    tls.insert(0, 'os_family', os_family)

    return tls.drop_duplicates()

def get_vm_names():
    command = ["sudo", "-u", "vmuser", "VBoxManage", "list", "vms"]

    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    if result.returncode != 0:
        print("Error while getting VMs:", result.stderr.decode())
    
    return [line.split()[0].strip('"') for line in result.stdout.decode().splitlines()]


def main():
    global output_file
    global update_all
    global output_file_all

    if not args.name:
        global update_all
        update_all = True

        # get output file
        if args.output:
            output_file_all = args.output
            # check if exists
            if os.path.exists(output_file_all):
                print('Output file already exists:', output_file_all)
                sys.exit(1)
        
        # test write permission
        try:
            with open(output_file_all, 'w', newline='') as f:
                writer = csv.writer(f)
        except Exception as e:
            print(e)
            sys.exit(1)

        vm_names = get_vm_names()
        print(f'VM names: {vm_names}')
    
        tls_all = pd.DataFrame()
        for name in vm_names:
            tls = get_tls_info(name)
            tls_all = pd.concat([tls_all, tls])
        tls_all = tls_all.drop_duplicates()
        tls_all.to_csv(output_file_all, index=False)
        print(f'Finished, saved to {output_file_all}')
    else:
        tls = get_tls_info(args.name)
        tls.to_csv(output_file, index=False)
        print(f'Finished, saved to {output_file}')

    

if __name__ == '__main__':
    main()
