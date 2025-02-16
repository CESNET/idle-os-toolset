#!/usr/bin/bash

TRAFFIC_PATH='/data/virtual_machines/traffic/'
HTTP_FILE_NAME='http.csv'

# Show help and usage
usage() {
    echo "Merge all ${HTTP_FILE_NAME} files in folder ${TRAFFIC_PATH} into csv file."
    echo "Usage: $0 [-o output_file|--output output_file]"
    echo "Example: $0 -o merged_http.csv"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

if [ -z $output_file ]; then
    usage
fi

# finds all files named "data.csv"
files=$(find $TRAFFIC_PATH -type f -name $HTTP_FILE_NAME | sort)

# check if files exist
if [ -z "$files" ]; then
    echo "No files were found."
    exit 1
fi

# get header from the first file
first_file=$(echo "$files" | head -n 1)
cat "$first_file" > "$output_file"

tail -n +2 -q $(echo "$files" | tail -n +2) >> "$output_file"

echo "Successfully merged into $output_file"
