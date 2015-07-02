#!/bin/bash
#
# Copyright (c) 2014 David Vossel <dvossel@redhat.com>
#					All Rights Reserved.
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
#######################################################################

iprange="172.17.0."
pcmkiprange="172.17.200."
remoteiprange="172.17.201."
gateway="172.17.42.1"
pcmklogs="/var/log/pacemaker.log"
cluster_nodeprefix="pcmk"
remote_nodeprefix="pcmk_remote"

if [ -z "$PHD_DOCKER_LIB" ]; then
	PHD_DOCKER_LIB="/usr/libexec/phd/docker"
fi
if [ -z "$PHD_DOCKER_LOGDIR" ]; then
	PHD_DOCKER_LOGDIR="/var/lib/phd/"
fi

mkdir -p $PHD_DOCKER_LOGDIR
mkdir -p $PHD_DOCKER_LIB

exec_cmd()
{
	echo "$1" | nsenter --target $(docker inspect --format {{.State.Pid}} ${2}) --mount --uts --ipc --net --pid
}

verify_connection()
{
	local nodes=$1

	for node in $(echo $nodes); do
		exec_cmd "ls > /dev/null 2>&1" "$node"
		if [ $? -ne 0 ]; then
			echo "Unable to establish connection with node \"$node\"."
			exit 1
		fi
		echo "Node ($node) is accessible"
	done
}

rm_from_file()
{
	local tmpfile=$(mktemp)

	rm -f ${1}_bu
	cp $1 ${1}_bu

	cat $1 | grep -v $2 > $tmpfile
	cat $tmpfile > $1
	rm -f $tmpfile
}

docker_setup()
{
	# make sure we have docker installed
	yum list installed | grep "docker" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		yum install -y docker 
	fi
	systemctl start docker
	# handle base image retrieval
	docker $doc_opts images | grep -q "$from"
	if [ $? -ne 0 ]; then
		pull=1
	fi
	if [ $pull -ne 0 ]; then
		docker $doc_opts pull $from
	fi
}

prev_cluster_cleanup()
{
	echo "Cleaning up previous pacemaker docker clusters"
	prev_image=$(docker $doc_opts ps -a | grep ${cluster_nodeprefix}  | awk '{print $2}' | uniq)
	docker $doc_opts kill $(docker $doc_opts ps -a | grep ${cluster_nodeprefix} | awk '{print $1}') > /dev/null 2>&1
	docker $doc_opts kill $(docker $doc_opts ps -a | grep ${remote_nodeprefix} | awk '{print $1}') > /dev/null 2>&1
	docker $doc_opts rm $(docker $doc_opts ps -a | grep ${cluster_nodeprefix} | awk '{print $1}') > /dev/null 2>&1
	docker $doc_opts rm $(docker $doc_opts ps -a | grep ${remote_nodeprefix} | awk '{print $1}') > /dev/null 2>&1
	if [ $reuse -eq 0 ]; then
		docker $doc_opts rmi $prev_image > /dev/null 2>&1
	fi
}

