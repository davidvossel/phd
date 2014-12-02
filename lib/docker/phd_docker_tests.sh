#!/bin/bash

.  ${PHD_DOCKER_LIB}/phd_docker_utils.sh

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
