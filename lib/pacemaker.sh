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


. ${PHDCONST_ROOT}/lib/phd_utils_api.sh
. ${PHDCONST_ROOT}/lib/phd_rsc_api.sh

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
		phd_cmd_exec "yum list installed 2>&1 | grep -q 'pacemaker'" "$node"
		if [ $? -ne 0 ]; then
			continue
		fi
		phd_cmd_exec "yum list installed 2>&1 | grep 'grep pcs'" "$node"
		if [ $? -ne 0 ]; then
			phd_cmd_exec "yum install -y pcs > /dev/null 2>&1" "$node"
		fi

		# if pacemaker is down, still execut pcs stop to make
		# sure corosync is down
		phd_cmd_exec "pcs cluster status > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			phd_log LOG_INFO "Pacemaker already stopped on node $node"
			phd_cmd_exec "pcs cluster stop > /dev/null 2>&1" "$node"
			phd_cmd_exec "service corosync stop > /dev/null 2>&1" "$node"
			pacemaker_kill_processes $node
			continue
		fi

		# Once we find a live node, make sure to stop
		# all resources before we shutdown nodes.
		# Resources like clvmd don't shutdown properly
		# if we start killing off nodes before clvmd stopped
		# everywhere
		if [ $rsc_stopped -eq 0 ]; then
			phd_log LOG_INFO "Stopping all resources in cluster before destroying cluster"
			phd_rsc_stop_all "$node"
			phd_rsc_verify_stop_all 120 "$node"
			if [ $? -eq 0 ]; then
				rsc_stopped=1
			fi
		fi

		phd_log LOG_INFO "Stopping pacemaker on node $node"
		phd_cmd_exec "pcs cluster stop > /dev/null 2>&1" "$node"
		if [ "$?" -eq 0 ]; then
			phd_cmd_exec "service corosync stop > /dev/null 2>&1" "$node"
		else
			phd_log LOG_ERR "Could not gracefully stop pacemaker on node $node"
			phd_log LOG_INFO "Force stopping $node"
		fi
		# always cleanup processes
		pacemaker_kill_processes $node
	done
}

# verify all nodes are active
pacemaker_verify_nodes()
{
	local nodes=$(definition_nodes)
	local node
	local execnode=$(definition_node "1")

	for node in $(echo $nodes); do
		phd_cmd_exec "crm_mon -X | grep '$node.*online=.true' -q" "$execnode"
		if [ $? -ne 0 ]; then
			phd_log LOG_INFO "waiting for $node to come online"
			return 1
		fi
	done
	return 0
}

pacemaker_cluster_start()
{
	local nodes=$(definition_nodes)
	local node
	local timeout=120
	local lapse_sec=0
	local start_time=0

	for node in $(echo $nodes); do
		phd_log LOG_NOTICE "Starting cluster stack on node $node"
		phd_cmd_exec "pcs cluster start > /dev/null 2>&1" "$node"
		if [ "$?" -ne 0 ]; then
			phd_exit_failure "Could not start pacemaker on node $node"
		fi
	done

	node=$(definition_node "1")
	start_time=$(date +%s)

	while true; do
		lapse_sec=`expr $(date +%s) - $start_time`
		phd_log LOG_INFO "Waiting for pacemaker cluster to come up."
		phd_cmd_exec "cibadmin -Q > /dev/null 2>&1" "$node"
		if [ "$?" -eq 0 ]; then
			pacemaker_verify_nodes
			if [ "$?" -eq 0 ]; then
				break
			fi
		fi
		if [ $lapse_sec -ge $timeout ]; then
			phd_exit_failure "Timed out waiting for the pacemaker cluster to come up."
		fi
		phd_log LOG_INFO "Retry..."
		sleep 1
	done
}

pacemaker_cluster_clean()
{
	local nodes=$(definition_nodes)
	local output

	phd_cmd_exec "rm -rf /var/lib/pacemaker/cib /var/lib/pacemaker/cores /var/lib/pacemaker/blackbox /var/lib/pacemaker/pengine" "$nodes"

	output=$(phd_cmd_exec "ls /var/lib/pacemaker/cib/" "$nodes")
	if [ $? -eq 0 ]; then
		phd_exit_failure "Unable to clear cluster cache. $output"
	fi
	phd_cmd_exec "mkdir /var/lib/pacemaker/cib /var/lib/pacemaker/cores /var/lib/pacemaker/blackbox /var/lib/pacemaker/pengine" "$nodes"
}

pacemaker_cluster_init()
{
	local nodes=$(definition_nodes)
	local cluster_name=$(definition_cluster_name)

       # There is a pcs syntax change that results in us trying to
       # initialize the cluster in multiple ways.
        phd_cmd_exec "pcs cluster setup --force --local --name phd-cluster $nodes > /dev/null 2>&1" "$nodes"
        if [ "$?" -ne 0 ]; then
               phd_cmd_exec "pcs cluster setup --local $cluster_name $nodes > /dev/null 2>&1" "$nodes"
               if [ "$?" -ne 0 ]; then
                       phd_exit_failure "Could not setup corosync config for pacemaker cluster"
               fi
               local numnodes=$(echo $nodes | wc -w)
               phd_log LOG_DEBUG "$numnodes in cluster."
               if [ "$numnodes" = "2" ]; then
                       phd_log LOG_DEBUG "manually setting two_node cluster"
                       phd_cmd_exec "sed -i.bak 's/.*provider:.*corosync_votequorum/provider:corosync_votequorum\\ntwo_node:1/g' /etc/corosync/corosync.conf" "$nodes" 
               fi
        fi
}

pacemaker_fence_init()
{
	local node=$(definition_node "1")
	local script="${PHD_TMP_DIR}/FENCE_AGENTS"

	write_fence_cmds "$script"
	phd_script_exec "$script" "$node"
	if [ $? -ne 0 ]; then
		phd_exit_failure "Failed to initialize cluster fencing."
	fi
}
