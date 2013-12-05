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

# returns if rsc is active on a node or not.
# 0 active
# 1 not active
phd_rsc_verify_is_active_on()
{
	local rsc=$1
	local active_node=$2
	local node=$3
	local active_list=$(phd_rsc_active_nodes "$rsc" "$node")

	echo "$active_list" | grep -q "$active_node"
	# TODO externally verify rsc is running on the node as well
	#for active_node in $(echo $active_list); do
		# 
	#done

	return $?
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

