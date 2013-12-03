#!/bin/bash

#. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh

phd_ssh_script_exec()
{
	local script=$1
	local nodes=$2
	local dir=$(dirname $script)
	local node

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "executing script \"$script\" on node \"$node\""		
		ssh -l root $node mkdir -p $dir
		scp $script $node:$script
		ssh -l root $node "chmod 755 $script"
		ssh -l root $node "$script"
	done
}

phd_ssh_cp()
{
	local src=$1
	local dest=$2
	local nodes=$3
	local node

	for node in $(echo $nodes); do
		scp $src $node:${dest}
	done
}

phd_ssh_cmd_exec()
{
	local cmd=$1
	local nodes=$2
	local node

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "executing cmd \"$cmd\" on node \"$node\""		
		ssh -l root $node "$cmd"
	done
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
