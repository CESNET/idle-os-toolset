import csv
import pyshark
import os
import sys
import argparse
import json

INFO_PATH = '/data/virtual_machines/vm_info'

# parse arguments
parser = argparse.ArgumentParser(description='Extract HTTP requests from traffic capture files')
parser.add_argument('-n', '--name', help='Name of VM', required=True)
parser.add_argument('-o', '--output',
                    help='Path to output .csv file (default is "http.csv" in the VM\'s traffic folder)')
parser.add_argument('-f', '--pcap-files', nargs="*",
                    help='Use given PCAP file(s) (default is to search all "traffic.pcap" files in the VM\'s traffic folder')
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

# find pcap files
if args.pcap_files:
    pcap_files = args.pcap_files
else:
    pcap_files = find_files('traffic.pcap', traffic_folder)


if args.output:
    output_file = args.output
else:
    output_file = os.path.join(traffic_folder, 'http.csv')

http = set()

for pcap_file in pcap_files:
    print(f'processing {pcap_file} ...')

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

http = sorted(http)

with open(output_file, 'w') as f:
    f.write('os_family,os_type,os_version,user-agent,host,uri\n')
    for i in http:
        record = [os_family, os_type, os_version, f'"{i[0]}"', i[1], i[2]]
        f.write(','.join(record) + '\n')

print(f'Finished, {len(http)} unique HTTP requests stored into "{output_file}"')
