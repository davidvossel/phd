#!/bin/bash

#. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh

# only top level resources
phd_rsc_parent_list()
{
	local cmd="cibadmin -Q --local --xpath '//primitive' --node-path | awk -F \"id='\" '{print \$2}' | awk -F \"'\" '{print \$1}' | uniq"

	phd_cmd_exec "$cmd" "$1"
}

# Only primitives
phd_rsc_raw_list()
{
	local cmd="crm_resource -l"

	phd_cmd_exec "$cmd" "$1"
}

# return the nodes a rsc is active on
phd_rsc_active_nodes()
{
	local rsc=$1
	local node=$2
	local cmd="crm_resource -W -r $rsc 2>&1 | sed 's/.*on: //g' | sed 's/.*is NOT running.*//g' | sed 's/.*No such device.*//g' | tr -d '\n'"

	phd_cmd_exec "$cmd" "$node"
}


phd_rsc_verify_is_active()
{
	local rsc=$1
	local timeout=$2
	local node=$3
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	active_list=$(phd_rsc_active_nodes "$rsc" "$node")
	while [ -z "$active_list" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to become active on ($active_node)"
			return 1
		fi
		sleep 1
		active_list=$(phd_rsc_active_nodes "$rsc" "$node")
	done

	return 0
}

# returns if rsc is active on a node or not.
# 0 active
# 1 not active
phd_rsc_verify_is_active_on()
{
	local rsc=$1
	local active_node=$2
	local timeout=$3
	local node=$4
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	while [ $? -ne 0 ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to become active on ($active_node)"
			return 1
		fi
		sleep 1
		echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	done

	return 0
}


# returns if rsc is stopped on a node or not.
# 0 active
# 1 not active
phd_rsc_verify_is_stopped_on()
{
	local rsc=$1
	local active_node=$2
	local timeout=$3
	local node=$4
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	while [ $? -eq 0 ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to become stop on ($active_node)"
			return 1
		fi
		sleep 1
		echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	done

	return 0
}


# returns whether or not a rsc is started in the cluster
# 0 started
# 1 not started
phd_rsc_is_started()
{
	local rsc=$1
	local node=$2
	local active_list
	local active_node

	active_list=$(phd_rsc_active_nodes "$rsc" "$node")
	if [ -z "$active_list" ]; then
		phd_log LOG_INFO "$rsc is not active"
		return 1
	fi
	return 0
}

phd_rsc_verify_start_all()
{
	local timeout=$1
	local node=$2
	local rsc_list=$(phd_rsc_raw_list "$node")
	local lapse_sec=0
	local stop_time=0
	local rsc
	local rc=1

	stop_time=$(date +%s)

	while [ $rc -ne 0 ]; do
		for rsc in $(echo $rsc_list); do
			phd_rsc_is_started $rsc $node
			rc=$?
			if [ $rc -ne 0 ]; then
				phd_log LOG_INFO "Waiting for $rsc to start"
				break
			fi
		done

		if [ $rc -eq 0 ]; then
			phd_log LOG_INFO "Success, all resources are active"
			return 0
		fi

		sleep 2
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resources to start"
			return 1
		fi
	done
	return 0
}

phd_rsc_verify_stop_all()
{
	local timeout=$1
	local node="$2"
	local lapse_sec=0
	local stop_time=0
	local cmd="crm_mon -X | grep 'active=\"true\"' -q"

	stop_time=$(date +%s)
	phd_cmd_exec "$cmd" "$node"
	while [ "$?" -eq "0" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resources to stop"
			return 1
		fi

		sleep 1
		phd_log LOG_DEBUG "still waiting to verify stop all"
		phd_cmd_exec "$cmd" "$node"
	done
	return 0
}

phd_rsc_stop_all()
{
	local node=$1
	local rsc_list=$(phd_rsc_parent_list "$node")
	local rsc

	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "stop all failed, unable retrieve resource list"
		return 1
	fi

	phd_log LOG_DEBUG "stopping all resources. $rsc_list on node $node"
	for rsc in $(echo $rsc_list); do
		phd_cmd_exec "pcs resource disable $rsc" "$node"
	done
}

phd_rsc_relocate()
{
	local rsc=$1
	local node=$2
	local cur_node=$(phd_rsc_active_nodes $rsc $node)

	if [ -z "$rsc" ]; then
		return 1
	fi

	cur_node=$(echo $cur_node | awk '{print $1}')
	if [ -z "$cur_node" ]; then
		return 1
	fi
	
	phd_cmd_exec "pcs resource defaults | grep resource-stickiness" "$node"
	if [ $? -ne 0 ]; then
		phd_cmd_exec "pcs resource defaults resource-stickiness=100" "$node"
	fi

	phd_log LOG_DEBUG "Moving $rsc away from node $cur_node"
	phd_cmd_exec "pcs resource move $rsc" "$node"
	phd_rsc_verify_is_stopped_on "$rsc" "$cur_node" 60 "$node"
	if [ $? -ne 0 ]; then
		return 1
	fi
	# verify it is active anywhere, we don't care where
	phd_rsc_verify_is_active "$rsc" 60 "$node"
	if [ $? -ne 0 ]; then
		return 1
	fi
	phd_cmd_exec "pcs resource clear $rsc" "$node"
	phd_log LOG_NOTICE "Resource $rsc successfully relocated from node $cur_node to node $(phd_rsc_active_nodes $rsc $node)"
	return 0
}

