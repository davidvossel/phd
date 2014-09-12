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

function respond()
{
	string=$1
	returnfile=$2
	node=$3
	pid=$4

	us="$(uname -n)"
	echo "Sending Response to source node: $node"
	echo "Return String: $string"
	if [ "$us" = "$node" ]; then
		write_file=$returnfile
	else
		write_file="/var/lib/docker/devicemapper/mnt/$(docker inspect --format {{.Id}} $node)/rootfs/$returnfile"
	fi

	echo "Return File: $write_file"
	echo "$string" > $write_file
	kill -9 $pid
}


while [ 1 -eq 1 ]; do
	sleep 1

	line="$(ps -aux | grep -m 1 [f]ence_docker_cts_helper)"

	if [ -z "$line" ]; then
		continue;
	fi
		
	pid=$(echo "$line" | awk '{ print $2; }')
	srcnode=$(echo "$line" | awk '{ print $13; }')
	action=$(echo "$line" | awk '{ print $14; }')
	returnfile=$(echo "$line" | awk '{ print $15; }')
	node=$(echo "$line" | awk '{ print $16; }')
	echo "Processing Request from $srcnode: PID=$pid Action=$action Returnfile=$returnfile Node=$node"

	case "$action" in
	list)
			
		containers=$(docker ps -a | awk '{print $NF}' | sed "s/^NAMES$//g")
		if [ $? -ne 0 ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		elif [ -z "$containers" ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		else
			respond "$containers" "$returnfile" "$srcnode" "$pid"
		fi

		;;

	status|monitor)

		if [ -z "$node" ]; then
			respond "success" "$returnfile" "$srcnode" "$pid"
			continue;
		fi
		res=$(docker inspect --format {{.State.Running}} $node)
		if [ $? -eq 0 ]; then
			respond "$res" "$returnfile" "$srcnode" "$pid"
		else
			respond "fail" "$returnfile" "$srcnode" "$pid"
		fi
		;;
	start|on)
		docker start $node
		if [ $? -ne 0 ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		fi
		respond "success" "$returnfile" "$srcnode" "$pid"
		;;

	stop|off)
		docker stop $node
		if [ $? -ne 0 ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		fi
		respond "success" "$returnfile" "$srcnode" "$pid"
		;;

	restart|reboot)
		docker stop $node
		if [ $? -ne 0 ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		fi
		docker start $node
		if [ $? -ne 0 ]; then
			respond "fail" "$returnfile" "$srcnode" "$pid"
		fi
		respond "success" "$returnfile" "$srcnode" "$pid"
		;;

	*)
		respond "fail" "$returnfile" "$srcnode" "$pid"
		;;
	esac
done
