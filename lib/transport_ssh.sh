#!/bin/bash

#. ${PHDCONST_ROOT}/lib/phd_utils_api.sh
PHD_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

phd_ssh_cp()
{
	local src=$1
	local dest=$2
	local node=$3
	local fullcmd="scp $PHD_SSH_OPTS $src $node:${dest}"

	timeout -s kill 120 $fullcmd
}

phd_ssh_cmd_exec()
{
	local cmd=$1
	local node=$2
	local fullcmd="ssh $PHD_SSH_OPTS -l root $node $cmd"

	timeout -s KILL 120 $fullcmd
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
