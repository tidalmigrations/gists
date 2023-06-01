#!/bin/bash

# Get the CPU count
cpu_count=$(nproc)

# Get the CPU name
cpu_name=$(cat /proc/cpuinfo | grep "model name" | uniq | awk -F':' '{print $2}' | sed 's/ //g')

# Get the hostname
hostname=$(hostname)

# Get the operating system
os=$(uname -s)

# Get the operating system version
os_version=$(uname -r)

# Print the information in CSV format
echo "CPU Count,CPU Name,Hostname,Operating System,Operating System Version"
echo "$cpu_count,$cpu_name,$hostname,$os,$os_version"
