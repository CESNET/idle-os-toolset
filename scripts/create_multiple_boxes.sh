#!/usr/bin/bash

if [ -f vagrant_list.txt ]; then
  while read line; do
    if [ -n "$line" ]; then
      vagrant_box=$(echo "$line" | awk -F ";" '{print $1}')
      vm_name=$(echo "$line" | awk -F ";" '{print $2}')
      echo "Creating virtual machine for ${vagrant_box} with name ${vm_name}..."
      ./new_vagrant.sh -v "$vagrant_box" -b "$vm_name"
    fi
  done < vagrant_list.txt
else
  echo "Vagrant_list.txt not found. Please create a file named vagrant_list.txt with the list of vagrant boxes you want to create, one per line."
fi