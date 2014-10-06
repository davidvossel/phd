#!/bin/bash
#
# Copyright (c) 2014 David Vossel <dvossel@redhat.com>
#					All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Further, this software is distributed without any warranty that it is
# free of the rightful claim of any third person regarding infringement
# or the like.  Any license provided herein, whether implied or
# otherwise, applies only to this software file.  Patent licenses, if
# any, provided herein do not apply to combinations of this program with
# other software, or any other product whatsoever.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston MA 02111-1307, USA.
#
#######################################################################

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
