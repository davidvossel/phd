#!/bin/bash

containers="2"
from="fedora"
#from="fedora"
pull=0
iprange="172.17.0."
gateway="172.17.42.1"
ssh_keys="$HOME/.ssh/"
reuse=0
prev_image=""
image=""
run_cts=0
pcmklogs="/var/log/pacemaker.log"
doc_opts=""

function helptext() {
	echo "pcmk_docker_autogen.sh - A tool for generating pacemaker clusters locally with docker containers."
	echo ""
	echo "Usage: pcmk_docker_autogen.sh [options]"
	echo ""
	echo "Options:"
	echo "-c, --containers    Specify the number of containers to generate, defaults to $containers."
	echo "-d, --cleanup-only  Cleanup previous containers only."
	echo "-f, --from          Specify the FROM image to base the docker containers off of. Default is \"$from\""
	echo "-o, --doc-opts      Connection options to pass to docker daemon for every command"
	echo "-p, --pull          Force pull \"from\" image regardless if it exists or not."
	echo "-r, --reuse-image   Reuse image built from previous cluster if previous image is detected."
	echo "-s, --ssh-keys      Specify ssh directory to copy keys over from. Defaults to \"$ssh_keys\""
	echo "-t, --cts-test      Run cts on docker instances"
	echo ""
	exit $1
}

docker_setup()
{
	# make sure we have docker installed
	yum list installed | grep "docker-io" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		yum install docker-io
	fi
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
	prev_image=$(docker $doc_opts ps -a | grep docker  | awk '{print $2}' | uniq)
	docker $doc_opts stop $(docker $doc_opts ps -a | grep docker | awk '{print $1}') > /dev/null 2>&1
	docker $doc_opts rm $(docker $doc_opts ps -a | grep docker | awk '{print $1}') > /dev/null 2>&1
	if [ $reuse -eq 0 ]; then
		docker $doc_opts rmi $prev_image > /dev/null 2>&1
		sed -i.bak '/docker.*/d' $ssh_keys/known_hosts
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
	rm -rf ssh_keys
	mkdir ssh_keys
	cp $ssh_keys/id* ssh_keys/
	cp $ssh_keys/authorized_keys ssh_keys/
	cat << END >> Dockerfile
FROM $from
RUN yum install -y net-tools openssh-server pacemaker resource-agents pcs corosync
ADD /ssh_keys /root/.ssh/
ADD /launch_scripts /root/
ENTRYPOINT /root/launch.sh
END

	# make launch script.
	echo "Making ENTRYPOINT script"
	rm -rf launch_scripts
	mkdir launch_scripts
	cat << END >> launch_scripts/launch.sh
#!/bin/bash
mkdir -p /var/lock/subsys/
ifconfig eth0 \$DOCK_IP
route add 0.0.0.0 gw \$DOCK_GATEWAY eth0
ifconfig
if [ ! -e /etc/ssh_host_ecdsa_key ]; then
	sshd-keygen
fi

/sbin/sshd
echo "sshd exit code: $?"
pcs cluster setup --local mycluster \$(echo \$DOCK_NODES | tr '_' ' ')
/usr/share/corosync/corosync start
if [ $? -ne 0 ]; then
	echo "corosync failed to launch!"
fi

export PCMK_debugfile=$pcmklogs
pacemakerd
END
	chmod 755 launch_scripts/launch.sh

	# generate image
	echo "Making image"
	docker $doc_opts build .
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to generate docker image"
	fi
	image=$(docker $doc_opts images -q | head -n 1)
}

launch_containers()
{
	echo "Launcing containers"

	for (( c=1; c <= $containers; c++ ))
	do
		if [ -z $node_ips ]; then
			node_ips="${iprange}${c}"
		else
			node_ips="${node_ips}_${iprange}${c}"
		fi
	done

	for (( c=1; c <= $containers; c++ ))
	do
		name="docker${c}"
		ip="${iprange}${c}"

		sed -i.bak "/...\....\....\..* ${name}/d" /etc/hosts

		cat << END >> /etc/hosts
$ip     $name
END
		echo "Launching node $name"
		echo "docker $doc_opts run -d -e "DOCK_NODES=$node_ips" -e DOCK_IP=$ip -e DOCK_GATEWAY=$gateway -h $name --name=$name $image"
		docker $doc_opts run -d -e "DOCK_NODES=$node_ips" -e DOCK_IP=$ip -e DOCK_GATEWAY=$gateway -h $name --name=$name $image
	done
}

launch_cts()
{
	if [ $run_cts -eq 0 ]; then
		return;
	fi

	for (( c=1; c <= $containers; c++ ))
	do
		if [ -z $nodes ]; then
			nodes="docker${c}"
		else
			nodes="${nodes} docker${c}"
		fi
	done
	/usr/share/pacemaker/tests/cts/CTSlab.py --outputfile /var/log/cts.log --nodes "$nodes" -r --stonith "no" -c --test-ip-base "${iprange}100" --stack "mcp" --log-file="${pcmklogs}" --at-boot 1 100
}

while true ; do
	case "$1" in
	--help|-h|-\?) helptext 0;;
	-c|--containers) containers="$2"; shift; shift;;
	-d|--cleanup-only) prev_cluster_cleanup; exit 0;;
	-f|--from) from="$2"; shift; shift;;
	-o|--doc-opts) doc_opts=$2; shift; shift;;
	-p|--pull) pull=1; shift;;
	-r|--reuse) reuse=1; shift;;
	-s|--ssh-keys) ssh_keys=$2; shift; shift;;
	-t|--cts-test) run_cts=1; shift;;
	"") break;;
	*) helptext 1;;
	esac
done

# We have to re-launch docker with tcp ports open.
docker_setup
prev_cluster_cleanup
make_image
launch_containers
launch_cts
