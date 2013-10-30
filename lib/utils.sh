#!/bin/bash
. ${PHDCONST_ROOT}/lib/transport_ssh.sh

LOG_ERR="error"
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

	# TODO - support multiple transports
	phd_ssh_cmd_exec "$cmd" "$nodes"
}

phd_script_exec()
{
	local script=$1
	local nodes=$2

	# TODO - support multiple transports
	phd_ssh_script_exec $script "$nodes"
}
