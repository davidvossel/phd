#!/bin/bash

#. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh

phd_ssh_cp()
{
	local src=$1
	local dest=$2
	local node=$3
	local fullcmd="scp -o ConnectTimeout=30 -o BatchMode=yes  $src $node:${dest}"

	timeout -s kill 60 $fullcmd
}

phd_ssh_cmd_exec()
{
	local cmd=$1
	local node=$2
	local fullcmd="ssh -o ConnectTimeout=30 -o BatchMode=yes -l root $node $cmd"

	timeout -s KILL 60 $fullcmd
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
