OpenStack on OpenStack, or TripleO
===================================

Welcome to our TripleO incubator! TripleO is our pithy term for OpenStack
deployed on and with OpenStack. This repository is our staging area, where we
incubate new ideas and new tools which get us closer to our goal.

As an incubation area, we move tools to permanent homes in
https://github.com/stackforge once they have proved that they do need to exist.
Other times we will propose the tool for inclusion in an existing project (such
as nova or devstack).

What is TripleO?
----------------

TripleO is a project to automate the operations of an OpenStack cloud.

We start with an [image builder]
(https://github.com/stackforge/diskimage-builder/), and rules for that to
[build OpenStack images] (https://github.com/stackforge/tripleo-image-elements/).
We then use [Heat] (https://github.com/openstack/heat) to orchestrate deployment
of those images onto bare metal using the [Nova baremetal driver]
(https://wiki.openstack.org/wiki/GeneralBareMetalProvisioningFramework).

The Heat instance we use is hosted in the same cloud we're deploying, taking
advantage of rolling deploys + a fully redundant deployment to avoid needing
any manually maintained infrastructure.

Within each machine we use small focused tools for converting Heat metadata to
configuration files on disk, and handling updates from Heat. It is possible to
replace those with e.g. Chef or Puppet if desired.

Finally, we use this self contained bare metal cloud to deploy a kvm (or Xen or
whatever) OpenStack instance as a tenant of the bare metal cloud. In future we
would like to consolidate this into one cloud, but there are technical and
security issues to overcome first.

We have future worked planned to perform cloud capacity planning, node
allocation, and other essential operational tasks.

Why?
----

Driving the cost of operations down, increasing reliability of deployments and
consolidating on a single API for deploying machine images, to get great
flexibility in hardware use.

The use of gold images allows us to test precisely what will be running in
production in a test environment - either virtual or physical. This provides
early detection of many issues. Gold image building also ensures that there
is no variation between machines in production - no late discovery of version
conflicts, for instance.

Using CI/CD testing in the deployment pipeline gives us:

- The ability to deploy something we have tested.

- With no variation on things that could invalidate those tests (kernel
  version, userspace tools OpenStack calls into, ...)

- While varying the exact config (to cope with differences in e.g. network
  topology between staging and production environments).


None of the existing ways to deploy OpenStack permit you to move hardware
between being cloud infrastructure to cloud offering and back again.
Specifically, a given hardware node has to be either managed by e.g. Crowbar,
or not managed by Crowbar and enrolled with OpenStack - and short of doing
shenanigans with your switches, this actually applies at a broadcast domain
level. Virtualising the role of hardware nodes provides immense freedom to run
different workloads via a single OpenStack cloud.

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

Broad conceptual plan
=====================

Stage 1
-------

OpenStack on OpenStack with two distinct clouds:

1. The under cloud, runs baremetal nova-compute and deploys instances on
   bare metal, is managed and used by the cloud sysadmins, starts deployed onto
   a laptop or other similar device in a VM.
1. The over cloud, which runs using the same images as the under cloud, but as
   a tenant on the undercloud, and delivers virtualised compute machines rather
   than bare metal machines.

Flat networking will be in use everywhere: the bootstrap cloud will use a single
range (e.g. 192.0.2.0/26), the virtualised cloud will allocate instances in
another range (e.g. 192.0.2.64/26), and floating ips can be issued to any range
the cloud operator has available. For demonstration purposes, we can issue
floating ips in the high half of the bootstrap ip range (e.g. 192.168.2.129/25).

Infrastructure like Glance and Swift will be duplicated - both clouds will need
their own, to avoid issues with skew between the APIs in the two clouds.

The under cloud will, during its deployment, include enough images to bring
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

1. The under cloud is used ts in Stage 1.
1. KVM or Xen Nova compute nodes are deployed into the cloud as part of the
   admin tenant, and offer their compute capacity to the under cloud.
1. Low overhead services can be redeployed as virtual machines rather than
   physical (as long as they are machines which the cluster can be rebooted
   without.

Quantum will be in use everywhere, in two layers: The hardware nodes will
talk to Openflow switches, allowing secure switching of a hardware node between
use as a cloud component and use by a tenant of the cloud. When a node is
being used a cloud component, traffic from the node itself will flow onto the
cloud's own network (managed by Quantum), and traffic from instances running
on that node will participate in their own Quantum defined networks.

Infrastructure such as Glance, Swift and Keystone will be solely owned by the
one cloud: there is no duplication needed.

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
https://github.com/tripleo/incubator/blob/master/notes.md - for technical 
setup walk-thru.
and
https://github.com/tripleo/incubator-bootstrap contains the scripts we run on
the devstack based bootstrap node.
