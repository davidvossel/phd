#!/bin/bash

.  ${PHD_DOCKER_LIB}/phd_docker_utils.sh

fake_rsc_count=0
cloned_fake_rsc_count=4

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

	fake_rsc_count=$(( $remote_containers * 2 ))
	rsc=$fake_rsc_count

	for (( c=1; c <= $rsc; c++ ))
	do
		exec_cmd "pcs resource create FAKE${c} Dummy" "$cluster_node"
		if [ $? -ne 0 ]; then
			echo "failed to create resources for baremetal remote node tests"
			exit 1
		fi
	done

	for (( c=1; c <= $cloned_fake_rsc_count; c++ ))
	do
		# increment rsc count by the number of cloned resource instances we'd expect.
		# each clone is like adding cluster nodes + remote nodes to the total rsc count.
		fake_rsc_count=$(( $remote_containers + $containers + $fake_rsc_count ))
		exec_cmd "pcs resource create FAKECLONE${c} Dummy --clone notify=true" "$cluster_node"
		if [ $? -ne 0 ]; then
			echo "failed to create resources for baremetal remote node tests"
			exit 1
		fi
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
		local node_type=$(( ($RANDOM % 2) + 1 ))
		local name
		local index
		echo "============== ITERATION NUMBER $c OUT OF $iter ==============="
		if [ $node_type -eq 1 ]; then
			index=$(( ($RANDOM % $remote_containers) + 1 ))
			name=${remote_nodeprefix}$index
			total_rsc=$((total_rsc - 1))
		else
			index=$(( ($RANDOM % $containers) + 1 ))
			name=${cluster_nodeprefix}$index
		fi
		echo "killing node $name"

		docker kill $name
		baremetal_verify_state "$(( $total_rsc - $cloned_fake_rsc_count ))" 1 $name
		rm -f /var/run/fence_docker_daemon.count
		sleep 5
		echo "bring node $name back online"
		if [ $node_type -eq 1 ]; then
			launch_pcmk_remote $index
			total_rsc=$((total_rsc + 1))
			# clear the failcount on the remote node
			exec_cmd "crm_resource -C -r $name" "${cluster_nodeprefix}1"
		else
			launch_pcmk $index
		fi
		baremetal_verify_state $total_rsc 0
	done
}
