#!/usr/bin/bash
# Merge files with extracted L7 requests (dns.csv, http.csv, tls.csv) from individual OSes into a single file.

TRAFFIC_PATH='/data/virtual_machines/traffic'
output_dir="$TRAFFIC_PATH"

# Show help and usage
usage() {
    echo "Merge all CSV files with extracted requests of selected protocols (${TRAFFIC_PATH}/<OS>/*.csv) into a single file."
    echo "Usage:"
    echo "  $0 [-o output_dir|--output output_dir]"
    echo ""
    echo "The following files are search for and merged:"
    echo "  dns.csv"
    echo "  http.csv"
    echo "  tls.csv"
    echo "Output is stored into ${TRAFFIC_PATH}/merged_<proto>.csv (-o can be used to specify another directory)"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -o|--output)
            output_dir="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$output_dir" ]; then
    usage
    exit 1
fi

for proto in dns http tls
do
  echo "Merging ${proto}.csv files ..."
  output_file="$output_dir/merged_${proto}.csv"
  # find all files named "$proto.csv"
  files=$(find $TRAFFIC_PATH -maxdepth 2 -type f -name ${proto}.csv | sort)

  # check if files exist
  if [ -z "$files" ]; then
      echo "No files were found."
      continue
  fi

  # get the first file including header
  first_file=$(head -n 1 <<<"$files")
  cat "$first_file" > "$output_file"

  # append other files without headers
  tail -n +2 -q $(tail -n +2 <<<"$files") >> "$output_file"

  echo "Successfully merged into $output_file"
done
