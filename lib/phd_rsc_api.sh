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

#. ${PHDCONST_ROOT}/lib/phd_utils_api.sh

phd_rsc_failed_list()
{
	local execnode=$1
	local output
	local cmd="cibadmin -Q | grep name=\\\"fail-count- | sed s/.*name=\\\"fail-count-//g | sed s/\\\".*value=.*//g | uniq"

	phd_cmd_exec "$cmd" "$execnode"
}

phd_rsc_detect_failures()
{
	local execnode=$1
	local fail_list=$(phd_rsc_failed_list "$execnode")

	if [ -n "$fail_list" ]; then
		return 1
	fi

	return 0
}

phd_rsc_clear_failcounts()
{
	local execnode=$1
	local rsc_list=$(phd_rsc_failed_list "$execnode")
	local rsc

	for rsc in $(echo $rsc_list); do
		phd_cmd_exec "crm_resource -C -r  $rsc"
	done
}

phd_rsc_enable()
{
	local rsc=$1
	local node=$2
	local rc

	phd_cmd_exec "pcs resource enable $rsc" "$node" > /dev/null 2>&1
	rc=$?
	if [ $rc -ne 0 ]; then
		phd_cmd_exec "pcs resource start $rsc" "$node" > /dev/null 2>&1
		rc=$?
	fi
	return $?
}

phd_rsc_disable()
{
	local rsc=$1
	local node=$2
	local rc

	phd_cmd_exec "pcs resource disable $rsc" "$node" > /dev/null 2>&1
	rc=$?
	if [ $rc -ne 0 ]; then
		phd_cmd_exec "pcs resource stop $rsc" "$node" > /dev/null 2>&1
		rc=$?
	fi
	return $?
}

##
# Returns either top level resources (Excludes stonith resources) with 'parent_only'
# set, or all primitive resources with 'parent_only' not enabled.
# For example, a group with 3 primitives, only the group id will be returned.
#
# Usage: phd_rsc_list <parent resources only> [execution node]
# If execution node is not present, the command will be executed locally
##
phd_rsc_list()
{
	local parent_only=$1
	local node=$2
	local output
	local rc=0
	local cmd_no_stonith="cibadmin -Q --local --xpath \"//primitive[@class!='stonith']\" --node-path"
	local cmd="cibadmin -Q --local --xpath \"//primitive\" --node-path"
	local parent_filter="awk -F \"id='\" '{print \$2}' | awk -F \"'\" '{print \$1}' | uniq"
	local raw_filter="sed \"s/.*primitive\\[@id='//g\" | sed \"s/'\\]//g\""
	local filter=$raw_filter

	output=$(phd_cmd_exec "$cmd_no_stonith" "$node")
	rc=$?
	if [ $rc -ne 0 ]; then
		output=$(phd_cmd_exec "$cmd" "$node")
		rc=$?
	fi	

	if [ $rc -eq 0 ]; then
		if [ $parent_only -eq 1 ]; then
			filter=$parent_filter
		fi
		phd_cmd_exec "echo \"$output\" | tr ' ' '\n' | $filter"
	else
		# only return an rc of non-zero if we don't actually have access
		# to the cib, otherwise there were no resources listed.
		# TODO - we should be able to detect this from the first cibadmin's return code.
		phd_cmd_exec "cibadmin -Q --local > /dev/null 2>&1" "$node"
		rc=$?
	fi

	return $rc
}

##
# Return the nodes a rsc is active on
#
# Usage: phd_rsc_active_list <rsc id> [execution node]
# If execution node is not present, the command will be executed locally
##
phd_rsc_active_nodes()
{
	local rsc=$1
	local node=$2
	local cmd="crm_resource -W -r $rsc 2>&1 | sed 's/.*on: / /g' | sed 's/.*is NOT running.*//g' | sed 's/.*No such device.*//g' | tr -d '\n'"

	phd_cmd_exec "$cmd" "$node"
}

