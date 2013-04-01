OpenStack on OpenStack, or TripleO
===================================

Welcome to our TripleO incubator! TripleO is our pithy term for OpenStack on
OpenStack. This repository is our staging area, where we incubate new ideas and
new tools which get us closer to our goal.

As an incubation area, we move tools to permanent homes in
https://github.com/stackforge once they have proved that they do need to exist.
Other times we will propose the tool for inclusion in an existing project (such
as nova or devstack).

What is TripleO?
----------------

TripleO is an image based toolchain for deploying OpenStack on top of
OpenStack, leveraging the [Nova Baremetal driver]
(https://wiki.openstack.org/wiki/GeneralBareMetalProvisioningFramework) for
image deployment and power control. This will eventually consist of a number of
small reusable tools to perform cloud capacity planning, node allocation,
[image building] (https://github.com/stackforge/diskimage-builder/), with
suitable extension points to allow folk to use their preferred systems
management tools, orchestration tools and so forth.

What isn't it?
--------------

TripleO isn't an orchestration tool, a workload deployment tool or a systems
management tool. Where there is overlap TripleO will either have a
super-minimal domain-specific implementation, or extension points to permit the
tool of choice (e.g. heat, puppet, chef).

Why?
----

Flexibility and reliability.

On the flexibility side, none of the existing ways to deploy OpenStack permit
you to move hardware between being cloud infrastructure to cloud offering and
back again.  Specifically, a given hardware node has to be either managed by
e.g. Crowbar, or not managed by Crowbar and enrolled with OpenStack - and short
of doing shenanigans with your switches, this actually applies at a broadcast
domain level. Virtualising the role of hardware nodes provides immense freedom
to run different workloads via a single OpenStack cloud.

Fitting this into any of the existing deployment toolchains is problematic:

- you either end up with a circular reference (e.g. Crowbar having to drive
  Quantum to move a node out of OpenStack and back to Crowbar, but Crowbar
  brings up OpenStack.

- or you end up with two distinct clouds and orchestration requirements to
  move resources between them. E.g. MAAS + OpenStack, or even - as this
  demo repository does, OpenStack + OpenStack.

Using OpenStack as the single source of control at the hardware node level
avoids this awkward hand off, in exchange for a bootstrap problem where
OpenStack becomes its own parent. We believe that having a single tool
chain to provision and deploy onto hardware is simpler and lower cost to
maintain, and so are choosing to have the bootstrap problem rather than
the handoff between provisioning systems problem.

For reliability, we want to be able to do CI / CD of the cloud, and that means
having great confidence in:

- Our ability to deploy something we have tested.

- With no variation on things that could invalidate those tests (kernel
  version, userspace tools OpenStack calls into, ...)

- While varying the exact config (to cope with differences in e.g. network
  topology between staging and production environments).

It is on this basis that we believe an imaging based solution will give us
that confidence: we can do all software installation before running any
tests, and merely vary the configuration between tests. That way, if we have
added something to the environment that will conflict, we find out during our
tests rather than when mixing e.g. nova in with nagios.

Broad conceptual plan
=====================

Stage 1
-------

OpenStack on OpenStack with two distinct clouds:

1. The bootstrap cloud, runs baremetal nova-compute and deploys instances on
   bare metal, is managed and used by the cloud sysadmins, and is initially
   deployed onto a laptop or other similar device.
1. The virtualised cloud, runs regular packaged OpenStack, and your tenants
   use this.

Flat networking will be in use everywhere: the bootstrap cloud will use a single
range (e.g. 192.0.2.0/26), the virtualised cloud will allocate instances in
another range (e.g. 192.0.2.64/26), and floating ips can be issued to any range
the cloud operator has available. For demonstration purposes, we can issue
floating ips in the high half of the bootstrap ip range (e.g. 192.168.2.129/25).

Infrastructure like Glance and Swift will be duplicated - both clouds will need
their own, to avoid issues with skew between the APIs in the two clouds.

The bootstrap cloud will, during its deployment, include enough images to bring
up the virtualised cloud without internet access, making it suitable for
deploying behind firewalls and other restricted networking environments.

Stage 2
-------

Use Quantum to provide VLANs to the bare metal, permitting segregated
management and tenant traffic.

<...>

Stage N
-------

OpenStack on itself: OpenStack on OpenStack with one cloud:

1. The bootstrap cloud is used to deploy a virtualised cloud as in Stage 1.
1. The virtualised cloud runs the NTT baremetal codebase, and has the nodes
   from the bootstrap cloud enrolled into the virtualised cloud, allowing it
   it to redeploy itself (as long as there are no single points of failure).

Quantum will be in use everywhere, in two layers: The hardware nodes will
talk to Openflow switches, allowing secure switching of a hardware node between
use as a cloud component and use by a tenant of the cloud. When a node is
being used a cloud component, traffic from the node itself will flow onto the
cloud's own network (managed by Quantum), and traffic from instances running
on that node will participate in their own Quantum defined networks.

Infrastructure such as Glance, Swift and Keystone will be solely owned by the
one virtualised cloud: there is no duplication needed.

Caveats
=======

It is important to consider some unresolved issues in this plan.

Security
--------

Nova baremetal does nothing to secure transfers via PXE on the
network. This means that a node spoofing DHCP and TFTP on the provisioning
network could potentially compromise a new machine. As these networks
should be under full control of the user, strategies to eliminate and/or
detect spoofing are advised.

Also requests from baremetal machines to the Nova/EC2 meta-data service
may be transmitted over an unsecured network. This carries the same
attack vector as the PXE problems noted above, and so should be given
similar consideration.

Machine State
-------------

Currently there is no way to guarantee preservation of any of the drive
contents on a machine if it is deleted in nova baremetal.

See also
--------

https://github.com/tripleo/incubator-bootstrap contains the scripts we run on
the bootstrap node.
