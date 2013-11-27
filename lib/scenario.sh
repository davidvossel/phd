#!/bin/bash

. ${PHDCONST_ROOT}/lib/utils.sh
. ${PHDCONST_ROOT}/lib/pacemaker.sh
. ${PHDCONST_ROOT}/lib/shared_storage.sh

SENV_PREFIX="PHD_SENV"
SREQ_PREFIX="PHD_SREQ"
SCRIPT_PREFIX="PHD_SCPT"
TMP_DIR="/var/run/phd_scenario"

SEC_REQ="REQUIREMENTS"
SEC_LOCAL="LOCAL_VARIABLES"
SEC_SCRIPTS="SCRIPTS"

scenario_clean()
{
	rm -rf ${TMP_DIR}
	mkdir -p $TMP_DIR
	phd_clear_vars "$SENV_PREFIX"
}

scenario_clean_nodes()
{
	local nodes=$(definition_nodes)
	phd_cmd_exec "rm -rf $TMP_DIR" "$nodes"
	phd_cmd_exec "mkdir -p $TMP_DIR" "$nodes"
}

scenario_script_add_env()
{
	local script=$1
	local tmp

	while read tmp; do
		local key=$(echo $tmp | awk -F= '{print $1}')
		local value=$(echo $tmp | awk -F= '{print $2}')
		echo "export $key=\"${value}\"" >> $script
	done < <(print_definition)
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

scenario_unpack()
{
	local section=""
	local cleaned=""
	local cur_script=""
	local script_num=1
	local writing_script=0

	scenario_clean

	while read line; do
		cleaned=$(echo "$line" | tr -d ' ')
		if [ "${cleaned:0:1}" = "=" ]; then
			cleaned=$(echo "$cleaned" | tr -d '=')
		fi

		case $cleaned in
		$SEC_REQ|$SEC_LOCAL|$SEC_SCRIPTS)
			section=$cleaned
			continue ;;
		*) : ;;
		esac

		case $section in
		$SEC_REQ)
			export "${SREQ_PREFIX}_$line"
			continue ;;
		$SEC_LOCAL)
			export "${SENV_PREFIX}_$cleaned"
			continue ;;
		$SEC_SCRIPTS) : ;;
		*) : ;;
		esac

		# determine if we are writing to a script
		if [ "$cleaned" = "...." ]; then
			if [ "$writing_script" -eq 0 ]; then
				writing_script=1
				cur_script=${TMP_DIR}/${SCRIPT_PREFIX}${script_num}
				export "${SCRIPT_PREFIX}_${script_num}=${cur_script}"
				echo "#!/bin/bash" > ${cur_script}
				scenario_script_add_env "$cur_script"
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
		else
			if [ -z "$cleaned" ]; then
				continue
			fi

			local key=$(echo $cleaned | awk -F= '{print $1}')
			local value=$(echo $cleaned | awk -F= '{print $2}')

			local cleaned_value=$(phd_get_value $value)
			if [ -z "$cleaned_value" ]; then
				phd_log LOG_ERR "no value found for \"$line\" for script number $script_num in scenario file"
				continue
			fi
			export "${SENV_PREFIX}_${key}${script_num}=${cleaned_value}"
		fi
	done < <(cat $1 | grep -v -e "[[:space:]]#" -e "^#")
}

print_scenario()
{
	printenv | grep -e "$SENV_PREFIX" -e "$SREQ_PREFIX" -e "$SCRIPT_PREFIX"
	return 0
}

scenario_custom_package_install()
{
	local package_dir=$(definition_package_dir)
	local packages=""
	local rpms=""
	local entry=""
	local nodes=$(scenario_install_nodes)
	local node

	if [ -z "$package_dir" ]; then
		echo ""
		return
	fi


	phd_cmd_exec "mkdir -p $TMP_DIR/phd_rpms/" "$nodes"

	for entry in $(ls ${package_dir}*.rpm); do
		packages="$packages $(rpm -qp -i $entry | grep -e 'Name' | sed 's/Name.*: //')"
		rpms="$rpms $entry"
		phd_node_cp "$entry" "$TMP_DIR/phd_rpms/" "$nodes"
	done

	if [ -z "$rpms" ]; then
		return
	fi

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "Installing custom packages '$packages' on node '$node'"
		phd_cmd_exec "yum remove -y $packages" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not clean custom packages on \"$node\" before install"
		fi
	    phd_cmd_exec "yum install -y $TMP_DIR/phd_rpms/*.rpm" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not install custom packages on \"$node\""
		fi
	done
	
	export "${SENV_PREFIX}_custom_packages=$packages"
}