##
# Returns if a resource is active somewhere in the cluster or not
#
# Usage: phd_rsc_verify_is_active <rsc id> <timeout value in seconds> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 active
# 1 not active
##
phd_rsc_verify_is_active()
{
	local rsc=$1
	local timeout=$2
	local node=$3
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	active_list=$(phd_rsc_active_nodes "$rsc" "$node")
	while [ -z "$active_list" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_DEBUG "Timed out waiting for resource ($rsc) to become active within the cluster"
			return 1
		fi
		sleep 1
		active_list=$(phd_rsc_active_nodes "$rsc" "$node")
	done

	return 0
}

##
# Returns if rsc is active on a specific node or not.
#
# Usage: phd_rsc_verify_is_active_on <rsc id> <active node id to check> <timeout in seconds> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 active
# 1 not active
##
phd_rsc_verify_is_active_on()
{
	local rsc=$1
	local active_node=$2
	local timeout=$3
	local node=$4
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	while [ $? -ne 0 ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to become active on ($active_node)"
			return 1
		fi
		sleep 1
		echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	done

	return 0
}

##
# Returns if rsc is stopped on a node or not.
#
# Usage:
# phd_rsc_verify_is_stopped_on <rsc id> <active node id> <timeout in seconds> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 is stopped on node
# 1 did not stop within timeout period
##
phd_rsc_verify_is_stopped_on()
{
	local rsc=$1
	local active_node=$2
	local timeout=$3
	local node=$4
	local lapse_sec=0
	local stop_time=0

	stop_time=$(date +%s)
	echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	while [ $? -eq 0 ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to become stop on ($active_node)"
			return 1
		fi
		sleep 1
		echo $(phd_rsc_active_nodes "$rsc" "$node") | grep -q "$active_node"
	done

	return 0
}

##
# Returns whether all the resources are active within the cluster
#
# Usage: phd_rsc_verify_start_all <timeout value in seconds> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 all resources are active
# 1 all resources did not become active during timeout period
##
phd_rsc_verify_start_all()
{
	local timeout=$1
	local node=$2
	local rsc_list=$(phd_rsc_list 0 "$node")
	local lapse_sec=0
	local stop_time=0
	local rsc
	local rc=1

	phd_wait_cluster_idle $timeout $node
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "Timed out waiting for cluster to become idle"
		return 1
	fi

	phd_rsc_detect_failures $node
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "Resource failures detected."
		return 1
	fi

	stop_time=$(date +%s)
	while [ $rc -ne 0 ]; do
		for rsc in $(echo $rsc_list); do
			phd_rsc_verify_is_active $rsc 2 $node
			rc=$?
			if [ $rc -ne 0 ]; then
				phd_log LOG_INFO "Waiting for $rsc to start"
				break
			fi
		done

		if [ $rc -eq 0 ]; then
			phd_log LOG_INFO "Success, all resources are active"
			return 0
		fi

		sleep 2
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resources to start"
			return 1
		fi
	done
	return 0
}

##
# Returns whether all the resources are stopped within the cluster
#
# Usage: phd_rsc_verify_stop_all <timeout value in seconds> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 all resources are stopped
# 1 resources did not stop during timeout period
##
phd_rsc_verify_stop_all()
{
	local timeout=$1
	local node="$2"
	local lapse_sec=0
	local stop_time=0
	local cmd="crm_mon -X | grep 'active=\"true\"' | grep -v 'resource_agent=\"stonith' -q"

	phd_wait_cluster_idle $timeout "$node"
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "Timed out waiting for cluster to become idle during stop all"
		return 1
	fi

	phd_rsc_detect_failures "$node"
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "Resource failures detected during stop"
		return 1
	fi

	stop_time=$(date +%s)
	phd_cmd_exec "$cmd" "$node"
	while [ "$?" -eq "0" ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resources to stop"
			return 1
		fi

		sleep 1
		phd_log LOG_DEBUG "still waiting to verify stop all"
		phd_cmd_exec "$cmd" "$node"
	done
	return 0
}

##
# Tells all resources in the cluster to stop.
# Use with phd_rsc_verify_stop_all to wait on resources to shutdown.
#
# Usage: phd_rsc_stop_all [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 all resources are disabled via pcs.
# 1 failed to disable resources
##
phd_rsc_stop_all()
{
	local node=$1
	local rsc
	local rsc_list

	rsc_list=$(phd_rsc_list 1 "$node")
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "stop all failed, unable retrieve resource list"
		return 1
	fi

	phd_log LOG_DEBUG "stopping all resources. $rsc_list on node $node"
	for rsc in $(echo $rsc_list); do
		phd_rsc_disable "$rsc" "$node"
	done
}

##
# Tells all resources in the cluster to start.
# Use with phd_rsc_verify_start_all to wait on resources to become active
#
# Usage: phd_rsc_start_all [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 all resources are enabled via pcs
# 1 failed to enable resources
##
phd_rsc_start_all()
{
	local node=$1
	local rsc
	local rsc_list

	rsc_list=$(phd_rsc_list 1 "$node")
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "start all failed, unable retrieve resource list"
		return 1
	fi

	phd_log LOG_DEBUG "enabling all resources. $rsc_list"
	for rsc in $(echo $rsc_list); do
		phd_rsc_enable "$rsc" "$node"
	done
}

##
# Relocates a resource from the current active node to another node in the cluster..
#
# Usage: phd_rsc_relocate <rsc> <timeout> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return values:
# 0 rsc successfully relocated
# 1 rsc failed to relocate during timeout period
##
phd_rsc_relocate()
{
	local rsc=$1
	local timeout=$2
	local node=$3
	local cur_node=$(phd_rsc_active_nodes $rsc $node)

	if [ -z "$rsc" ]; then
		return 1
	fi

	# If there are more than one nodes returned. this will get the first entry.
	cur_node=$(echo $cur_node | awk '{print $1}')
	if [ -z "$cur_node" ]; then
		return 1
	fi
	
	phd_cmd_exec "pcs resource defaults | grep resource-stickiness" "$node"
	if [ $? -ne 0 ]; then
		phd_cmd_exec "pcs resource defaults resource-stickiness=100" "$node"
	fi

	phd_log LOG_DEBUG "Moving $rsc away from node $cur_node"
	phd_cmd_exec "pcs resource move $rsc" "$node"
	phd_rsc_verify_is_stopped_on "$rsc" "$cur_node" $timeout "$node"
	if [ $? -ne 0 ]; then
		return 1
	fi
	# verify it is active anywhere, we don't care where
	phd_rsc_verify_is_active "$rsc" $timeout "$node"
	if [ $? -ne 0 ]; then
		return 1
	fi
	phd_cmd_exec "pcs resource clear $rsc" "$node"
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "'pcs resource clear' command failed for resource ($rsc)"
		return 1
	fi
	phd_log LOG_NOTICE "Resource $rsc successfully relocated from node $cur_node to node $(phd_rsc_active_nodes $rsc $node)"
	return 0
}

##
# Fails a resource on a specific node
#
# Usage: phd_rsc_fail <rsc id> <node to fail on> [execution node]
# If execution node is not present, the command will be executed locally
#
# Return value:
# 0 success
# non-zero failure
##
phd_rsc_fail()
{
	local rsc=$1
	local fail_node=$2
	local node=$3

	# TODO add non generic ways to fail resource

	phd_cmd_exec "crm_resource -F -r $rsc -N $fail_node" "$node"
}

##
# Fail a resource and verify it recovers
##
phd_rsc_failure_recovery()
{
	local rsc=$1
	local timeout=$2
	local node=$3
	local cur_node=$(phd_rsc_active_nodes $rsc $node)
	local lapse_sec=0
	local stop_time=0

	if [ -z "$rsc" ]; then
		return 1
	fi

	# If there are more than one nodes returned. this will get the first entry.
	cur_node=$(echo $cur_node | awk '{print $1}')
	if [ -z "$cur_node" ]; then
		phd_log LOG_ERR "Resource $rsc is not active anywhere to test failure recovery"
		return 1
	fi

	# clear failcount
	phd_cmd_exec "crm_resource -C -r  $rsc -N $cur_node"

	# fail rsc
	phd_rsc_fail "$rsc" "$cur_node" "$node"

	# verify failcount increases
	stop_time=$(date +%s)
	phd_cmd_exec "pcs resource failcount show $rsc $cur_node | grep '$cur_node:.*[1-9]*'"
	while [ $? -ne 0 ]; do
		lapse_sec=`expr $(date +%s) - $stop_time`
		if [ $lapse_sec -ge $timeout ]; then
			phd_log LOG_ERR "Timed out waiting for resource ($rsc) to fail on node ($cur_node)"
			return 1
		fi
		sleep 1
		phd_cmd_exec "pcs resource failcount show $rsc $cur_node | grep '$cur_node:.*[1-9]*'"
	done

	# verify rsc is active on that node again (shows resource recovered)
	phd_rsc_verify_is_active_on "$rsc" "$cur_node" $timeout "$node"
	if [ $? -ne 0 ]; then
		phd_log LOG_ERR "Resource $rsc never recovered after failure on node $cur_node"
		return 1
	fi

	# clear failcount
	phd_cmd_exec "crm_resource -C -r  $rsc -N $cur_node"
	return 0
}

phd_rsc_random()
{
	local node="$1"
	local rsc_list=$(phd_rsc_list 0 "$node")
	local num_rscs=$(echo "$rsc_list" | wc -w)
	local ran_rsc_index=$(( ($RANDOM % $num_rscs) + 1 ))

	echo "$rsc_list" | cut -d ' ' -f $ran_rsc_index
}

phd_rsc_random_moveable()
{
	local node="$1"
	local cmd_group="cibadmin  -Q --local --xpath \"/cib/configuration/resources/group/primitive\" --node-path"
	local cmd_primitive="cibadmin -Q --local --xpath \"/cib/configuration/resources/primitive[@class!='stonith']\" --node-path"
	local rsc_list
	local tmp

	tmp=$(phd_cmd_exec "$cmd_group")
	if [ $? -eq 0 ]; then
		rsc_list=$tmp
	fi
	tmp=$(phd_cmd_exec "$cmd_primitive")
	if [ $? -eq 0 ]; then
		rsc_list="$rsc_list $tmp"
	fi

	local num_rscs=$(echo "$rsc_list" | wc -w)

	if [ $num_rscs -eq 0 ]; then
		return
	fi

	local ran_rsc_index=$(( ($RANDOM % $num_rscs) + 1 ))
	echo "$rsc_list" | cut -d ' ' -f $ran_rsc_index  | sed "s/.*primitive\\[@id='//g" | sed "s/'\\]//g"
}

