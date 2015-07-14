#!/bin/bash

.  ${PHD_DOCKER_LIB}/phd_docker_utils.sh

fake_rsc_count=0
cloned_fake_rsc_count=2

launch_cts()
{
	local iterations="$1"
	local nodes
	local rc=0

	if [ "$iterations" = "0" ]; then
		iterations="--once"
	fi

	for (( c=1; c <= $containers; c++ ))
	do
		if [ -z "$nodes" ]; then
			nodes="${cluster_nodeprefix}${c}"
		else
			nodes="${nodes} ${cluster_nodeprefix}${c}"
		fi
	done

	launch_helper_daemons
	/usr/share/pacemaker/tests/cts/CTSlab.py --docker --logfile $pcmklogs --outputfile /var/log/cts.log --nodes "$nodes" -r --stonith "docker" -c --test-ip-base "${pcmkiprange}200" --stack "mcp" --at-boot 0 $iterations
	rc=$?
	kill_helper_daemons
	return $rc
}

launch_stonith_tests()
{
	local name="${cluster_nodeprefix}1"
	exec_cmd "/usr/sbin/ip_start" "$name"
	exec_cmd "/usr/share/pacemaker/tests/fencing/regression.py" "$name"
}

baremetal_verify_state()
{
	local total_rsc=$1
	local expected_fencing_actions=$2
	local offline=$3

	echo "Verifying cluster state, expecting [$offline] nodes to be offline"
	for (( tries=120; tries > 0; tries--))
	do
		local cluster_node=${cluster_nodeprefix}$(( ($RANDOM % $containers) + 1 ))
		local output
		local tmp
		local node
		local wait_list=""

		echo "Tries left... $tries"
		sleep 5
		output=$(exec_cmd "crm_mon --as-xml" "$cluster_node")
		if [ $? -ne 0 ]; then
			echo "no crm_mon --as-xml output, trying another node"
			continue
		fi

		fencing_count="$(cat /var/run/fence_docker_daemon.count)"
		if [ -n "$fencing_count" ] && [ "$expected_fencing_actions" = "0" ]; then
			echo "WARNING: whoa, someone got fenced when expected fence actions is 0"
		fi

		for node in $(echo $offline); do
			echo "$output" | grep -q "node.*name=.${node}. .*online=.false.*unclean=.false"
			if [ $? -ne 0 ]; then
				wait_list="$wait_list $node"
				continue
			fi
			tmp=$(docker inspect --format {{.State.Running}} $node)
			if ! [ "$tmp" = "true" ]; then
				wait_list="$wait_list $node"
				echo "Waiting for node [$node] to reboot.  running=$tmp"
				continue
			fi
		done

		if [ -n "$wait_list" ]; then
			echo "waiting for node[s] [${wait_list}] to go offline cleanly"
			continue
		fi

		if [ -z "$offline" ]; then
			echo "$output" | grep -q "node.*online=.false"
			if [ $? -eq 0 ]; then
				echo "waiting for all nodes to come online"
				continue
			fi
		fi

		tmp=$(echo "$output" | grep "resource.*ocf.*.*active=.true.*failed=.false" | wc -l)
		if [ "$tmp" -ne "${total_rsc}" ]; then
			echo "waiting for $total_rsc resources to come online. $tmp up so far"
			continue
		fi

		fencing_count="$(cat /var/run/fence_docker_daemon.count)"
		if [ -z "$fencing_count" ] && [ "$expected_fencing_actions" = "0" ]; then
			: fall through
		elif ! [ "$fencing_count" = "$expected_fencing_actions" ]; then
			echo "WARNING: Expected $expected_fencing_actions fencing actions, but got $fencing_count"
		fi
		return 0
	done
	echo "Failed to verify state."
	exit 1
}

