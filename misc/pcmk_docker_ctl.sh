#!/bin/bash
. misc/pcmk_docker_utils.sh

function helptext() {
	echo "pcmk_docker_ctl.sh - A tool for controlling pcmk docker containers after they have been generated"
	echo ""
	echo "Usage: pcmk_docker_ctl.sh <action> <docker index>"
	echo "Example: restart docker1"
	echo "./pcmk_docker_ctl.sh restart 1"
	echo ""
	echo "========================"
	echo "---- Valid Actions: ----"
	echo "========================"
	echo "start:       start docker container"
	echo "stop:        stop docker container"
	echo "restart:     restart docker container"
	echo "pcmkstart:   start pacemaker. Will start container if container is down."
	echo "pcmkstop:    stop pacemaker ONLY. container will not stop"
	echo "pcmkrestart: retarts pacemaker, if container is down this is the same as pcmkstart"
	exit $1
}

if [ -z "$2" ]; then
	helptext
	exit 1
fi

action=$1
index=$2
container="${nodeprefix}${index}"

case "$action" in
	start)
		echo "starting $container"
		docker start $container
		;;
	stop)
		echo "stopping $container"
		docker stop $container
		;;
	restart)
		docker stop $container
		docker start $container
		;;
	pcmkstart)
		docker start $container
		launch_pcmk $index
		;;
	pcmkstop)
		docker stop $container
		docker start $container
		;;

	pcmkrestart)
		docker stop $container
		docker start $container
		launch_pcmk $index
		;;
	*)
		helptext
		;;


esac