make_image()
{
	# make Dockerfile
	if [ -n "$prev_image" ]; then
		if [ $reuse -ne 0 ]; then
			echo "using previous image $prev_image"
			image=$prev_image
			return
		fi
	fi

	echo "Making Dockerfile"
	rm -f Dockerfile

	echo "FROM $from" > Dockerfile

	# this gets around a bug in rhel 7.0
	touch /etc/yum.repos.d/redhat.repo

	rm -rf repos
	mkdir repos
	if [ -n "$repodir" ]; then
		cp $repodir/* repos/
		echo "ADD /repos /etc/yum.repos.d/" >> Dockerfile
	fi

	rm -rf rpms
	mkdir rpms
	if [ -n "$rpmdir" ]; then
		echo "ADD /rpms /root/" >> Dockerfile
		echo "RUN yum install -y /root/*.rpm" >> Dockerfile
		cp $rpmdir/* rpms/
	fi

	echo "RUN yum install -y net-tools pacemaker pacemaker-cts resource-agents pcs corosync which fence-agents-common sysvinit-tools" >> Dockerfile

	# make launch script.
	echo "Making ENTRYPOINT script"
	rm -rf launch_scripts
	mkdir launch_scripts
	# by default make an idle docker container that we can dynamically start/stop pcmk in
	cat << END >> launch_scripts/launch.sh
#!/bin/bash
while true; do
	sleep 1
done
END
	chmod 755 launch_scripts/launch.sh
	echo "ADD /launch_scripts /root/" >> Dockerfile

	rm -rf bin_files
	mkdir bin_files
	cp ${PHD_DOCKER_LIB}/fence_docker_cts bin_files/fence_docker_cts
	# add rest of docker file entries
	echo "ADD bin_files/fence_docker_cts /usr/sbin/" >> Dockerfile
	echo "ENTRYPOINT /root/launch.sh" >> Dockerfile

	# generate image
	echo "Making image"
	docker $doc_opts build .
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to generate docker image"
		exit 1
	fi
	image=$(docker $doc_opts images -q | head -n 1)

	# cleanup
	rm -rf bin_files rpms repos launch_scripts
}

write_helper_scripts()
{
	local node=$1
	local ip=$2
	local tmp
	local helper_dir="${node}_helpers"

	rm -rf $helper_dir
	mkdir $helper_dir

	tmp=$(mktemp)
	cat << END >> $tmp
#!/bin/bash
export OCF_ROOT=/usr/lib/ocf/ OCF_RESKEY_ip=$ip OCF_RESKEY_cidr_netmask=32
/usr/lib/ocf/resource.d/heartbeat/IPaddr2 start
END
	chmod 755 $tmp
	mv $tmp $helper_dir/ip_start

	tmp=$(mktemp)
	cat << END >> $tmp
#!/bin/bash

/usr/sbin/ip_start
/usr/share/corosync/corosync start > /dev/null 2>&1

pid=\$(pidof pacemakerd)
if [ "\$?" -ne 0 ];  then
	mkdir -p /var/run

	export PCMK_debugfile=$pcmklogs
	(pacemakerd &) & > /dev/null 2>&1
	sleep 5

	pid=\$(pidof pacemakerd)
	if [ "\$?" -ne 0 ]; then
		echo "startup of pacemaker failed"
		exit 1
	fi
	echo "$pid" > /var/run/pacemakerd.pid
fi
exit 0
END
	chmod 755 $tmp
	mv $tmp $helper_dir/pcmk_start

	tmp=$(mktemp)
	cat << END >> $tmp
#!/bin/bash
/usr/sbin/ip_start
pid=\$(pidof pacemaker_remoted)
if [ "\$?" -ne 0 ];  then
	mkdir -p /var/run

	export PCMK_debugfile=$pcmklogs
	(pacemaker_remoted &) & > /dev/null 2>&1
	sleep 5

	pid=\$(pidof pacemaker_remoted)
	if [ "\$?" -ne 0 ]; then
		echo "startup of pacemaker failed"
		exit 1
	fi
	echo "$pid" > /var/run/pacemaker_remoted.pid
fi
exit 0
END
	chmod 755 $tmp
	mv $tmp $helper_dir/pcmk_remote_start

	tmp=$(mktemp)
	cat << END >> $tmp
#!/bin/bash
status()
{
	pid=\$(pidof \$1 2>/dev/null)
	rtrn=\$?
	if [ \$rtrn -ne 0 ]; then
		echo "\$1 is stopped"
	else
		echo "\$1 (pid \$pid) is running..."
	fi
	return \$rtrn
}
stop()
{
	desc="Pacemaker Cluster Manager"
	prog=\$1
	shutdown_prog=\$prog

	if ! status \$prog > /dev/null 2>&1; then
	    shutdown_prog="crmd"
	fi

	cname=\$(crm_node --name)
	crm_attribute -N \$cname -n standby -v true -l reboot

	if status \$shutdown_prog > /dev/null 2>&1; then
	    kill -TERM \$(pidof \$prog) > /dev/null 2>&1

	    while status \$prog > /dev/null 2>&1; do
		sleep 1
		echo -n "."
	    done
	else
	    echo -n "\$desc is already stopped"
	fi

	rm -f /var/lock/subsystem/pacemaker
	rm -f /var/run/\${prog}.pid
	killall -q -9 'crmd stonithd attrd cib lrmd pacemakerd pacemaker_remoted'
}

stop "pacemakerd"
/usr/share/corosync/corosync stop > /dev/null 2>&1
killall -q -9 'corosync'
exit 0
END
	chmod 755 $tmp
	mv $tmp $helper_dir/pcmk_stop

	tmp=$(mktemp)
	cat << END >> $tmp
#!/bin/bash
status()
{
	pid=\$(pidof \$1 2>/dev/null)
	rtrn=\$?
	if [ \$rtrn -ne 0 ]; then
		echo "\$1 is stopped"
	else
		echo "\$1 (pid \$pid) is running..."
	fi
	return \$rtrn
}
stop()
{
	desc="Pacemaker Remote"
	prog=\$1
	shutdown_prog=\$prog

	if status \$shutdown_prog > /dev/null 2>&1; then
	    kill -TERM \$(pidof \$prog) > /dev/null 2>&1

	    while status \$prog > /dev/null 2>&1; do
		sleep 1
		echo -n "."
	    done
	else
	    echo -n "\$desc is already stopped"
	fi

	rm -f /var/lock/subsystem/pacemaker
	rm -f /var/run/\${prog}.pid
	killall -q -9 'crmd stonithd attrd cib lrmd pacemakerd pacemaker_remoted'
}

stop "pacemaker_remoted"
exit 0
END
	chmod 755 $tmp
	mv $tmp $helper_dir/pcmk_remote_stop

	echo "this is a pretty insecure key" > $helper_dir/authkey
}

launch_pcmk_full()
{

	verify_connection "$1"
	exec_cmd "pcmk_start" "$1"

}

launch_pcmk()
{
	local index=$1
	local name="${cluster_nodeprefix}${index}"

	launch_pcmk_full $name
}

launch_pcmk_all()
{
	for (( c=1; c <= $containers; c++ ))
	do
		launch_pcmk $c
	done
}

launch_pcmk_remote_full()
{
	verify_connection "$1"
	exec_cmd "pcmk_remote_start" "$1"
}

launch_pcmk_remote()
{
	local index=$1
	local name="${remote_nodeprefix}${index}"

	launch_pcmk_remote_full $name
}

launch_pcmk_remote_all()
{
	for (( c=1; c <= $remote_containers; c++ ))
	do
		launch_pcmk_remote $c
	done
}

launch_remote_containers()
{
	echo "Launching baremetal remote containers"

	for (( c=1; c <= $remote_containers; c++ ))
	do
		name="${remote_nodeprefix}${c}"
		echo "Launching remote node $name"

		write_helper_scripts "$name" "${remoteiprange}${c}"
		docker $doc_opts run -v $PWD/${name}_helpers:/usr/sbin/pcmk_helpers/  -d -P -h $name --name=$name $image /bin/bash
		verify_connection "$name"
		exec_cmd "cp /usr/sbin/pcmk_helpers/* /usr/sbin/" "$name"
		exec_cmd "mkdir /etc/pacemaker" "$name"
		exec_cmd "cp /usr/sbin/pcmk_helpers/authkey /etc/pacemaker/" "$name"
	done
}

launch_containers()
{
	echo "Launching containers"

	local node_ips=""
	local ip=""

	for (( c=1; c <= $containers; c++ ))
	do
		name="${cluster_nodeprefix}${c}"
		ip="${pcmkiprange}$c"
		echo "Launching node $name"
		write_helper_scripts "$name" "$ip"

		if [ $debug_container -eq 0 ]; then
			docker $doc_opts run -v $PWD/${name}_helpers:/usr/sbin/pcmk_helpers/ -d -P -h $name --name=$name $image /bin/bash
		else
			docker $doc_opts run -v $PWD/${name}_helpers:/usr/sbin/pcmk_helpers/  -i -t -P -h $name --name=$name $image /bin/bash
			exit 0
		fi

		if [ -z "$node_ips" ]; then
			node_ips="$ip"
		else
			node_ips="${node_ips} ${ip}"
		fi

	done

	for (( c=1; c <= $containers; c++ ))
	do
		name="${cluster_nodeprefix}${c}"
		ip="${pcmkiprange}$c"

		verify_connection "$name"
		echo "setting up cluster"
		exec_cmd "cp /usr/sbin/pcmk_helpers/* /usr/sbin/" "$name"
		exec_cmd "mkdir /etc/pacemaker" "$name"
		exec_cmd "cp /usr/sbin/pcmk_helpers/authkey /etc/pacemaker/" "$name"

		exec_cmd "pcs cluster setup --local --name mycluster $node_ips"  "$name" > /dev/null 2>&1
		if [ "$?" -ne 0 ]; then
			exec_cmd "pcs cluster setup --local mycluster $node_ips"  "$name" > /dev/null 2>&1
		fi
		# make sure we use file based logging 
		exec_cmd 'cat /etc/corosync/corosync.conf | sed "s/to_syslog:.*yes/to_logfile: yes\\nlogfile: \\/var\\/log\\/pacemaker.log/g" > /etc/corosync/corosync.conf.bu' "$name"
		exec_cmd "mv -f /etc/corosync/corosync.conf.bu /etc/corosync/corosync.conf" "$name"

	done

}

kill_helper_daemons()
{
	killall -9 fence_docker_daemon > /dev/null 2>&1
	killall -9 phd_docker_remote_daemon > /dev/null 2>&1
}


launch_helper_daemons()
{
	kill_helper_daemons

	rm -f ${PHD_DOCKER_LOGDIR}/fence_docker_daemon.log
	rm -f ${PHD_DOCKER_LOGDIR}/phd_docker_remote_daemon.log
	$PHD_DOCKER_LIB/fence_docker_daemon > ${PHD_DOCKER_LOGDIR}/fence_docker_daemon.log 2>&1 &
	$PHD_DOCKER_LIB/phd_docker_remote_daemon > ${PHD_DOCKER_LOGDIR}/phd_docker_remote_daemon.log 2>&1 &
}

integrate_remote_containers()
{
	local cluster_node="${cluster_nodeprefix}1"	

	while true; do
		exec_cmd "cibadmin -Q > /dev/null 2>&1" "$cluster_node"
		if [ $? -eq 0 ]; then
			break;
		fi
		sleep 2
		echo "waiting for cluster to initialize in order to integrate remote nodes"
	done

	launch_helper_daemons
	exec_cmd "pcs stonith create shooter fence_docker_cts" "$cluster_node"

	for (( c=1; c <= $remote_containers; c++ ))
	do
		name="${remote_nodeprefix}${c}"
		exec_cmd "pcs resource create $name remote server=${remoteiprange}${c} op start timeout=10s" "$cluster_node"
		echo "integrating remote node $name"

	done

}