baremetal_set_env()
{
	local cluster_node="${cluster_nodeprefix}1"
	local rsc

	fake_rsc_count=$(( $containers * 2 ))
	rsc=$fake_rsc_count

	for (( c=1; c <= $rsc; c++ ))
	do
		exec_cmd "pcs resource create FAKE${c} Dummy" "$cluster_node"
		if [ $? -ne 0 ]; then
			echo "failed to create resources for baremetal remote node tests"
			exit 1
		fi

		for (( j=1; j <= $containers; j++ ))
		do
			exec_cmd "pcs constraint location add FAKE${c}-${cluster_nodeprefix}${j} FAKE${c} ${cluster_nodeprefix}${j} 0 resource-discovery=exclusive" "$cluster_node"
			if [ $? -ne 0 ]; then
				echo "failed to create constraints for baremetal remote node tests"
				exit 1
			fi
		done

	done

	for (( c=1; c <= $cloned_fake_rsc_count; c++ ))
	do
		# increment rsc count by the number of cloned resource instances we'd expect.
		# each clone is like adding cluster nodes + remote nodes to the total rsc count.
		fake_rsc_count=$(( $remote_containers + $containers + $fake_rsc_count ))
		exec_cmd "pcs resource create FAKECLONE${c} Dummy --clone" "$cluster_node"
		if [ $? -ne 0 ]; then
			echo "failed to create resources for baremetal remote node tests"
			exit 1
		fi
	done
}

NODE_KILL_LIST=""
NODE_KILL_COUNT=0
NODE_KILL_NEW_RSC_COUNT=0
kill_random_nodes() {
	local num=$(( ($RANDOM % $1) + 1 ))
	local name
	local index
	local cluster_nodes_killed=0

	NODE_KILL_COUNT=0
	NODE_KILL_NEW_RSC_COUNT=$2
	NODE_KILL_LIST=""

	while [ $num -gt 0 ]; do
		local node_type=$(( ($RANDOM % 2) + 1 ))

		# TODO force fencing of remote nodes if cluster nodes fenced is approaching a 
		# quorum limit. right now we only allow a single cluster node to be fenced
		if [ $node_type -eq 1 ] || [ $cluster_nodes_killed -ne 0 ]; then
			index=$(( ($RANDOM % $remote_containers) + 1 ))
			name=${remote_nodeprefix}$index
			node_type=1
		else
			index=$(( ($RANDOM % $containers) + 1 ))
			name=${cluster_nodeprefix}$index
			cluster_nodes_killed=$(( $cluster_nodes_killed + 1 ))
		fi
		# make sure this isn't a node that we've already killed
		echo "$NODE_KILL_LIST" | grep -e "$name"
		if [ $? -eq 0 ]; then
			# try again, already killed this one
			continue
		fi

		echo "killing node $name" 
		NODE_KILL_LIST="$NODE_KILL_LIST $name"
		num=$(( $num - 1))
		if [ $node_type -eq 1 ]; then
			# less connection resources will be around
			NODE_KILL_NEW_RSC_COUNT=$(( NODE_KILL_NEW_RSC_COUNT - 1 ))
		fi
		# less cloned resources will be around
		NODE_KILL_NEW_RSC_COUNT=$(( NODE_KILL_NEW_RSC_COUNT - $cloned_fake_rsc_count ))
		NODE_KILL_COUNT=$(( NODE_KILL_COUNT + 1 ))
		docker kill $name
	done

}

launch_baremetal_remote_tests()
{
	local total_rsc
	local iter=$1

	echo "Launching Baremetal Remote Node Stress Tests"
	baremetal_set_env

	total_rsc=$(($fake_rsc_count + $remote_containers))
	baremetal_verify_state $total_rsc 0

	for (( c=1; c <= $iter; c++ ))
	do
		local max_num_kill_nodes=3

		echo "============== ITERATION NUMBER $c OUT OF $iter ==============="
		kill_random_nodes $max_num_kill_nodes $total_rsc
		baremetal_verify_state "$NODE_KILL_NEW_RSC_COUNT" "$NODE_KILL_COUNT" "$NODE_KILL_LIST"
		rm -f /var/run/fence_docker_daemon.count
		sleep 5
		echo "bring nodes [$NODE_KILL_LIST] back online"

		for node in $(echo $NODE_KILL_LIST); do
			echo "$node" | grep "remote" > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				launch_pcmk_remote_full "$node"
				# clear the failcount on the remote node
			# TODO this cleanup should go away after i do the reconnect interval stufff
#				exec_cmd "crm_resource -C -r $node" "${cluster_nodeprefix}1"
			else
				launch_pcmk_full $node
			fi
		done
		baremetal_verify_state $total_rsc 0
	done
}
