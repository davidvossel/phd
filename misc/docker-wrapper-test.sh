#!/bin/bash

container="hatest"
baseimage="centos:centos7"
image="centos:dock-wrapper-test"
curtest="unknown"

clear_vars()
{
	local prefix=OCF
	local tmp

	for tmp in $(printenv | grep -e "^${prefix}_*" | awk -F= '{print $1}'); do
		unset $tmp
	done

	export OCF_ROOT=/usr/lib/ocf

	return 0
}

cleanup()
{
	docker kill $container > /dev/null 2>&1
	docker rm $container > /dev/null 2>&1
}

build_image()
{
	from="$baseimage"
	to="$image"

	cleanup
	docker rmi $to
	rm -rf Dockerfile

	docker pull "$from"
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to pull docker image $from"
		exit 1
	fi

	# Create Dockerfile for image creation.
	echo "FROM $from" > Dockerfile
	echo "RUN yum install -y resource-agents pacemaker-remote pacemaker" >> Dockerfile

	docker build -t "$to" .
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to generate docker image"
		exit 1
	fi

	# cleanup
	rm -rf Dockerfile
}

docker_exec()
{
	local cmd=$1
	local expected_rc=$2
	local rc

	echo "---- Executing $cmd ----"
	/usr/lib/ocf/resource.d/containers/docker-wrapper $cmd
	rc=$?	

	if [ $rc -ne $expected_rc ]; then
		echo "FAILED: test $curtest: expected exit code $expected_rc, but got $rc"
		exit 1
	fi
	return 0

}

test_simple()
{
	clear_vars
	curtest="simple"

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	docker_exec "stop" "0"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}

test_failure_detection()
{
	clear_vars
	curtest="failure_detection"

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	docker kill "$container"
	docker_exec "monitor" "7"
	docker_exec "stop" "0"
	docker_exec "start" "0"
	docker_exec "stop" "0"
}

#TODO test, kill pid 1

test_rsc_failure_detection()
{
	clear_vars
	curtest="rsc_failure_detection"

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	echo "rm -f /var/run/resource-agents/Dummy-*" | nsenter --target $(docker inspect --format {{.State.Pid}} $container) --mount --uts --ipc --net --pid

	docker_exec "monitor" "7"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "stop" "0"
}

test_multi_rsc()
{
	clear_vars
	curtest="multi_rsc"

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	export OCF_RESOURCE_INSTANCE="test2"
	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	docker_exec "stop" "0"
	val=$(docker inspect --format {{.State.Running}} $container 2>/dev/null)
	if [ $? -ne 0 ]; then
		#not running as a result of container not being found
		echo "FAILED: test $curtest: container shouldn't have stopped"
		exit 1
	fi

	export OCF_RESOURCE_INSTANCE="test"
	docker_exec "monitor" "0"
	docker_exec "stop" "0"

	val=$(docker inspect --format {{.State.Running}} $container 2>/dev/null)
	if [ $? -eq 0 ]; then
		#not running as a result of container not being found
		echo "FAILED: test $curtest: container should be stopped now"
		exit 1
	fi
}


test_super_multi_rsc()
{
	clear_vars
	curtest="super_multi_rsc"
	resources=9

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"

		docker_exec "monitor" "7"
		docker_exec "start" "0"
		docker_exec "monitor" "0"

	done

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"
		docker_exec "monitor" "0"
	done

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"
		docker_exec "stop" "0"

		val=$(docker inspect --format {{.State.Running}} $container 2>/dev/null)
		rc=$?
		if [ $rc -ne 0 ] && [ $c -ne $resources ]; then
			echo "FAILED: test $curtest: container shouldn't have stopped yet. resource $OCF_RESOURCE_INSTANCE stopped last"
			exit 1
		elif [ $rc -eq 0 ] && [ $c -eq $resources ]; then
			echo "FAILED: test $curtest: container should be stopped now"
			exit 1
		fi
		docker_exec "monitor" "7"
	done

}


test_super_multi_rsc_failure()
{
	clear_vars
	curtest="super_multi_rsc_failure"
	local resources=9
	local index

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_meta_isolation_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_pcmk_docker_image="$image"  OCF_RESKEY_pcmk_docker_privileged="true"

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"

		docker_exec "monitor" "7"
		docker_exec "start" "0"

		fail_it=$(( $RANDOM % 2 ))
		if [ $fail_it -eq 1 ]; then
			echo "FAILING INDEX $c"
			echo "rm -f /var/run/resource-agents/Dummy-test${c}.state" | nsenter --target $(docker inspect --format {{.State.Pid}} $container) --mount --uts --ipc --net --pid
			docker_exec "monitor" "7"
		fi
	done

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"
		/usr/lib/ocf/resource.d/containers/docker-wrapper "monitor"
		if [ $? -ne 0 ]; then
			docker_exec "stop" "0"
			docker_exec "monitor" "7"
			docker_exec "start" "0"
			docker_exec "monitor" "0"
		fi
	done

	for (( c=1; c <= $resources; c++ ))
	do
		export OCF_RESOURCE_INSTANCE="test${c}"
		docker_exec "monitor" "0"
		docker_exec "stop" "0"

		val=$(docker inspect --format {{.State.Running}} $container 2>/dev/null)
		rc=$?
		if [ $rc -ne 0 ] && [ $c -ne $resources ]; then
			echo "FAILED: test $curtest: container shouldn't have stopped yet. resource $OCF_RESOURCE_INSTANCE stopped last"
			exit 1
		elif [ $rc -eq 0 ] && [ $c -eq $resources ]; then
			echo "FAILED: test $curtest: container should be stopped now"
			exit 1
		fi
		docker_exec "monitor" "7"
	done

}


service docker start > /dev/null 2>&1
build_image

echo "STARTING TESTS: using image <$image> container name <$container>"

test_simple
echo "--------------- PASSED: $curtest"

test_rsc_failure_detection
echo "--------------- PASSED: $curtest"

test_failure_detection
echo "--------------- PASSED: $curtest"

test_multi_rsc
echo "--------------- PASSED: $curtest"

test_super_multi_rsc
echo "--------------- PASSED: $curtest"

test_super_multi_rsc_failure
echo "--------------- PASSED: $curtest"

cleanup

echo "______ ALL TESTS PASSED ______"
