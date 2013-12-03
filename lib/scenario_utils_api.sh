#!/bin/bash
. ${PHDCONST_ROOT}/lib/transport_ssh.sh

LOG_ERR="error"
LOG_ERROR="error"
LOG_NOTICE="notice"
LOG_INFO="info"
LOG_DEBUG="debug"

phd_clear_vars()
{
	local prefix=$1
	local tmp

	if [ -z "$prefix" ]; then
		phd_log LOG_ERR "no variable prefix provided"
		return 1
	fi

	for tmp in $(printenv | grep -e "^${prefix}_*" | awk -F= '{print $1}'); do
		unset $tmp
	done

	return 0
}

phd_get_value()
{
	local value=$1

	if [ "${value:0:1}" = "\$" ]; then
		echo $(eval echo $value)
		return
	fi
	echo $value
}

phd_log()
{
	echo "$1: $2"
}

phd_cmd_exec()
{
	local cmd=$1
	local nodes=$2
	local node

	# TODO - support multiple transports
	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "executing cmd \"$cmd\" on node \"$node\""		
		phd_ssh_cmd_exec "$cmd" "$node"
	done
}

phd_node_cp()
{
	local src=$1
	local dest=$2
	local nodes=$3
	local permissions=$4
	local node
	
	# TODO - support multiple transports
	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "copying file \"$src\" to node \"$node\" destination location \"$dest\""
		phd_ssh_cp "$src" "$dest" "$node"
		if [ -n "$permissions" ]; then
			phd_cmd_exec "chmod $permissions $dest" "$node"
		fi
	done
}

phd_script_exec()
{
	local script=$1
	local dir=$(dirname $script)
	local nodes=$2
	local node

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "executing script \"$script\" on node \"$node\""		
		phd_cmd_exec "mkdir -p $dir" "$node"
		phd_node_cp "$script" "$script" "$node" "755"
		phd_cmd_exec "$script" "$node"
	done
}

phd_exit_failure()
{
	local reason=$1

	if [ -z "$reason" ]; then
		reason="scenario failure"
	fi

	phd_log LOG_ERR "Exiting: $reason"
	exit 1
}

phd_wait_pidof()
{
	local pidname=$1
	local timeout=$2
	local lapse_sec=0
	local stop_time=0

	if [ -z "$timeout" ]; then
		timeout=60
	fi

	stop_time=$(date +%s)
	pidof $pidname 
	while [ "$?" -ne "0" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_exit_failure "Timed out waiting for $pidname to start"
		fi

		sleep 1
		pidof $pidname
	done

	return 0
}
