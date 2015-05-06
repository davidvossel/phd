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
. ${PHDCONST_ROOT}/lib/pacemaker.sh
. ${PHDCONST_ROOT}/lib/shared_storage.sh
. ${PHDCONST_ROOT}/lib/package.sh

SENV_PREFIX="PHD_SENV"
SREQ_PREFIX="PHD_SREQ"
SCRIPT_PREFIX="PHD_SCPT"

SEC_VAR="VARIABLES"
SEC_REQ="REQUIREMENTS"
SEC_LOCAL="LOCAL_VARIABLES"
SEC_SCRIPTS="SCRIPTS"

scenario_clean()
{
	rm -rf ${PHD_TMP_DIR}
	mkdir -p "$PHD_TMP_DIR/lib"
	phd_clear_vars "$SENV_PREFIX"
}

scenario_clean_nodes()
{
	local nodes=$(definition_nodes)
	phd_cmd_exec "rm -rf $PHD_TMP_DIR" "$nodes"
	phd_cmd_exec "mkdir -p $PHD_TMP_DIR/lib" "$nodes"
}

scenario_script_add_env()
{
	local script=$1
	local api_files=$(ls ${PHDCONST_ROOT}/lib/*api*)
	local tmp
	local file

	echo "export PHDCONST_ROOT=\"${PHD_TMP_DIR}\"" >> $script
	for file in $(echo $api_files); do
		file=$(basename $file)
		echo ". ${PHD_TMP_DIR}/lib/${file}" >> $script
	done
	echo ". ${PHD_TMP_DIR}/lib/definition.sh" >> $script

	while read tmp; do
		local key=$(echo $tmp | awk -F= '{print $1}')
		local value=$(echo $tmp | awk -F= '{print $2}')
		echo "export $key=\"${value}\"" >> $script
	done < <(print_definition)

	while read tmp; do
		local key=$(echo $tmp | awk -F= '{print $1}')
		local value=$(echo $tmp | awk -F= '{print $2}')
		echo "export $key=${value}" >> $script
	done < <(env | grep PHD_VAR_)
}

scenario_install_nodes()
{
	local nodes=$(definition_nodes)
	local install_local=$(eval echo "\$${SREQ_PREFIX}_install_local")

	if [ "$install_local" = "1" ]; then
		echo "$nodes $HOSTNAME" | sed 's/\s/\n/g' | sort | uniq -u | tr '\n' ' '
	else 
		echo "$nodes"
	fi
}

scenario_generate_tests()
{
	local tests=$(ls ${PHDCONST_ROOT}/tests/*)
	local filepath
	local file

	mkdir -p "${PHD_TMP_DIR}/tests/"

	for filepath in $(echo $tests); do
		file=$(basename $filepath)
		scenario_script_add_env "${PHD_TMP_DIR}/tests/${file}"
		echo "### start of test ###"  >> ${PHD_TMP_DIR}/tests/${file}
		cat $filepath >> ${PHD_TMP_DIR}/tests/${file}
		chmod 755 ${PHD_TMP_DIR}/tests/${file}
	done
}

function parse_yaml {
	local prefix=$2
	local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
	sed -ne "s|^\($s\):|\1|" \
		-e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
		-e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
	awk -F$fs '{
		indent = length($1)/2;
		vname[indent] = $2;
		for (i in vname) {if (i > indent) {delete vname[i]}}
		if (length($3) > 0) {
			vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
			printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
		}
	}'
}

scenario_unpack()
{
	local section=""
	local cleaned=""
	local cur_script=""
	local script_num=1
	local writing_script=0

	scenario_clean

	local old_IFS=$IFS
	IFS=$'\n'
	
	local SREQ_YAML=/tmp/$$.req.yaml
	local SVAR_YAML=/tmp/$$.var.yaml
	local writing_script=0

	rm -f ${SREQ_YAML}
	rm -f ${SVAR_YAML}

	if [ ! -z $2 ]; then
	    for req in $(parse_yaml ${2} "PHD_VAR_")
	    do
		phd_log LOG_DEBUG "Parsed: ${req}"
		export ${req}
	    done
	fi

	for line in $(cat $1 | grep -v -e "^[[:space:]]#" -e "^#")
	do
		cleaned=$(echo "$line" | tr -d ' ')
		if [ "${cleaned:0:1}" = "=" ]; then
			cleaned=$(echo "$cleaned" | tr -d '=')
		fi

		# determine if we are writing to a script
		if [ "$cleaned" = "...." ]; then
		    if [ "$writing_script" -eq 0 ]; then
			writing_script=1
			cur_script=${PHD_TMP_DIR}/${SCRIPT_PREFIX}${script_num}
			export "${SCRIPT_PREFIX}_${script_num}=${cur_script}"
			echo "#!/bin/bash" > ${cur_script}
			
			IFS=$old_IFS
			scenario_script_add_env "$cur_script"
			IFS=$'\n'
			chmod 755 ${cur_script}
		    else
			writing_script=0
			script_num=$(($script_num + 1))
		    fi 
		    continue
		fi

		# If writing, append to latest script file
		if [ "$writing_script" -eq 1 ]; then
		    echo "$line" >> ${cur_script}
		    continue
		fi

		: case - cleaned in $cleaned
		case $cleaned in
		    \.\.\.\.)
			continue ;;
		    $SEC_REQ)
			section=$cleaned
			continue ;;
		    $SEC_VAR)
			section=$cleaned
			continue ;;
		    $SEC_LOCAL|$SEC_SCRIPTS)
			section=$cleaned
			if [ -e ${SREQ_YAML} ]; then

			    for req in $(parse_yaml ${SREQ_YAML} ${SREQ_PREFIX}_)
			    do
				phd_log LOG_DEBUG "Parsed: ${req}"
				export ${req}
			    done
			    rm -f ${SREQ_YAML}
			fi
			continue ;;
		*) : ;;
		esac

		: case - section in $section
		case $section in
		$SEC_VAR)
			if [ $(eval echo '${'${line}'}') ]; then
			    echo "Variable $line = $(eval echo '${'${line}'}')"
			else
			    echo "Variable $line is undefined"
			    exit 1
			fi
			continue ;;
		$SEC_REQ)
			if
			    echo "$line" | grep -qe = 
			then
			    export "${SREQ_PREFIX}_$line"
			else
			    echo "$line" >> ${SREQ_YAML}
			fi
			continue ;;
		$SEC_LOCAL)
			export "${SENV_PREFIX}_$cleaned"
			continue ;;
		$SEC_SCRIPTS) : ;;
		*) : ;;
		esac

		if [ -z "$cleaned" ]; then
		    continue
		fi

		local key=$(echo $cleaned | awk -F= '{print $1}')
		local value=$(echo $cleaned | awk -F= '{print $2}')

		if [ $key = target ]; then
		    value=$(echo $line | awk -F= '{print $2}')
		fi

		local cleaned_value=$(phd_get_value $value)
		if [ -z "$cleaned_value" ]; then
		    phd_log LOG_ERR "no value found for \"$line\" for script number $script_num in scenario file"
		    continue
		fi
		export ${SENV_PREFIX}_${key}${script_num}="${cleaned_value}"

	done

	IFS=$old_IFS

	scenario_generate_tests
}

print_scenario()
{
	printenv | grep -e "$SENV_PREFIX" -e "$SREQ_PREFIX" -e "$SCRIPT_PREFIX"
	return 0
}

scenario_package_install()
{
	local nodes=$(scenario_install_nodes)
	local custom_package_dir=$(definition_package_dir)
	local packages=$(eval echo "\$${SREQ_PREFIX}_packages")

	if [ "x$packages" != x ]; then
	    phd_log LOG_NOTICE "=========================" 
	    phd_log LOG_NOTICE "==== Package Install ====" 
	    phd_log LOG_NOTICE "=========================" 
	    
	# install custom packages from a directory
	    package_install_custom "$custom_package_dir"  "$nodes"

	# install required scenario packages
	    package_install "$packages" "$nodes"
	fi
}

scenario_storage_destroy()
{
	local cluster_init=$(eval echo "\$${SREQ_PREFIX}_cluster_init")
	local wipe=$(eval echo "\$${SREQ_PREFIX}_clean_shared_storage")
	local shared_dev=$(definition_shared_dev)

	if [ -z "$wipe" ]; then
		return
	fi

	if [ "$wipe" -ne 1 ]; then
		return
	fi

	phd_log LOG_NOTICE "==================================" 
	phd_log LOG_NOTICE "====  Checking Shared Storage ====" 
	phd_log LOG_NOTICE "==================================" 

	if [ -z "$shared_dev" ]; then
		phd_exit_failure "Could not clear shared storage, cluster definition contains no shared storage."
	fi
	
	# since wiping storage involves the dlm and clvmd, we need to init
	# corosync to perform this operation
	if [ "$cluster_init" -eq "1" ]; then
		pacemaker_cluster_init
	fi

	shared_storage_destroy
	phd_log LOG_NOTICE "Success: Shared storage wiped"
}

scenario_cluster_destroy()
{
	local cluster_destroy=$(eval echo "\$${SREQ_PREFIX}_cluster_destroy")
	local cluster_init=$(eval echo "\$${SREQ_PREFIX}_cluster_init")
	local destroy=0

	if [ -n "$cluster_destroy" ]; then
		destroy=1
	fi
	if [ -n "$cluster_init" ]; then
		destroy=1
	fi

	if [ "$destroy" -eq "1" ]; then
	    phd_log LOG_NOTICE "====================================" 
	    phd_log LOG_NOTICE "====  Checking Cluster Shutdown ====" 
	    phd_log LOG_NOTICE "====================================" 
		pacemaker_cluster_stop
		pacemaker_cluster_clean
		phd_log LOG_NOTICE "Success: Cluster destroyed"
	else 
		phd_log LOG_NOTICE "Skipping cluster destroy"
	fi
}

scenario_cluster_init()
{
	local cluster_init=$(eval echo "\$${SREQ_PREFIX}_cluster_init")

	if [ -z "$cluster_init" ]; then
		return
	fi

	if [ "$cluster_init" -eq "1" ]; then
	    phd_log LOG_NOTICE "==================================" 
	    phd_log LOG_NOTICE "==== Checking Cluster Startup ====" 
	    phd_log LOG_NOTICE "==================================" 

		pacemaker_cluster_init
		pacemaker_cluster_start
		pacemaker_fence_init
		phd_log LOG_NOTICE "Success: Cluster started"
	else 
		phd_log LOG_NOTICE "Skipping cluster start"

	fi
}

scenario_distribute_api()
{
	local api_files=$(ls ${PHDCONST_ROOT}/lib/*)
	local nodes=$(definition_nodes)
	local file

	if [ $api_init = 0 ]; then
	    phd_log LOG_NOTICE "==============================================" 
	    phd_log LOG_NOTICE "==== Asuming PHD API is already installed ====" 
	    phd_log LOG_NOTICE "==============================================" 
	    return
	fi

	phd_log LOG_NOTICE "============================" 
	phd_log LOG_NOTICE "==== Distribute PHD API ====" 
	phd_log LOG_NOTICE "============================" 

	# also copy it locally
	cp -r ${PHDCONST_ROOT}/lib/* "${PHD_TMP_DIR}/lib/"

	# copy it remotely
	phd_node_cp "${PHDCONST_ROOT}/lib/*" "${PHD_TMP_DIR}/lib/" "$nodes" "755"
	if [ $? -ne 0 ]; then
	    phd_exit_failure "Failed to distribute phd API to nodes. Exiting."
	fi
	
	phd_log LOG_NOTICE "Success: API distributed to nodes ($nodes)"
}

scenario_environment_defaults()
{
	phd_log LOG_NOTICE "===================================="
	phd_log LOG_NOTICE "==== Distribute Default Configs ====" 
	phd_log LOG_NOTICE "====================================" 

	local nodes=$(definition_nodes)

	# install configs and other environment constants that we
	# need to be consistent for all scenarios.
	phd_node_cp "${PHDCONST_ROOT}/environment/lvm.conf.phd_default" "/etc/lvm/lvm.conf" "$nodes" "644"
	if [ $? -ne 0 ]; then
		phd_exit_failure "Failed to distribute default configuration files."
	fi
	phd_log LOG_NOTICE "Success: Default configs distributed"
}

scenario_script_exec()
{
	local script_num=1
	local script=""
	local nodes=""
	local node=""
	local rc=0
	local expected_rc=0

	while true; do
		script=$(eval echo "\$${SCRIPT_PREFIX}_${script_num}")
		if [ -z "$script" ]; then
			break
		fi

		expected_rc=$(eval echo "\$${SENV_PREFIX}_require_exitcode${script_num}")
		if [ -z "$expected_rc" ]; then
			expected_rc=0
		fi

		nodes=$(eval echo "\$${SENV_PREFIX}_target${script_num}")
		echo "nodes: $nodes"
		if [ -z "$nodes" ]; then
			nodes=$(definition_nodes)
		fi
		if [ "$nodes" = "all" ]; then
			nodes=$(definition_nodes)
		fi

		if [ "$nodes" = "local" ]; then
			phd_log LOG_NOTICE "executing $script locally"
			eval $script
			rc=$?
			if [ "$expected_rc" -ne "$rc" ]; then
				phd_exit_failure "Script $script_num exit code is $rc, expected $expected_rc Exiting."
			fi
		else
			phd_log LOG_NOTICE "executing $script on nodes \"$nodes\""
			for node in $(echo $nodes); do
				phd_script_exec $script "$node"
				rc=$?
				if [ "$expected_rc" -ne "$rc" ]; then
					phd_exit_failure "Script $script_num exit code is $rc, expected $expected_rc Exiting."
				fi
			done
		fi
		script_num=$(($script_num + 1))
	done

	return 0
}

scenario_verify()
{
	local res=0
	while read line; do
		local key=$(echo $line | awk -F= '{print $1}' | sed "s/${SREQ_PREFIX}_//g")
		local value=$(echo $line | awk -F= '{print $2}')

		case $key in
		cluster_init|cluster_destroy|packages|install_local|clean_shared_storage)
			continue ;;
		*) : ;;
		esac

		definition_meets_requirement $key $value
		if [ $? -ne 0 ]; then
			res=1
		fi
	done < <(printenv | grep "$SREQ_PREFIX")

	if [ $res -ne 0 ]; then
		phd_exit_failure "Cluster defintion does not meet all of the scenarios requirements"
	fi
	phd_log LOG_NOTICE "Success: cluster definition passes scenario validation"
}

scenario_exec()
{
	phd_log LOG_NOTICE "=======================================================" 
	phd_log LOG_NOTICE "==== Verifying Scenario against Cluster Definition ====" 
	phd_log LOG_NOTICE "=======================================================" 
	scenario_verify

	phd_log LOG_NOTICE "========================================="
	phd_log LOG_NOTICE "==== Verifying Cluster Communication ===="
	phd_log LOG_NOTICE "========================================="
	phd_verify_connection "$(definition_nodes)"
	scenario_clean_nodes
	phd_log LOG_NOTICE "Success: all nodes are accessible"

	scenario_cluster_destroy

	scenario_storage_destroy

	scenario_package_install

	scenario_distribute_api

	scenario_environment_defaults

	scenario_cluster_init

	phd_log LOG_NOTICE "======================================" 
	phd_log LOG_NOTICE "==== Executing Deployment Scripts ====" 
	phd_log LOG_NOTICE "======================================" 
	scenario_script_exec 0
	phd_log LOG_NOTICE "Success: Deployment Complete" 
}

scenario_exec_tests()
{
	local iter=$1
	local tests
	local num_tests
	local ran_test_index
	local cur_test
	local node
	local rc

	if [ -z $iter ]; then
		iter=10
	fi

	phd_log LOG_NOTICE "=================================" 
	phd_log LOG_NOTICE "==== Executing Test Scripts  ====" 
	phd_log LOG_NOTICE "=================================" 
	phd_log LOG_NOTICE "Performing $iter random test iterations" 

	for cur_test in $(ls ${PHD_TMP_DIR}/tests/*); do
		if [ -z "$tests" ]; then
			tests="$cur_test"
		else 
			tests="$tests $cur_test"
		fi
	done
	num_tests=$(echo "$tests" | wc -w)

	phd_log LOG_NOTICE "Tests found $num_tests" 

	for (( i=1; i <= $iter; i++ ))
	do
		node=$(phd_random_node)
		ran_test_index=$(( ($RANDOM % $num_tests) + 1 ))
		cur_test=$(echo "$tests" | cut -d ' ' -f $ran_test_index)
		phd_log LOG_NOTICE "Iteration ${i}: $(basename $cur_test) on node ${node}"
		phd_script_exec $cur_test "$node"
		rc=$?
		if [ $rc -eq 0 ]; then
			phd_log LOG_NOTICE "Success!"
		else 
			phd_log LOG_NOTICE "Failed... test $cur_test on node $node exited with code $rc"
			
			phd_exit_failure "Tests failed"
		fi
	done
	phd_log LOG_NOTICE "All tests passed"
}
