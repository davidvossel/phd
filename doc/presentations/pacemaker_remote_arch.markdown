# Pacemaker Remote Architecture Overview

This is meant to be a pacemaker_remote developer overview.

## Pacemaker Use Cases

Pacemaker remote has two use cases which are represented by two code paths within the policy engine.

### guest

Pacemaker_remote is living within a resource (likely a VM or Container) controlled by pacemaker. This use case allows pacemaker to manage resources within a VM which pacemaker is also controlling. Think "nesting"
 
When a user defines a guest remote node they do this by defining the VM/container instance (using something similar to the VirtualDomain resource-agent) and then setting the remote-node meta attribute. Internally when pacemaker sees the 'remote-node' meta attribute, it knows that the resource definition that attribute is assigned to is acting as a host for a pacemaker_remote instance. From there pacemaker launches the VM/Container instance and the launches an implicitely define ocf:pacemaker:remote connection resource to establish a connection to pacemaker_remote in the VM/Container.

Really really understand this part. When remote-node is set as a metadata attribute, pacemaker creates a resource definition implicitly just for the connection to the remote-node.

### Baremetal

Pacemaker_remote is living on a system (whether it be virtual or baremetal) that is not directly controlled by the cluster as a resource. Basically, pacemaker_remote lives at the same level as all the other cluster nodes running the full pacemaker+corosync stack. This use case is primarily used to scale pacemaker.

When a user defines a baremetal remote node they do this by defining a resource using the ocf:pacemaker:remote resource-agent. Think back on the 'guest' use case when I talked about the implicit connection resource that is made when 'remote-node' is set on as a metadata option. The baremetal use case is explicitly defining the exact same resource.

### Guest vs. Baremetal
Internally, the major differentiation between the baremetal and guest use case internally is how the connection resource is defined.

Guest: implicitly defined using the remote-node meta attribute on another resource (like a vm/container).
Baremetal: explicilty defined directly using the ocf:pacemaker:remote resource agent.

# Pacemaker Remote connections.
Pacemaker communicates with pacemaker_remote instances through a connection resource. Understand that there is a trick going on here. The connection resource is defined as being ocf:pacemaker:remote, but if you look at /usr/lib/ocf/resource.d/pacemaker/remote you'll see that the resource agent doesn't actually do anything.

So, what's actually going on here?

Pacemaker treats this resource differently than all the other resources. This resource's logic actually lives within the crmd in the crmd/remote_lrmd_ra.c file. 

lrm_state_t: this structure represents a connection to a lrmd instance or a pacemaker_remote instance. In reality the lrmd and pacemaker_remote are the same thing. The only difference is the lrmd is communicated with via IPC and pacemaker_remote is communicated with using TLS. Other than that, the exact same client API is used for both.

When pacemaker starts there's a default lrm_state_t structure created to talk to the local lrmd instance.

When a remote node is defined a new lrm_state_t structure is created to talk to the remote lrmd (pacemaker_remote) instance.

When actions are being executed on a remote node, those actions are proxied through a cluster node and executed on the remote's lrm_state_t structure. The policy engine knows what cluster node a pacemaker_remote connection is currently active on and routes remote node resource actions through the cluster node. When the action hits the cluster node, it redirected to the remote node's lrm_state_t structure which in turn executes the action remotely via TLS.

NOTE: This is the trickiest part of all of this.

- The start/stop/monitor actions for a remote connection resource are executed on the local (IPC) lrm_state_t object. These actions are then routed directly to the crmd/remote_lrmd_ra.c file which holds all the actual logic for the ocf:pacemaker:remote resource agent.
- Actions being executed on the remote connection are executed using the remote's lrm_state_t object and have NOTHING to do with crmd/remote_lrmd_ra.c file.


# Fencing
Fencing is a critical part in what makes remote nodes safe and reliable.

## Fencing Baremetal Remote Nodes

One simple rule.

If a baremetal remote node connection is ever unexpectedly severed (lost), then the remote node is fenced.

There's only one exception to this rule. If the cluster node a remote connection lives on is lost, the cluster will attempt to re-establish a connection to the remote node on another cluster node. If that reconnection fails, then the remote node will be fenced. If that reconnection succeeds, then all the state on the remote node must be redetected because the connection was severed for a period of time. This ensures no resource failures are left undetected.

