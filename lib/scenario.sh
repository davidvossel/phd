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
			export "${SREQ_PREFIX}_$cleaned"
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
				export "${SCRIPT_PREFIX}_${script_num}=${TMP_DIR}/${SCRIPT_PREFIX}${script_num}"
			else
				writing_script=0
				script_num=$(($script_num + 1))
			fi 
			continue
		fi

		# If writing, append to latest script file
		if [ "$writing_script" -eq 1 ]; then
			echo "$line" >> ${TMP_DIR}/${SCRIPT_PREFIX}${script_num}
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

scenario_exec()
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
			nodes=$(eval echo "\$${PHDENV_PREFIX}_nodes")
		fi
		if [ "$nodes" = "all" ]; then
			nodes=$(eval echo "\$${PHDENV_PREFIX}_nodes")
		fi

		phd_log LOG_NOTICE "executing $script on nodes \"$nodes\""

	done

	return 0
}
