#!/usr/bin/bash

user="vmuser"

# get the parameters
usage() {
    echo "Usage: $0 [-r|--running]"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0 
            ;;
        -r|--running)
            running="true"
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

if [ -n "$running" ]; then
    su - $user -c "vboxmanage list runningvms"
else
    su - $user -c "vboxmanage list vms"
fi
