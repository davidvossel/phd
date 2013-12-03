#!/bin/bash

#. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh

phd_rsc_parent_list()
{
	local cmd="cibadmin -Q --local --xpath '//primitive' --node-path | awk -F \"id='\" '{print \$2}' | awk -F \"'\" '{print \$1}' | uniq"

	phd_cmd_exec "$cmd" "$1"
}

phd_rsc_verify_stop_all()
{
	local timeout=60
	local lapse_sec=0
	local stop_time=0
	local cmd="crm_mon -X | grep 'active=\"true\"' -q"
	local node="$1"

	stop_time=$(date +%s)
	phd_cmd_exec "$cmd" "$node"
	while [ "$?" -ne "0" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resources to stop"
			return 1
		fi

		sleep 1
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

