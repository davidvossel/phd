#!/bin/bash

. ${PHDCONST_ROOT}/lib/utils.sh

PHDENV_PREFIX="PHD_ENV"

definition_clean()
{
	phd_clear_vars "$PHDENV_PREFIX"
}

definition_unpack()
{
	local entry_num
	if [ -z "$1" ]; then
		phd_log LOG_ERR "No cluster definition given"
		return 1
	fi

	definition_clean

	while read line; do
		local key=$(echo $line | awk -F= '{print $1}')
		local value=$(echo $line | awk -F= '{print $2}')

		export "${PHDENV_PREFIX}_$line"

		entry_num=1
		for entry in $(echo $value); do
			export "${PHDENV_PREFIX}_${key}${entry_num}=${entry}"
			entry_num=$(($entry_num + 1))
		done
	done < <(cat $1 | grep -v -e ".*#" | awk 'NF' | grep -e ".*=.*")

	return 0
}

definition_package_dir()
{
	eval echo "\$${PHDENV_PREFIX}_package_dir"
}

definition_shared_dev()
{
	eval echo "\$${PHDENV_PREFIX}_shared_storage"
}

definition_nodes()
{
	eval echo "\$${PHDENV_PREFIX}_nodes"
}

definition_node()
{
	eval echo "\$${PHDENV_PREFIX}_nodes${1}"
}

definition_meets_requirement()
{
	local key=$1
	local val=$2
	local exists=$(eval echo "\$${PHDENV_PREFIX}_$key$val")

	if [ -z "$exists" ]; then
		phd_log LOG_ERR "Cluster definition is missing scenario requirement \"$key=$val\""
		return 1
	fi
	return 0
}

print_definition()
{
	printenv | grep -e "$PHDENV_PREFIX"
	return 0
}
