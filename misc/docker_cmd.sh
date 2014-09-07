#!/bin/bash

if [ -z "$2" ]; then
	echo 'usage - ./docker_cmd <docker container id> <cmd>'
fi 

host=$1
shift;

echo "$@" | nsenter --target $(docker inspect --format {{.State.Pid}} ${host}) --mount --uts --ipc --net --pid
