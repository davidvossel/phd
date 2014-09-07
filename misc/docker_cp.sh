#!/bin/bash

if [ -z "$2" ]; then
	echo 'usage - ./docker_cp <src> <target>'
	exit 1
fi 

us="$(uname -n)"
target_file="$(echo $2 | awk -F: '{print $2}')"

target_dst="$(echo $2 | awk -F: '{print $1}')"
node="$(echo $target_dst | awk -F@ '{print $2}')"

if [ -z "$node" ]; then
	node=$target_dst
fi


if [ "$us" = "$node" ]; then
	cp $1 $target_file
else
	cp $1 "/var/lib/docker/devicemapper/mnt/$(docker inspect --format {{.Id}} $node)/rootfs/$target_file"
fi
