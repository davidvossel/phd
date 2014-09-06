#!/bin/bash

if [ -z "$2" ]; then
	echo 'usage - ./docker_cmd <docker container id> <cmd>'
fi 

echo "$2" | nsenter --target $(docker inspect --format {{.State.Pid}} ${1}) --mount --uts --ipc --net --pid
