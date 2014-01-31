# phd - The study and application of the Pacemaker arts.

The phd project allows users to quickly initialize an HA cluster to a specific cluster scenario.

To execute a phd scenario on a cluster, the user must first create a cluster definition file. This file describes what nodes the cluster has as well as what shared cluster resources are available (such as floating ips and shared storage).

An example cluster_definition file can be found in /etc/phd/cluster_definition.conf.example

## INSTALLING

./autogen.sh && ./configure && make install

Run 'phd_exec -h' see usage.

## TEST REPO

I've made the repo I use for testing phd available.  The phd project has successfully been used in both fedora 20 and rhel6 based environments.

* wget -O /etc/yum.repos.d/vossel.repo http://davidvossel.com/repo/vossel-test.repo
* yum install phd

## SETUP

Before phd can be used, you must be able to either ssh into all the nodes in the cluster without requiring passwords (using ssh keys) or have qarshd enabled. Qarshd is a quality assurance tool that should never be used in a production environment.

phd defaults to using ssh unless the 'transport=qarsh' variable is set in the /etc/phd/cluster_definition.conf file.

## FENCING

Fencing devices are configured in the cluster_definition.conf file using the 'fence_cmd' option. Multiple entries of 'fence_cmd' can be used to define more complex fencing scenarios.  When no 'fence_cmd' options exist in the cluster definition, phd will automatically disable fencing allowing scenarios to continue to be executed. For more information on fencing, read the /etc/phd/cluster_definition.conf.example file.

## phd_exec tool

The phd_exec tool is used to execute cluster scenarios (deployments) on the cluster defined in the /etc/phd/cluster_definition.conf file.  Run phd_exec -h for usage information.

## Example Apache Deployment
Execute the example apache server on a three node cluster.  This is a good scenario to start with to test phd is working correctly.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* phd_exec -s example.scenario

## Example Apache deployment on shared storage
Execute an apache server with the /var/www file living on shared storage.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* echo "shared_storage=/dev/vdb" >> /etc/phd/cluster_definition.conf
* phd_exec -s apache-shared-lvm.scenario

## Example NFS deployment on shared storage
Execute an NFS deployment on top of shared storage.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* echo "shared_storage=/dev/vdb" >> /etc/phd/cluster_definition.conf
* phd_exec -s nfs-shared-clvmd.scenario

