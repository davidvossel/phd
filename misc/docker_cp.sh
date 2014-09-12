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


if [ "$us" = "$node" ] || [ "localhost" = "$node" ]; then
	cp $1 $target_file
else
	cp $1 "/var/lib/docker/devicemapper/mnt/$(docker inspect --format {{.Id}} $node)/rootfs/$target_file"
fi