scenario_package_install()
{
	local packages=$(eval echo "\$${SREQ_PREFIX}_packages")
	local package
	local node
	local custom_packages
	
	scenario_custom_package_install
	custom_packages=$(eval echo "\$${SENV_PREFIX}_custom_packages")

	# make sure not to try and install custom packages that overlap
	# with the scenario packages
    local unique=$(echo "$packages $custom_packages" | sed 's/\s/\n/g' | sort | uniq -u)
	packages=$(echo "$packages $unique" | sed 's/\s/\n/g' | sort | uniq -d | tr '\n' ' ')
	if [ -z "$packages" ]; then
		return 0
	fi

	for node in $(scenario_install_nodes); do
		phd_log LOG_DEBUG "Installing packages \"$packages\" on node \"$node\""
		phd_cmd_exec "yum install -y $packages" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not install required packages on node \"$node\""
		fi

		for package in $(echo $packages); do
			phd_cmd_exec "yum list installed | grep $package > /dev/null 2>&1" "$node"
			if [ $? -ne 0 ]; then
				phd_exit_failure "Could not install required package \"$package\" on node \"$node\""
			fi
		done
	done

	return 0
}

scenario_storage_destroy()
{
	local wipe=$(eval echo "\$${SREQ_PREFIX}_clean_shared_storage")
	local shared_dev=$(definition_shared_dev)

	if [ "$wipe" -ne 1 ]; then
		return
	fi

	if [ -z "$shared_dev" ]; then
		phd_exit_failure "Could not clear shared storage, cluster definition contains no shared storage."
	fi
	
	shared_storage_destroy
}

scenario_cluster_destroy()
{
	local cluster_destroy=$(eval echo "\$${SREQ_PREFIX}_cluster_destroy")
	local cluster_init=$(eval echo "\$${SREQ_PREFIX}_cluster_init")
	local destroy=1

	if [ -n "$cluster_destroy" ]; then
		destroy=1
	fi
	if [ -n "$cluster_init" ]; then
		destroy=1
	fi

	if [ "$destroy" -eq "1" ]; then
		pacemaker_cluster_stop
		pacemaker_cluster_clean
	fi
}

scenario_cluster_init()
{
	local cluster_init=$(eval echo "\$${SREQ_PREFIX}_cluster_init")

	if [ -z "$cluster_init" ]; then
		return
	fi

	if [ "$cluster_init" -eq "1" ]; then
		pacemaker_cluster_init
		pacemaker_cluster_start
	fi
}

scenario_script_exec()
{
	local script_num=0
	local script=""
	local nodes=""
	local node=""
	local rc=0
	local expected_rc=0

	while true; do
		script_num=$(($script_num + 1))
		script=$(eval echo "\$${SCRIPT_PREFIX}_${script_num}")
		if [ -z "$script" ]; then
			break
		fi

		expected_rc=$(eval echo "\$${SENV_PREFIX}_require_exitcode${script_num}")
		nodes=$(eval echo "\$${SENV_PREFIX}_target${script_num}")
		if [ -z "$nodes" ]; then
			nodes=$(definition_nodes)
		fi
		if [ "$nodes" = "all" ]; then
			nodes=$(definition_nodes)
		elif [ "$nodes" = "local" ]; then
			nodes=$(hostname)
		fi

		phd_log LOG_NOTICE "executing $script on nodes \"$nodes\""
		for node in $(echo $nodes); do
			phd_script_exec $script "$node"
			rc=$?
			if [ -z "$expected_rc" ]; then
				continue
			fi
			if [ "$expected_rc" -ne "$rc" ]; then
				phd_exit_failure "Script $script_num exit code is $rc, expected $expected_rc Exiting."
			fi
		done
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

}

scenario_exec()
{
	phd_log LOG_NOTICE "=======================================================" 
	phd_log LOG_NOTICE "==== Verifying Scenario against Cluster Definition ====" 
	phd_log LOG_NOTICE "=======================================================" 
	scenario_verify

	scenario_clean_nodes

	phd_log LOG_NOTICE "====================================" 
	phd_log LOG_NOTICE "====  Checking Cluster Shutdown ====" 
	phd_log LOG_NOTICE "====================================" 
	scenario_cluster_destroy

	phd_log LOG_NOTICE "==================================" 
	phd_log LOG_NOTICE "====  Checking Shared Storage ====" 
	phd_log LOG_NOTICE "==================================" 
	scenario_storage_destroy

	phd_log LOG_NOTICE "=========================" 
	phd_log LOG_NOTICE "==== Package Install ====" 
	phd_log LOG_NOTICE "=========================" 
	scenario_package_install

	phd_log LOG_NOTICE "==================================" 
	phd_log LOG_NOTICE "==== Checking Cluster Startup ====" 
	phd_log LOG_NOTICE "==================================" 
	scenario_cluster_init

	phd_log LOG_NOTICE "====================================" 
	phd_log LOG_NOTICE "==== Executing Scenario Scripts ====" 
	phd_log LOG_NOTICE "====================================" 
	scenario_script_exec

	phd_log LOG_NOTICE "====================================" 
	phd_log LOG_NOTICE "====           DONE             ====" 
	phd_log LOG_NOTICE "====================================" 
}
