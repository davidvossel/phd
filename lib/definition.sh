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

PHDENV_PREFIX="PHD_ENV"

FENCE_CMDS=0

definition_clean()
{
	phd_clear_vars "$PHDENV_PREFIX"
}

definition_unpack()
{
	local entry_num

	if [ -z "$1" ]; then
		phd_exit_failure "No cluster definition provided"
	fi
	if [ ! -e "$1" ]; then
		phd_exit_failure "Custer definition at $1 does not exist"
	fi

	definition_clean

	while read line; do
		local key=$(echo $line | awk -F= '{print $1}')
		local value=$(echo $line | awk -F= '{print $2}')


		case $key in
		fence_cmd)
			FENCE_CMDS=$(($FENCE_CMDS + 1))
			export "${PHDENV_PREFIX}_fence_cmd${FENCE_CMDS}=$value"
			continue;;
		*)
			export "${PHDENV_PREFIX}_$line"
			;;
		esac

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

definition_transport()
{
	eval echo "\$${PHDENV_PREFIX}_transport"
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

write_fence_cmds()
{
	local fence_script=$1
	local c
	local cmd

	echo "#!/bin/bash" > $fence_script
	chmod 755 $fence_script

	if [ $FENCE_CMDS -eq 0 ]; then
		phd_log LOG_NOTICE "Fencing disabled. No fencing devices defined."
		echo "pcs property set stonith-enabled=false" >> $fence_script
		return 0
	fi
	
	for (( c=1; c <= $FENCE_CMDS; c++ ))
	do
		eval echo "\$${PHDENV_PREFIX}_fence_cmd${c}" >> $fence_script
	done
	phd_log LOG_NOTICE "Using cluster definition fencing devices."
}
