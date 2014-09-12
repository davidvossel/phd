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

from="fedora"
#from="fedora"
pull=0
reuse=0
prev_image=""
image=""
run_cts=0
doc_opts=""
debug_container=0
rpmdir=""

function helptext() {
	echo "pcmk_docker_autogen.sh - A tool for generating pacemaker clusters locally with docker containers."
	echo ""
	echo "Usage: pcmk_docker_autogen.sh [options]"
	echo ""
	echo "Options:"
	echo "-c, --containers    Specify the number of containers to generate, defaults to $containers."
	echo "-d, --cleanup-only  Cleanup previous containers only."
	echo "-D, --debug-mode    Launch a container in interactive mode for testing."
	echo "-f, --from          Specify the FROM image to base the docker containers off of. Default is \"$from\""
	echo "-o, --doc-opts      Connection options to pass to docker daemon for every command"
	echo "-p, --pull          Force pull \"from\" image regardless if it exists or not."
	echo "-r, --reuse-image   Reuse image built from previous cluster if previous image is detected."
	echo "-R, --rpm-copu      Copy rpms in this directory to image for install".
	echo "-t, --cts-test      Run cts on docker instances"
	echo ""
	exit $1
}

while true ; do
	case "$1" in
	--help|-h|-\?) helptext 0;;
	-c|--containers) containers="$2"; shift; shift;;
	-d|--cleanup-only) prev_cluster_cleanup; exit 0;;
	-D|--debug-mode) debug_container=1; shift;;
	-f|--from) from="$2"; shift; shift;;
	-o|--doc-opts) doc_opts=$2; shift; shift;;
	-p|--pull) pull=1; shift;;
	-r|--reuse) reuse=1; shift;;
	-R|--rpm-copy) rpmdir=$2; shift; shift;;
	-t|--cts-test) run_cts=1; shift;;
	"") break;;
	*) helptext 1;;
	esac
done

# We have to re-launch docker with tcp ports open.
docker_setup
prev_cluster_cleanup
make_image
launch_containers
launch_pcmk_all
launch_cts

echo "DONE"
