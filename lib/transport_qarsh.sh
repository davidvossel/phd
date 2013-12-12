#!/bin/bash

#. ${PHDCONST_ROOT}/lib/phd_utils_api.sh

phd_qarsh_cp()
{
	local src=$1
	local dest=$2
	local node=$3

	qacp $src root@${node}:${dest}
}

phd_qarsh_cmd_exec()
{
	local cmd=$1
	local node=$2

	qarsh -l root -t 120 $node $cmd
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
