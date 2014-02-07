
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

PHD_PACKAGE_CUSTOM_INSTALLED=""

package_install_custom()
{
	local package_dir=$1
	local nodes=$2
	local packages=""
	local rpms=""
	local entry=""
	local node

	if [ -z "$package_dir" ]; then
		return
	fi

	phd_cmd_exec "mkdir -p $PHD_TMP_DIR/phd_rpms/" "$nodes"

	if ! [ -d "$package_dir" ]; then
			phd_exit_failure "Could not install custom packages, $package_dir is not a directory."
	fi

	for entry in $(ls ${package_dir}*.rpm); do
		packages="$packages $(rpm -qp -i $entry | grep -e 'Name' | sed 's/Name.*: //')"
		rpms="$rpms $entry"
		phd_node_cp "$entry" "$PHD_TMP_DIR/phd_rpms/" "$nodes"
	done

	if [ -z "$rpms" ]; then
		return
	fi

	for node in $(echo $nodes); do
		phd_log LOG_DEBUG "Installing custom packages '$packages' on node '$node'"
		phd_cmd_exec "yum remove -y $packages >/dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not clean custom packages on \"$node\" before install"
		fi
		phd_cmd_exec "yum install -y $PHD_TMP_DIR/phd_rpms/*.rpm > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not install custom packages on \"$node\""
		fi
	done

	# Keep up with a list of the custom packages installed
	PHD_PACKAGE_CUSTOM_INSTALLED="$PHD_PACKAGE_CUSTOM_INSTALLED $packages"
}

package_install()
{
	local packages=$1
	local nodes=$2
	local package
	local node
	local custom_packages
	
	custom_packages=$PHD_PACKAGE_CUSTOM_INSTALLED

	# make sure not to try and install custom packages that overlap
	# with the scenario packages
	local unique=$(echo "$packages $custom_packages" | sed 's/\s/\n/g' | sort | uniq -u)
	packages=$(echo "$packages $unique" | sed 's/\s/\n/g' | sort | uniq -d | tr '\n' ' ')
	if [ -z "$packages" ]; then
		phd_log LOG_NOTICE "Success: no package install required."
		return 0
	fi

	for node in $(echo $nodes); do
		phd_log LOG_NOTICE "Installing packages \"$packages\" on node \"$node\""
		phd_cmd_exec "yum install -y $packages 2>&1" "$node" > /dev/null
		if [ $? -ne 0 ]; then
			phd_exit_failure "Could not install required packages on node \"$node\""
		fi
	done

	phd_log LOG_NOTICE "Success: Packages installed"
	return 0
}

