#!/bin/bash

.  ${PHD_DOCKER_LIB}/phd_docker_utils.sh

fake_rsc_count=0

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
	local offline=$1
	local total_rsc=$(($fake_rsc_count + $remote_containers))
	# we expect a certain number of nodes to be offline
	# after those nodes are offline we expect all resources to be up

	echo "Verifying cluster state, expecting $offline nodes to be offline"
	for (( tries=120; tries > 0; tries--))
	do
		local cluster_node=${cluster_nodeprefix}$(( ($RANDOM % $containers) + 1 ))
		local output
		local tmp

		echo "Tries left... $tries"
		sleep 1
		output=$(exec_cmd "crm_mon --as-xml" "$cluster_node")
		if [ $? -ne 0 ]; then
			echo "no crm_mon --as-xml output, trying another node"
			continue
		fi

		tmp=$(echo "$output" | grep "node.*online=.false" | wc -l)
		if [ "$offline" -eq "0" ] && [ "$tmp" -ne "0" ]; then
			echo "waiting for all nodes to come online"
			continue
		elif [ "$tmp" -ne $offline ]; then
			# TODO check for nodes by name instead of just how many we expect. pass a node list in
			echo "waiting for exactly $offline nodes to go down. $tmp down so far"
			continue
		fi

		tmp=$(echo "$output" | grep "resource.*ocf.*.*active=.true.*failed=.false" | wc -l)
		if [ "$tmp" -ne "${total_rsc}" ]; then
			echo "waiting for $total_rsc resources to come online. $tmp up so far"
			continue
		fi
		return 0
	done
	return 1
}

baremetal_set_env()
{
	local cluster_node="${cluster_nodeprefix}1"
	local rsc

	fake_rsc_count=$(( $remote_containers * 10 ))
	rsc=$fake_rsc_count

	for (( c=1; c <= $rsc; c++ ))
	do
		exec_cmd "pcs resource create FAKE${c} Dummy" "$cluster_node"
		if [ $? -ne 0 ]; then
			echo "failed to create resources for baremetal remote node tests"
			exit 1
		fi
	done
}

launch_baremetal_remote_tests()
{
	iter=$1

	echo "Launching Baremetal Remote Node Stress Tests"
	baremetal_set_env
	baremetal_verify_state 0

	for (( c=1; c <= $iter; c++ ))
	do
		local node_type=$(( ($RANDOM % 2) + 1 ))
		local name
		local index
		if [ $node_type -eq 1 ]; then
			index=$(( ($RANDOM % $remote_containers) + 1 ))
			name=${remote_nodeprefix}$index
		else
			index=$(( ($RANDOM % $containers) + 1 ))
			name=${cluster_nodeprefix}$index
		fi
		echo "killing node $name"
		docker kill $name
		baremetal_verify_state 1
		echo "bring node $name back online"
		sleep 1
		if [ $node_type -eq 1 ]; then
			launch_pcmk_remote $index
		else
			launch_pcmk $index
		fi
		baremetal_verify_state 0
	done
}
