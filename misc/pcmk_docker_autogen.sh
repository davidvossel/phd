#!/bin/bash

node_ips=""
containers="2"
from="fedora"
#from="fedora"
pull=0
iprange="172.17.0."
gateway="172.17.42.1"
reuse=0
prev_image=""
image=""
run_cts=0
pcmklogs="/var/log/pacemaker.log"
doc_opts=""
debug_container=0

function helptext() {
	echo "pcmk_docker_autogen.sh - A tool for generating pacemaker clusters locally with docker containers."
	echo ""
	echo "Usage: pcmk_docker_autogen.sh [options]"
	echo ""
	echo "Options:"
	echo "-c, --containers    Specify the number of containers to generate, defaults to $containers."
	echo "-d, --cleanup-only  Cleanup previous containers only."
	echo "-D, --debug-mode    Launch a container in interactive mode for testing."
	echo "-f, --from          Specify the FROM image to base the docker containers off of. Default is \"$from\""
	echo "-o, --doc-opts      Connection options to pass to docker daemon for every command"
	echo "-p, --pull          Force pull \"from\" image regardless if it exists or not."
	echo "-r, --reuse-image   Reuse image built from previous cluster if previous image is detected."
	echo "-t, --cts-test      Run cts on docker instances"
	echo ""
	exit $1
}

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
	yum list installed | grep "docker-io" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		yum install docker-io docker
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
	prev_image=$(docker $doc_opts ps -a | grep docker  | awk '{print $2}' | uniq)
	docker $doc_opts stop $(docker $doc_opts ps -a | grep docker | awk '{print $1}') > /dev/null 2>&1
	docker $doc_opts rm $(docker $doc_opts ps -a | grep docker | awk '{print $1}') > /dev/null 2>&1
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

	# this gets around a bug in rhel 7.0
	touch /etc/yum.repos.d/redhat.repo

	rm -f Dockerfile
	rm -rf repos
	mkdir repos
	cp /etc/yum.repos.d/* repos/
	cat << END >> Dockerfile
FROM $from
ADD /repos /etc/yum.repos.d/
RUN yum install -y net-tools pacemaker resource-agents pcs corosync which
ADD /launch_scripts /root/
ENTRYPOINT /root/launch.sh
END

	# make launch script.
	echo "Making ENTRYPOINT script"
	rm -rf launch_scripts
	mkdir launch_scripts
	cat << END >> launch_scripts/launch.sh
#!/bin/bash
sleep 10000000
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
	echo "Launching containers"


	for (( c=1; c <= $containers; c++ ))
	do
		name="docker${c}"
		echo "Launching node $name"

		if [ $debug_container -eq 0 ]; then
			docker $doc_opts run -d -P -h $name --name=$name $image /bin/bash
		else
			docker $doc_opts run -i -t -P -h $name --name=$name $image /bin/bash
			exit 0
		fi

		ip="$(docker inspect $name | grep IPAddress | awk '{print $2}' | sed s/\"//g | sed s/,//g)"

		if [ -z "$node_ips" ]; then
			node_ips="$ip"
		else
			node_ips="${node_ips} ${ip}"
		fi

	done
}

launch_pcmk()
{

	echo "Starting pacemaker on IP list: $node_ips"

	for (( c=1; c <= $containers; c++ ))
	do
		name="docker${c}"

		verify_connection "$name" 
		exec_cmd "pcs cluster setup --local --name mycluster $node_ips"  "$name" > /dev/null 2>&1
		if [ "$?" -ne 0 ]; then
			exec_cmd "pcs cluster setup --local mycluster $node_ips"  "$name" > /dev/null 2>&1
		fi
		exec_cmd "/usr/share/corosync/corosync start" "$name" > /dev/null 2>&1
		exec_cmd "export PCMK_debugfile=$pcmklogs && pacemakerd &" "$name" > /dev/null 2>&1
	done

	echo "DONE"
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
	-D|--debug-mode) debug_container=1; shift;;
	-f|--from) from="$2"; shift; shift;;
	-o|--doc-opts) doc_opts=$2; shift; shift;;
	-p|--pull) pull=1; shift;;
	-r|--reuse) reuse=1; shift;;
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
launch_pcmk
launch_cts
