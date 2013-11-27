#!/bin/bash

shared_storage_destroy()
{
	local nodes=$(definition_nodes)
	local corosync_start="$TMP_DIR/PHD_STORAGE_COROSYNC_START"
	local clvmd_start="$TMP_DIR/PHD_STORAGE_CLVMD_START"
	local clvmd_stop="$TMP_DIR/PHD_STORAGE_CLVMD_STOP"
	local umount_script="$TMP_DIR/PHD_STORAGE_UMOUNT"
	local wipe_script="$TMP_DIR/PHD_STORAGE_WIPE"
	local shared_dev=$(definition_shared_dev)

	cat <<- END > $corosync_start
#!/bin/sh

cat /etc/lvm/lvm.conf | grep -e "^[[:space:]]*locking_type.*3"
if [ \$? -eq 0 ]; then
	service corosync start
	service dlm start
	sleep 1
fi
END

	cat <<- END > $clvmd_start
#!/bin/sh

cat /etc/lvm/lvm.conf | grep -e "^[[:space:]]*locking_type.*3"
if [ \$? -eq 0 ]; then
	echo "starting clvmd"
	service clvmd start
	sleep 1
fi
END
	cat <<- END > $clvmd_stop
#!/bin/sh

cat /etc/lvm/lvm.conf | grep -e "^[[:space:]]*locking_type.*3"
if [ \$? -eq 0 ]; then
	echo "stopping clvmd"
	service clvmd stop
	service dlm stop
	service corosync stop
	lvmconf --disable-cluster
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
	for vg in \$(pvs --noheadings \$dev | awk '{print \$2}'); do
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
END

	# we have to start corosync to get quorum before clvmd will start
	phd_script_exec "$corosync_start" "$nodes"
	phd_script_exec "$clvmd_start" "$nodes"
	phd_script_exec "$umount_script" "$nodes"
	phd_script_exec "$wipe_script" "$(definition_node 1)"
	if [ $? -ne 0 ]; then
		phd_exit_failure "failed to wipe shared storage devices"
	fi
	phd_script_exec "$clvmd_stop" "$nodes"
}

