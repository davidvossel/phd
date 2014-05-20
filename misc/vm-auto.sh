#!/bin/bash
# This is a terrible script.
# example
# ./vm-auto.sh /var/lib/libvirt/images/rhel7-base.img rhel7-base.xml 170 rhel7-auto 4
# 
# that creates rhel7-auto1, rhel7-auto2, rhel7-auto3, rhel7-auto4 with
# ip addresses 192.168.122.171 192.168.122.172 192.168.122.173 192.168.122.173

baseimg=$1
basexml=$2
ipstart=$3
node_prefix=$4
instances=$5

rm -f cur_network.xml

# create new base image
qemu-img convert -O qcow2 $baseimg $(pwd)/${node_prefix}-readonly.qcow2
chmod u-w ${node_prefix}-readonly.qcow2

	cat << END >> cur_network.xml
<network>
  <name>default</name>
  <uuid>41ebdb84-7134-1111-a136-91f0f1119225</uuid>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0' />
  <mac address='52:54:00:A8:12:35'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254' />
END

for (( c=1; c <= $instances; c++ ))
do
	ip="192.168.122.$(($ipstart + c))"
	mac="52:54:$(($RANDOM % 9))$(($RANDOM % 9)):$(($RANDOM % 9))$(($RANDOM % 9)):$(($RANDOM % 9))$(($RANDOM % 9)):$(($RANDOM % 9))$(($RANDOM % 9))"
	image_path="${PWD}/${node_prefix}${c}.qcow2"

	virsh destroy ${node_prefix}${c}
	virsh undefine ${node_prefix}${c} 
	rm -f ${node_prefix}${c}.qcow2
	rm -f ${node_prefix}${c}.xml


	# make new image based of readonly img
	qemu-img create -f qcow2 -b $(pwd)/${node_prefix}-readonly.qcow2 $image_path

	# make new xml file
	cat $basexml | sed "s/<name>.*/<name>${node_prefix}${c}<\/name>/g" | sed "s|<source file=.*\/>|<source file=\"${image_path}\" \/>|g" | sed "s/type='raw'/type='qcow2'/g" | sed "s/<mac.*address=.*\/>/<mac address=\"${mac}\"\/>/g" | sed "s/<uuid>.*//g" > ${node_prefix}${c}.xml

	# set dhcp entry
	echo "<host mac='$mac' name='${node_prefix}${c}' ip='$ip' />" >> cur_network.xml
done

cat << END >> cur_network.xml
    </dhcp>
  </ip>
</network>
END

virsh net-dumpxml default > network_backup.xml
virsh net-destroy default
virsh net-undefine default
virsh net-define cur_network.xml
virsh net-start default
virsh net-autostart default

for (( c=1; c <= $instances; c++ ))
do
	virsh define ${node_prefix}${c}.xml
	virsh start ${node_prefix}${c}
done

