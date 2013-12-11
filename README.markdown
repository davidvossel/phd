# phd - The study of applied Pacemaker arts.

The phd project allows users to quickly initialize an HA cluster to a specific cluster scenario.

To execute a phd scenario on a cluster, the user must first create a cluster definition file. This file describes what nodes the cluster has as well as what shared cluster resources are available (such as floating ips and shared storage).

An example cluster_definition file can be found in /etc/phd/cluster_definition.conf.example

## INSTALLING

./autogen.sh && ./configure && make install

Run 'phd_exec -h' see usage.

## Example Apache Deployment
Execute the example apache server on a three node cluster.
NOTE, The node executing this script must be capable of ssh communication without passwords to the other nodes.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* phd_exec -s example.scenario

## Example Apache deployment on shared storage
Execute an apache server with the /var/www file living on shared storage.
NOTE, The node executing this script must be capable of ssh communication without passwords to the other nodes.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* echo "shared_storage=/dev/vdb" >> /etc/phd/cluster_definition.conf
* phd_exec -s apache_shared_lvm.scenario

## Example NFS deployment on shared storage
Execute an NFS deployment on top of shared storage
NOTE, The node executing this script must be capable of ssh communication without passwords to the other nodes.

* echo "nodes=node1 node2 node3" > /etc/phd/cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> /etc/phd/cluster_definition.conf
* echo "shared_storage=/dev/vdb" >> /etc/phd/cluster_definition.conf
* phd_exec -s nfs_shared_clvmd.scenario

