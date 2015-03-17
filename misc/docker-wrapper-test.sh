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

	/usr/libexec/pacemaker/container_wrappers/docker-wrapper $cmd
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

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_wrapper_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_docker_image="$image"  OCF_RESKEY_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	docker_exec "monitor" "0"
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}

test_failure_detection()
{
	clear_vars
	curtest="failure_detection"

	export OCF_RESKEY_CRM_meta_provider="heartbeat" OCF_RESKEY_CRM_meta_class="ocf" OCF_RESKEY_CRM_meta_type="Dummy" OCF_RESKEY_CRM_wrapper_instance="$container"
	export OCF_RESOURCE_INSTANCE="test" OCF_RESKEY_docker_image="$image"  OCF_RESKEY_docker_privileged="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	docker kill "$container"
	docker_exec "monitor" "7"
	docker_exec "stop" "0"
	docker_exec "start" "0"
	docker_exec "stop" "0"
}

service docker start > /dev/null 2>&1
build_image

echo "STARTING TESTS: using image <$image> container name <$container>"

test_simple
echo "--------------- PASSED: $curtest"

test_failure_detection
echo "--------------- PASSED: $curtest"

cleanup

echo "______ ALL TESTS PASSED ______"
