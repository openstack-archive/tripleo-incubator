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

TripleO is the use of a self hosted OpenStack infrastructure - that is
OpenStack bare metal (nova and cinder) + Heat + diskimage-builder + in-image
orchestration such as Chef or Puppet - to install, maintain and upgrade itself.

This is combined with Continuous Integration / Continuous Deployment (CICD) of
the environment to reduce the opportunity for failures.

Finally end user services such as Openstack compute virtual machine hosts, or
Hadoop are deployed as tenants of the self hosted infrastructure. These can be
deployed using any orchestration layer desired.

Current status
--------------

TripleO is a work in progress : we're building up the facilities needed to
deliver the full story incrementally. Proof of concept implementations exist
for all the discrete components - sufficient to prove the design, though
(perhaps) not what will be used in production. We track bugs affecting TripleO
itself at https://bugs.launchpad.net/tripleo/.

### Diskimage-builder

The lowest layer in the dependency stack, diskimage-builder can be used to
customise generic disk images for use with Nova bare metal. It can also be
used to provide build-time specialisation for disk images. Diskimage-builder
is quite mature.

### Nova bare-metal

The next layer up, In OpenStack Grizzly Nova bare-metal is able to deliver
ephemeral instances to physical machines with multiple architectures.
By ephemeral instances, we mean that local storage is lost when a new
image is deployed / the instance is rebuilt. So the machines operate in
exactly the same fashion as if one installed a regular operating system
instance on the machine. Nova depends on a partition image to copy into
the machine, though the image can be totally generic.

Caveats / limitations:
 - no persistent storage (cinder) yet. This was specced out and is pending
   implementation.
   https://bugs.launchpad.net/tripleo/+bug/1174154
 - no raid hardware config yet (can workaround by baking a specific config into
   the deploy ramdisk)
   https://bugs.launchpad.net/tripleo/+bug/1174151
 - no support (yet) for booting an arbitrary ramdisk to do machine maintenance
   without tearing down the instance.
   https://bugs.launchpad.net/nova/+bug/1174518 (When there is an instance).
   https://blueprints.launchpad.net/nova/+spec/baremetal-operations (when
   there is no instance).
 - HA support is rudimentary at the moment : need to use corosync+pacemaker
   (work is in progress to have multiple bare-metal compute hosts dynamically
    take over each others configuration)
 - File injection is required due to the PXE boot configuration conflicting
   with Nova-network/Quantum DHCP (work is in progress to resolve this)
 - Dynamic VLAN support is not yet implemented (but was specced at the Havana
   summit). Workaround is to manually configure it via Nova userdata.
   https://bugs.launchpad.net/tripleo/+bug/1174149
 - Node content is deployed using dd + iscsi (rather than e.g. bittorrent).

### Heat

Heat is the orchestration layer in TripleO - it glues the various services
together in the cluster, arbitrates deployments and reconfiguration.

Heat is quite usable in Grizzly, though some additional features are planned
to make the TripleO story easier and more robust. Heat depends on the Nova
API to provision and remove instances in the cluster it is managing.

Caveats / limitations:
 - deployments/reconfigurations currently take effect immediately, rather
   than keeping a fraction of the cluster capacity unaffected. Workaround
   by defining multiple redundant groups to provide an artificial coordination
   point. A special case of this is HA pairs, where ideally Heat would know
   to take one side down, then the other.
 - deployments/reconfigurations only pay attention to the Nova API status
   rather than also coordinating with monitoring systems. Workaround by 
   tying your monitoring back into Heat to trigger rollbacks.

### os-config-applier/os-refresh-config

These tools work with the Heat delivered metadata to create configuration
files on disk (os-config-applier), and to trigger in-instance reconfiguration
including shutting down services and performing data migrations. These tools
are new but very simple and very focused.

os-config-applier reads a JSON metadata file and generates templates. It can
be used with any orchestration layer that generates a JSON metadata file on
disk.

os-refresh-config subscribes to the Heat metadata we're using, and then invokes
hooks - it can be used to drive os-config-applier, or Puppet or Chef or other
configuration management tools.

### tripleo-image-elements

These diskimage-builder elements create build-time specialised disk/partition
images for TripleO. The elements build images with software installed but
not configured - and hooks to configure the software with os-config-applier. 
Much of OpenStack is deployable via the elements that have been written but
it is not yet setup for full HA.

Caveats/Limitations:
 - No support for image based updates yet. (Requires separating out updateable
   configuration and persistent data from the image contents - which depends
   on cinder for baremetal).
 - Full HA is not yet implemented
   https://bugs.launchpad.net/quantum/+bug/1174132
 - Bootstrap installation is not yet implemented (depends on full HA).
 - Currently assumes two clouds: under cloud and over cloud. Long term story
   is to have a single cloud, which is primarily (but not entirely)
   configuration.

Deploying
---------

As TripleO is not finished, deploying it is tricky. Additionally as by
definition it will replace existing facilities (be those manual or automated)
within an organisation, some care is needed to make migration, or integration
smooth.

This is a sufficiently complex topic, we've created a dedicated document for
it - [Deploying TripleO] (./Deploying.md).

Design
------

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
