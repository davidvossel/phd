#!/bin/bash

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
