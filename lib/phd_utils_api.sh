#!/bin/bash

# Copyright (c) 2013 David Vossel <dvossel@redhat.com>
#                    All Rights Reserved.
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

. ${PHDCONST_ROOT}/lib/transport_ssh.sh
. ${PHDCONST_ROOT}/lib/transport_qarsh.sh

LOG_ERR="error"
LOG_ERROR="error"
LOG_NOTICE="notice"
LOG_INFO="info"
LOG_DEBUG="debug"

PHD_LOG_LEVEL=2
PHD_LOG_STDOUT=1
PHD_TMP_DIR="/var/lib/phd_state/"

LOG_UNAME=""
PHD_TRANSPORT=""

phd_detect_transport()
{
	if [ -z "$PHD_TRANSPORT" ]; then
		PHD_TRANSPORT=$(definition_transport)

		if [ -z "$PHD_TRANSPORT" ]; then
			# default to ssh
			PHD_TRANSPORT="ssh"
		fi

		case $PHD_TRANSPORT in
		ssh|qarsh) : ;;
		*) phd_exit_failure "Unknown Transport \"$PHD_TRANSPORT\". Valid values are ssh and qarsh" ;;
		esac

		phd_log LOG_NOTICE "Using $PHD_TRANSPORT as transport"
	fi
}

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
		eval echo $value
		return
	fi
	echo $value
}

phd_time_stamp()
{
	date +%b-%d-%T
}

phd_log()
{
	local priority=$1
	local msg=$2
	local node=$3
	local level=1
	local log_msg
	local enable_log_stdout=$PHD_LOG_STDOUT

	if [ -z "$msg" ]; then
		return
	fi

	if [ -z "$LOG_UNAME" ]; then
		LOG_UNAME=$(uname -n)
	fi

	if [ -z "$node" ]; then
		node=$LOG_UNAME
	fi

	case $priority in
	LOG_ERROR|LOG_ERR|LOG_WARNING) level=0;;
	LOG_NOTICE) level=1;;
	LOG_INFO) level=2;;
	LOG_DEBUG) level=3;;
	LOG_TRACE) level=4;;
	# exec output can only be logged to files
	LOG_EXEC) level=5; enable_log_stdout=0;;
	*) phd_log LOG_WARNING "!!!WARNING!!! Unknown log level ($priority)"
	esac

	log_msg="$priority: $node: $(basename ${BASH_SOURCE[1]})[$$]:${BASH_LINENO} - $msg"
	if [ $level -le $PHD_LOG_LEVEL ]; then
		if [ $enable_log_stdout -ne 0 ]; then
			echo "$log_msg"
		fi
	fi

	# log everything to log file
	if [ -n "$PHD_LOG_FILE" ]; then
		echo "$(phd_time_stamp): $log_msg" >> $PHD_LOG_FILE
	fi
}

phd_set_exec_dir()
{
	PHD_TMP_DIR=$1

	phd_log LOG_NOTICE "SCENARIO STATE DATA LOCATION $PHD_TMP_DIR "
	if [ -z "$PHD_LOG_FILE" ]; then
		phd_set_log_file "${PHD_TMP_DIR}/phd.log"
	fi
}

phd_enable_stdout_log()
{
	PHD_LOG_STDOUT=$1
}

phd_set_log_level()
{
	PHD_LOG_LEVEL="$1"
}

phd_set_log_file()
{
	PHD_LOG_FILE="$1"
	phd_log LOG_NOTICE "LOG FILES ARE AT $1"
}

