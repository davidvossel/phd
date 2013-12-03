#!/bin/bash

#. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh

phd_ssh_cp()
{
	local src=$1
	local dest=$2
	local node=$3

	scp $src $node:${dest}
}

phd_ssh_cmd_exec()
{
	local cmd=$1
	local node=$2

	ssh -l root $node "$cmd"
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
