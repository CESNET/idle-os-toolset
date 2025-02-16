import csv
import pyshark
import os
import sys
import argparse
import json

INFO_PATH = '/data/virtual_machines/vm_info'

# parse arguments
parser = argparse.ArgumentParser(description='Extract HTTP requests from PCAP file')
parser.add_argument('-n', '--name', help='Name of VM', required=True)
parser.add_argument('-o', '--output', help='Path to output .csv file, not required, default is traffic folder')
parser.add_argument('-a', '--append', help='Append to existing file')
args = parser.parse_args()


def find_files(filename, search_path):
    result = []
    for root, dirs, files in os.walk(search_path):
        if filename in files:
            result.append(os.path.join(root, filename))
    print(f'Files: {result}')
    return result

# find info file
info_file_path = os.path.join(INFO_PATH, args.name + '.json')
if not os.path.exists(info_file_path):
    print('Info file not found:', info_file_path)
    sys.exit(1)
info = json.load(open(info_file_path))
traffic_folder = info['traffic_folder']

# find pcap files
if args.append:
    pcap_files = [args.append]
else:
    pcap_files = find_files('traffic.pcap', traffic_folder)


if args.output:
    output_file = args.output
else:
    output_file = os.path.join(traffic_folder, 'http.csv')

if not os.path.exists(output_file):
    try:
        with open(output_file, 'w') as f:
            f.write('os_family,os_type,os_version,user-agent,host,uri\n')
    except FileNotFoundError:
        print('Output file not found and could not be created')
        sys.exit(1)


http = set()

for pcap_file in pcap_files:
    print('Extracting HTTP requests from PCAP file...')

    # load pcap file
    capture = pyshark.FileCapture(pcap_file, display_filter='http.request')
    for packet in capture:
        try:
            http_layer = packet.http
            host = http_layer.get('host', 'None')
            user_agent = http_layer.get('user_agent', 'None')
            uri = http_layer.get('request_uri', 'None')

            if host == 'None' or user_agent == 'None' or uri == 'None':
                continue

            http.add((user_agent, host, uri))

        except AttributeError:
            continue

    capture.close()  
    print('HTTP requests extracted:', len(http))

# load information about VM from json file
os_family = info['os_family']
os_type = info['os_type']
os_version = info['os_version']

if args.append:
    reader = csv.reader(open(output_file, 'r'))
    first_line = True
    for row in reader:
        if first_line:
            first_line = False
            continue
        row = (row[3], row[4], row[5])
        http.add(row)

http = sorted(http)

with open(output_file, 'w') as f:
    f.write('os_family,os_type,os_version,user-agent,host,uri\n')
    for i in http:
        record = [os_family, os_type, os_version, f'"{i[0]}"', i[1], i[2]]
        f.write(','.join(record) + '\n')