phd_cmd_exec()
{
	local cmd=$1
	local nodes=$2
	local node
	local rc=1
	local output=""

	# execute locally if no nodes are given
	if [ -z "$nodes" ]; then
		phd_log LOG_EXEC "$cmd"
		output=$(eval $cmd 2>&1)
		rc=$?

		if [ -n "$output" ]; then
			echo $output
			phd_log LOG_EXEC "$output"
		fi
	else
		for node in $(echo $nodes); do
			phd_detect_transport
			phd_log LOG_EXEC "$node($PHD_TRANSPORT) - $cmd"

			case $PHD_TRANSPORT in
			qarsh)	output=$(phd_qarsh_cmd_exec "$cmd" "$node" 2>&1) ;;
			*)		output=$(phd_ssh_cmd_exec "$cmd" "$node" 2>&1) ;;
			esac
			rc=$?

			if [ -n "$output" ]; then
				echo $output
				phd_log LOG_EXEC "$output" "$node"
			fi
			if [ $rc -eq 137 ]; then
				phd_exit_failure "Timed out waiting for cmd ($cmd) to execute on node $node"
			fi
		done
	fi

	return $rc
}

phd_node_cp()
{
	local src=$1
	local dest=$2
	local nodes=$3
	local permissions=$4
	local node
	local rc
	
	# TODO - support multiple transports
	for node in $(echo $nodes); do
		phd_detect_transport
		phd_log LOG_DEBUG "copying file \"$src\" to node \"$node\" destination location \"$dest\""

		case $PHD_TRANSPORT in
		qarsh)	phd_qarsh_cp "$src" "$dest" "$node" ;;
		*)		phd_ssh_cp "$src" "$dest" "$node" ;;
		esac
		rc=$?
		
		if [ $rc -ne 0 ]; then
			phd_log LOG_ERR "failed to copy file \"$src\" to node \"$node\" destination location \"$dest\""
			return 1
		fi
		if [ -n "$permissions" ]; then
			phd_cmd_exec "chmod $permissions $dest" "$node"
		fi
	done

	return 0
}

phd_script_exec()
{
	local script=$1
	local dir=$(dirname $script)
	local nodes=$2
	local node
	local rc

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "executing script \"$script\" on node \"$node\""		
		phd_cmd_exec "mkdir -p $dir" "$node" > /dev/null 2>&1
		phd_node_cp "$script" "$script" "$node" "755" > /dev/null 2>&1
		output=$(phd_cmd_exec "$script" "$node")
		rc=$?
		echo "$output" | sed 's/ LOG_/\nLOG_/g'
	done
	return $rc
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

phd_test_assert()
{
	if [ $1 -ne $2 ]; then
		phd_log LOG_NOTICE "========================="
		phd_log LOG_NOTICE "====== TEST FAILURE ====="
		phd_log LOG_NOTICE "========================="
		phd_exit_failure "unexpected exit code $1, $3"
	fi	
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

phd_verify_connection()
{
	local nodes=$1

	for node in $(echo $nodes); do
		phd_cmd_exec "ls > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Unable to establish connection with node \"$node\"."
		fi
		phd_log LOG_DEBUG "Node ($node) is accessible"
	done
}

phd_random_node()
{
	local nodes=$(definition_nodes)
	local num_nodes=$(echo "$nodes" | wc -w)
	local ran_node_index=$(( ($RANDOM % $num_nodes) + 1 ))

	echo "$nodes" | cut -d ' ' -f $ran_node_index
}

phd_cluster_idle()
{
	local execnode=$1
	local nodes=$(definition_nodes)
	local node

	for node in $(echo $nodes); do
		phd_cmd_exec "crmadmin -S $node -t 10000 | grep S_IDLE -q" "$execnode"
		if [ $? -eq 0 ]; then
			return 0
		fi 
	done

	return 1
}

phd_wait_cluster_idle()
{
	local timeout=$1
	local execnode=$2
	local wait_time=$(date +%s)
	local rc=1
	local lapse_sec=0

	while [ $rc -ne 0 ]; do
		lapse_sec=`expr $(date +%s) - $wait_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERROR "Timed out waiting for cluster to become idle"
			return 1
		fi

		phd_cluster_idle "$execnode"
		rc=$?
		if [ $rc -ne 0 ]; then
			sleep 1
		fi
	done

	return $rc
}


