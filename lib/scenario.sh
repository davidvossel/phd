#!/bin/bash

. ${PHDCONST_ROOT}/lib/utils.sh

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
				touch ${cur_script}
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
			local key=$(echo $cleaned | awk -F= '{print $1}')
			local value=$(echo $cleaned | awk -F= '{print $2}')

			local cleaned_value=$(phd_get_value $value)
			if [ -z "$cleaned_value" ]; then
				phd_log LOG_ERR "no value found for \"$key=$value\" for script number $script_num in scenario file"
				continue
			fi
			export "${SENV_PREFIX}_${key}${script_num}=${cleaned_value}"
		fi
	done < <(cat $1 | grep -v -e ".*#" | awk 'NF')
}

print_scenario()
{
	printenv | grep -e "$SENV_PREFIX" -e "$SREQ_PREFIX" -e "$SCRIPT_PREFIX"
	return 0
}

scenario_package_install()
{
	local packages=$(eval echo "\$${SREQ_PREFIX}_packages")
	local nodes=$(definition_nodes)

	if [ -z "$packages" ]; then
		return 0
	fi

	phd_log LOG_NOTICE "Installing packages \"$packages\" on nodes \"$nodes\""
	phd_cmd_exec "yum install -y $packages" "$nodes"

	return 0
}

scenario_script_exec()
{
	local script_num=0
	local script=""
	local nodes=""

	while true; do
		script_num=$(($script_num + 1))
		script=$(eval echo "\$${SCRIPT_PREFIX}_${script_num}")
		if [ -z "$script" ]; then
			break
		fi

		nodes=$(eval echo "\$${SENV_PREFIX}_nodes${script_num}")
		if [ -z "$nodes" ]; then
			nodes=$(defintion_nodes)
		fi
		if [ "$nodes" = "all" ]; then
			nodes=$(definition_nodes)
		fi

		phd_log LOG_NOTICE "executing $script on nodes \"$nodes\""
		phd_script_exec $script "$nodes"
	done

	return 0
}

scenario_exec()
{
	scenario_package_install
	scenario_script_exec
}
