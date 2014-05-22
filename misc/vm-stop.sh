#!/bin/bash
# This is a terrible script.
# example
# ./vm-stop.sh rhel7-auto 4
# force stops vm rhel7-auto1 rhel7-auto2 rhel7-auto3 rhel7-auto4
# 

node_prefix=$1
instances=$2

if [ -z "$2" ]; then
	echo "usage - $0 <vm name prefix> <instances to restart>"
	exit 1
fi


for (( c=1; c <= $instances; c++ ))
do
	virsh destroy ${node_prefix}${c}
done

