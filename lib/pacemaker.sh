#!/bin/bash
. ${PHDCONST_ROOT}/lib/scenario_utils_api.sh
. ${PHDCONST_ROOT}/lib/scenario_rsc_api.sh

pacemaker_kill_processes()
{
	local node=$1

	phd_log LOG_DEBUG "Killing processes on $node"

	phd_cmd_exec "killall -q -9 corosync aisexec heartbeat pacemakerd pacemaker-remoted ccm stonithd ha_logd lrmd crmd pengine attrd pingd mgmtd cib fenced dlm_controld gfs_controld" "$node"
}

pacemaker_cluster_stop()
{
	local nodes=$(definition_nodes)
	local rsc_stopped=0

	for node in $(echo $nodes); do
		phd_cmd_exec "yum list installed | grep pacemaker > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			continue
		fi
		phd_cmd_exec "yum list installed | grep pcs > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			phd_cmd_exec "yum install -y pcs" "$node"
		fi

		# if pacemaker is down, still execut pcs stop to make
		# sure corosync is down
		phd_cmd_exec "pcs cluster status" "$node" > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			phd_cmd_exec "pcs cluster stop" "$node" > /dev/null 2>&1
			phd_cmd_exec "service corosync stop" "$node" > /dev/null 2>&1
			pacemaker_kill_processes $node
			continue
		fi

		# Once we find a live node, make sure to stop
		# all resources before we shutdown nodes.
		# Resources like clvmd don't shutdown properly
		# if we start killing off nodes before clvmd stopped
		# everywhere
		if [ $rsc_stopped -eq 0 ]; then
			phd_rsc_stop_all "$node"
			phd_rsc_verify_stop_all "$node"
			if [ $? -eq 0 ]; then
				rsc_stopped=1
			fi
		fi

		phd_cmd_exec "pcs cluster stop" "$node" > /dev/null 2>&1
		if [ "$?" -eq 0 ]; then
			phd_cmd_exec "service corosync stop" "$node" > /dev/null 2>&1
		else
			phd_log LOG_ERR "Could not gracefully stop pacemaker on node $node"
			phd_log LOG_DEBUG "Force stopping $node"
		fi
		# always cleanup processes
		pacemaker_kill_processes $node
	done
}

pacemaker_cluster_start()
{
	local nodes=$(definition_nodes)
	local node

	for node in $(echo $nodes); do
		phd_cmd_exec "pcs cluster start" "$node"
		if [ "$?" -ne 0 ]; then
			phd_exit_failure "Could not start pacemaker on node $node"
		fi
	done

	node=$(definition_node "1")

	while true; do
		phd_log LOG_DEBUG "Attempting to determine if pacemaker cluster is up."
		phd_cmd_exec "cibadmin -Q > /dev/null 2>&1" "$nodes"
		if [ "$?" -eq 0 ]; then
			break
		fi
	done
}

pacemaker_cluster_clean()
{
	local nodes=$(definition_nodes)

	phd_cmd_exec "rm -rf /var/lib/pacemaker/cib/* /var/lib/pacemaker/cores/* /var/lib/pacemaker/blackbox/* /var/lib/pacemaker/pengine/*" "$nodes"
}

pacemaker_cluster_init()
{
	local nodes=$(definition_nodes)

	phd_cmd_exec "pcs cluster setup --local --name phd-cluster $nodes" "$nodes"
	if [ "$?" -ne 0 ]; then
		phd_exit_failure "Could not setup corosync config for pacemaker cluster"
	fi
}
