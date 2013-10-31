#!/bin/bash
. ${PHDCONST_ROOT}/lib/utils.sh

pacemaker_cluster_stop()
{
	local nodes=$(definition_nodes)
	local node

	for node in $(echo $nodes); do
		phd_cmd_exec "pcs cluster stop" "$node"
		if [ "$?" -ne 0 ]; then
			phd_log LOG_ERR "Could not stop pacemaker on node $node"
			exit 1
		fi
		phd_cmd_exec "service corosync stop" "$node"
	done

}

pacemaker_cluster_start()
{
	local nodes=$(definition_nodes)
	local node

	for node in $(echo $nodes); do
		phd_cmd_exec "pcs cluster start" "$node"
		if [ "$?" -ne 0 ]; then
			phd_log LOG_ERR "Could not start pacemaker on node $node"
			exit 1
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

	phd_cmd_exec "pcs cluster setup --local phd-cluster $nodes" "$nodes"
	if [ "$?" -ne 0 ]; then
		phd_log LOG_ERR "Could not setup corosync config for pacemaker cluster"
		exit 1
	fi
}
