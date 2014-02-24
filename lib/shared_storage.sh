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

# make all our nodes use a consistent locking type
verify_locking_type()
{
	local nodes=$(definition_nodes)
	local type3=0
	local type1=0

	for node in $(echo $nodes); do
		phd_cmd_exec "lvm dumpconfig global/locking_type 2>&1 | grep 'locking_type=3' > /dev/null 2>&1" $node
		if [ $? -eq 0 ]; then
			type3=1
		else 
			type1=1
		fi
	done

	if [ $type1 -ne $type3 ];  then
		# not a mix of type1 and type3, so we are good
		return
	fi

	# if there is a mix, force all the nodes to use type3
	phd_cmd_exec "lvmconf --enable-cluster" "$nodes"
}

shared_storage_destroy()
{
	local nodes=$(definition_nodes)
	local corosync_start="$PHD_TMP_DIR/PHD_STORAGE_COROSYNC_START"
	local corosync_stop="$PHD_TMP_DIR/PHD_STORAGE_COROSYNC_STOP"
	local clvmd_start="$PHD_TMP_DIR/PHD_STORAGE_CLVMD_START"
	local clvmd_stop="$PHD_TMP_DIR/PHD_STORAGE_CLVMD_STOP"
	local umount_script="$PHD_TMP_DIR/PHD_STORAGE_UMOUNT"
	local wipe_script="$PHD_TMP_DIR/PHD_STORAGE_WIPE"
	local shared_dev=$(definition_shared_dev)

	phd_log LOG_NOTICE "Wiping shared storage device[s] ($shared_dev)"

	cat <<- END > $corosync_start
#!/bin/sh

export OCF_ROOT=/usr/lib/ocf
export OCF_RESKEY_CRM_meta_timeout=60000

lvm dumpconfig global/locking_type 2>&1 | grep 'locking_type=3' > /dev/null 2>&1
if [ \$? -eq 0 ]; then
	service corosync start
	/usr/lib/ocf/resource.d/pacemaker/controld start
fi
END


	cat <<- END > $corosync_stop
#!/bin/sh
export OCF_ROOT=/usr/lib/ocf
export OCF_RESKEY_CRM_meta_timeout=60000

lvm dumpconfig global/locking_type 2>&1 | grep 'locking_type=3' > /dev/null 2>&1
if [ \$? -eq 0 ]; then
	/usr/lib/ocf/resource.d/pacemaker/controld stop
	service corosync stop
	sleep 1
fi
END

	cat <<- END > $clvmd_start
#!/bin/sh
export OCF_ROOT=/usr/lib/ocf
export OCF_RESKEY_CRM_meta_timeout=60000

lvm dumpconfig global/locking_type 2>&1 | grep 'locking_type=3' > /dev/null 2>&1
if [ \$? -eq 0 ]; then
	echo "starting clvmd"
	/usr/lib/ocf/resource.d/heartbeat/clvm start
fi
END
	cat <<- END > $clvmd_stop
#!/bin/sh
export OCF_ROOT=/usr/lib/ocf
export OCF_RESKEY_CRM_meta_timeout=60000

lvm dumpconfig global/locking_type 2>&1 | grep 'locking_type=3' > /dev/null 2>&1
if [ \$? -eq 0 ]; then
	echo "stopping clvmd"
	/usr/lib/ocf/resource.d/heartbeat/clvm stop
fi
END

	cat <<- END > $umount_script
#!/bin/sh
devices="$shared_dev"

sed -i.bak "s/.*[[:space:]]volume_list =.*/#volume_list = /g" /etc/lvm/lvm.conf
sed -i.bak "s/^volume_list.*=.*/#volume_list = /g" /etc/lvm/lvm.conf
for dev in \$(echo \$devices); do
	for vg in \$(pvs --noheadings \$dev | awk '{print \$2}'); do
		for lv in \$(lvs vg_normal --noheadings | awk '{print \$1}'); do
			fuser -mkv /dev/\$vg/\$lv
			umount /dev/\$vg/\$lv
			lvchange -an \$vg/\$lv
		done
		vgchange -an \$vg
	done
	fuser -mkv \$dev
	umount \$dev
done
END

	cat <<- END > $wipe_script
#!/bin/sh
devices="$shared_dev"
for dev in \$(echo \$devices); do
	cat /proc/mounts | grep -e "^\${dev}.* /boot "    
	if [ \$? -eq 0 ]; then
		exit 2
	fi

	for vg in \$(pvs --noheadings \$dev | awk '{print \$2}'); do
		cat /proc/mounts | grep "^/dev.*\${vg}-.* / "
		if [ \$? -eq 0 ]; then
			exit 2
		fi

		echo "removing \$vg"
		vgremove -f \$vg
		if [ \$? -ne 0 ]; then 
			echo "failed to remove volume group (\$vg)"
		fi
	done

	pvs \$dev
	if [ \$? -eq 0 ]; then
		pvremove \$dev
		if [ \$? -ne 0 ]; then
			echo "Failed remove lvm physical device, (\$dev)"
			exit 1
		fi
	fi

	# clear partition tables
	dd if=/dev/zero of=\$dev bs=512 count=2
	if [ \$? -ne 0 ]; then
		echo "Failed to clear block device (\$dev)"
		exit 1
	fi
done

exit 0

END

	# set consistent lvm locking type across cluster
	verify_locking_type

	# we have to start corosync to get quorum before clvmd will start
	phd_script_exec "$corosync_start" "$nodes"
	phd_script_exec "$clvmd_start" "$nodes"
	phd_script_exec "$umount_script" "$nodes"
	if [ $? -eq 2 ]; then
		phd_log LOG_ERR "Devices ($shared_dev) are associated with with the root filesystem. You really don't us to wipe these devices."
		phd_script_exec "$clvmd_stop" "$nodes"
		phd_exit_failure "Avoiding potential wipe of root filesystem"
	fi
	
	phd_script_exec "$wipe_script" "$(definition_node 1)"
	if [ $? -ne 0 ]; then
		phd_exit_failure "failed to wipe shared storage devices"
	fi
	phd_script_exec "$clvmd_stop" "$nodes"
	phd_script_exec "$corosync_stop" "$nodes"
}

