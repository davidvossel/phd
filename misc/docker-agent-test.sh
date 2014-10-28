#!/bin/bash

container="hatest"
image="centos:centos7"
curtest="unknown"

clear_vars()
{
	local prefix=OCF_RESKEY
	local tmp

	for tmp in $(printenv | grep -e "^${prefix}_*" | awk -F= '{print $1}'); do
		unset $tmp
	done

	return 0
}

cleanup()
{
	docker kill $container > /dev/null 2>&1
	docker rm $container > /dev/null 2>&1
}

pull()
{
	echo "Pulling image for test. This could take several minutes."
	docker pull $image
}

docker_exec()
{
	local cmd=$1
	local expected_rc=$2
	local rc

	/usr/lib/ocf/resource.d/heartbeat/docker $cmd
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
	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_CRM_meta_timeout="10000"

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
	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_force_kill="true"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"

	docker kill "$container"
	docker_exec "monitor" "7"
	docker_exec "stop" "0"
	docker_exec "start" "0"
	docker_exec "stop" "0"
}

test_monitor_cmd_start()
{
	clear_vars

	curtest="monitor_cmd_start"

	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_force_kill="true" OCF_RESKEY_monitor_cmd="r=\$(( \$RANDOM % 2 )); exit \$r"
	
	for (( c=1; c <= 10; c++ ))
	do
		docker_exec "start" "0"
		docker_exec "stop" "0"
	done
}

test_monitor_cmd_fail()
{
	clear_vars

	curtest="monitor_cmd_fail"

	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_force_kill="true" OCF_RESKEY_monitor_cmd="true"
	
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	export OCF_RESKEY_monitor_cmd="false"
	docker_exec "monitor" "1"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}


test_invalid_monitor_cmd()
{
	clear_vars

	curtest="invalid_monitor_cmd"

	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_force_kill="true" OCF_RESKEY_monitor_cmd="/i/made/this/up"
	
	docker_exec "start" "2"
	docker_exec "monitor" "2"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}

test_reuse()
{
	clear_vars

	curtest="reuse"
	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_CRM_meta_timeout="10000" OCF_RESKEY_reuse="true" OCF_RESKEY_force_kill="true"

	docker inspect $container > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "failed: reuse: container should not exist yet"
		exit 1
	fi
	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"

	docker inspect $container > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed: reuse: container should still exist after stop."
		exit 1
	fi

	docker rm $container
}

test_custom_name()
{
	clear_vars

	curtest="custom_name"
	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_CRM_meta_timeout="10000" OCF_RESKEY_force_kill="true" OCF_RESKEY_name="customname"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker inspect customname  > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "failed: to name container correctly"
		exit 1
	fi
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}


test_run_opts()
{
	clear_vars

	mkdir -p /tmp/docker_ha_test
	touch /tmp/docker_ha_test/testfile

	curtest="custom_run_opts"
	export OCF_RESKEY_image="$image" OCF_RESKEY_run_cmd="sleep 1000" OCF_RESKEY_CRM_meta_timeout="10000" OCF_RESKEY_force_kill="true" OCF_RESKEY_run_opts="-v /tmp/docker_ha_test:/tmp/docker_ha_test" OCF_RESKEY_monitor_cmd="ls /tmp/docker_ha_test"

	docker_exec "monitor" "7"
	docker_exec "start" "0"
	docker_exec "monitor" "0"
	docker_exec "stop" "0"
	docker_exec "monitor" "7"
}

export OCF_ROOT=/usr/lib/ocf OCF_RESOURCE_INSTANCE=$container

service docker start > /dev/null 2>&1
cleanup
pull

echo "STARTING TESTS: using image <$image> container name <$container>"

test_simple
echo "--------------- PASSED: $curtest"

test_monitor_cmd_start
echo "--------------- PASSED: $curtest"

test_monitor_cmd_fail
echo "--------------- PASSED: $curtest"

test_invalid_monitor_cmd
echo "--------------- PASSED: $curtest"

test_run_opts
echo "--------------- PASSED: $curtest"

test_custom_name
echo "--------------- PASSED: $curtest"

test_reuse
echo "--------------- PASSED: $curtest"

test_failure_detection
echo "--------------- PASSED: $curtest"

cleanup

echo "______ ALL TESTS PASSED ______"
