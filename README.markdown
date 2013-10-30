# phd
The study of applied Pacemaker arts.

## Example Apache Deployment
Execute the example apache server on a three node cluster. NOTE, The node executing this script must be capable of ssh communication without passwords to the other nodes.

* echo "nodes=node1,node2,node3" >> cluster_definition.conf
* echo "floating_ips=192.168.122.200" >> cluster_definition.conf
* exec/scenario_exec.sh cluster_definition examples/example.scenario