## Fencing Guest Remote Nodes

Guest remote nodes are fenced differently than baremetal remote nodes. Since pacemaker has control of the resource (vm/container) that pacemaker_remote is running within, fencing is as simple as stopping the guest resource (killing the vm/container). This is achieved by forcing the guest resource to recover if the pacemaker_remote connection resource associated with the guest fails.

So, for guest remote nodes, fencing is implied after the guest resource's "stop" action is executed. If the "stop" action fails, fencing is escallated to fencing the cluster node the guest resource lives on with an actual fencing device. In practice, if this escallation ever occurs, then the guest's resource agent has something wrong with it.

# Migrating Remote Node Connection Resources

By default, baremetal remote node connection resources can freely float between cluster nodes. This is performed using the typical migration logic and actions just like any other resource. You can see how this migration logic is implemented for the connection resource by looking in the crmd/remote_lrmd_ra.c file. The big thing to note here is that at no point during the migration process is the remote_node's connection completely disconnected from the cluster. During the migration there is a takeover event which ensures that no time gap occurs as the connection is handed off from the source node to the destination node. This is super important because it ensures us that any failure that occurs on a resource living on a remote node will not somehow get lost during the migration.

# Reconnection interval

The reconnection interval feature exists to reattempting recovery of a baremetal remote node after the remote node is fenced. After a remote node is fenced, pacemaker will wait the duration of the reconnection interval before attempting to reconnect to the remote node. This allows the remote node to have time to come back online (when possible). If the reconnection attempt fails, pacemaker will keep trying to reconnect to the remote node at the specified interval. This feature is basically 'failure-timeout' with some other special logic specific to remote nodes baked in.

# Resource Discovery (Probes)

Before starting a resource for the first time, Pacemaker performs resource discovery to determine whether or not that resource is already active within the cluster. This allows Pacemaker to be certain a unique resource is not running in multiple locations at the same time. In the past, there was only a small performance penalty caused by resource discovery. However, once remote nodes entered into the scene this penalty became exponentially more expensive.

## The Math

To illustrate the performance issue, lets compare a traditional 3 node pacemaker against a more advanced 100 node cluster with using pacemaker_remote.

(number of nodes) * (unique resources) = (number of probe actions)

If the 3 node cluster has 30 resources being managed this results in a mere 90 probe actions. No big deal. However, for the 100 node cluster this results in 3000 probe actions. To complicate the issue even more, the 100 node cluster likely has way more than 30 resources it manages. If that number grew to something like 5 resources per a node, the 100 node cluster could be required to execute as many as 50,000 probe actions... This would take a really really long time.

so.

5 resources per node (15 total resources) for 3 node cluster = 90 probes
5 resource per node (500 total resources) for 100 node cluster = 50,000 probes

If each probe took 1 second, the 50,000 probes would take over 13 hours to complete. That's horrible. Luckily we know how to fix all of this.

## Mitigating poor performance

### Use Cloned Resources.

Typically when pacemaker remote is being used to horizontally scale an application, most of the remote nodes are running the exact same resources. By using cloned resources to achieve this, probe actions are drastically reduced.

For example, 5 cloned resources replicated across 100 nodes results in only 500 probe actions. 5 unique resources per a node in a 100 node cluster results in 50,000 probes. Both of these clusters are running the same number of resources (5 resources * 100 nodes = 500 total resources), but by using cloned resources we can exponentially reduce the performance impact of resource discovery.

### Use resouce-discovery=exclusive|never

One common use case we are seeing is a small set of unique control plane resources mixed in with much larger set of cloned resources that are spread across hundreds of remote nodes.

For example, Red Hat's OpenStack HA Architecture uses 3 nodes to manage around 60 or so OpenStack control plane services, and uses 100s of pacemaker remote nodes to manage cloned compute services. Because of the way this deployment is designed, it is impossible for the control plane to be active on a compute node, so there is no reason for Pacemaker to probe for control plane resources on a compute node.

In order to restrict what nodes pacemaker will probe a resource on, we created the resource-discovery option. 60 resources probed across 3 nodes results in 360 probe actions which is much better than the 6000 probe actions that would occur if the 60 resources were probed on the remote nodes as well.
