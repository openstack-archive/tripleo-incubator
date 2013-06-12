OpenStack on OpenStack, or TripleO
===================================

Welcome to our TripleO incubator! TripleO is our pithy term for OpenStack
deployed on and with OpenStack. This repository is our staging area, where we
incubate new ideas and new tools which get us closer to our goal.

As an incubation area, we move tools to permanent homes in
https://github.com/stackforge once they have proved that they do need to exist.
Other times we will propose the tool for inclusion in an existing project (such
as nova or glance).

What is TripleO?
----------------

TripleO is an endeavour to drive down the effort required to deploy an
OpenStack cloud, increase the reliabilty of deployments and configuration
changes - and hopefully consolidate the disparate operations projects around
OpenStack.

TripleO is the use of a self hosted OpenStack infrastructure - that is
OpenStack bare metal (nova and cinder) + Heat + diskimage-builder + in-image
orchestration such as Chef or Puppet - to install, maintain and upgrade itself.

This is combined with Continuous Integration / Continuous Deployment (CICD) of
the environment to reduce the opportunity for failures to sneak into
production.

Finally end user services such as Openstack compute virtual machine hosts, or
Hadoop are deployed as tenants of the self hosted bare metal cloud. These can
be deployed using any orchestration layer desired. In the specific case of
deploying an OpenStack virtual compute cloud, the Heat orchestration rules
used to deploy the bare metal cloud can be used.

Benefits
--------

Driving the cost of operations down, increasing reliability of deployments and
consolidating on a single API for deploying machine images, to get great
flexibility in hardware use and more skill reuse between administration of
different layers.

The use of gold images allows one to test precisely what will be running in
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

The use of cloud APIs for bare metal deployment permit trivial migration of
machine between roles - whether that is infrastructure, compute host, or
testbed.

Using OpenStack as the single source of control at the hardware node level
avoids awkward hand offs between different provisioning systems. We believe
that having a single tool chain to provision and deploy onto hardware is
simpler and lower cost to maintain than having heterogeneous systems.

Current status
--------------

TripleO is a work in progress : we're building up the facilities needed to
deliver the full story incrementally. Proof of concept implementations exist
for all the discrete components - sufficient to prove the design, though
(perhaps) not what will be used in production. In particular we don't have
a full HA story in place, which leads to requiring a long lived seed facility
rather than a fully self-sustaining infrastructure.  We track bugs affecting
TripleO itself at https://bugs.launchpad.net/tripleo/.

### Diskimage-builder

The lowest layer in the dependency stack, diskimage-builder can be used to
customise generic disk images for use with Nova bare metal. It can also be
used to provide build-time specialisation for disk images. Diskimage-builder
is quite mature and can be downloaded from
https://github.com/diskimage-builder.

### Nova bare-metal / Ironic

The next layer up, In OpenStack Grizzly Nova bare-metal is able to deliver
ephemeral instances to physical machines with multiple architectures.
By ephemeral instances, we mean that local storage is lost when a new
image is deployed / the instance is rebuilt. So the machines operate in
exactly the same fashion as if one installed a regular operating system
instance on the machine. Nova depends on a partition image to copy into
the machine, though the image can be totally generic - diskimage-builder
can create such images.

During the Portland ODS consensus emerged that the Nova bare-metal plumbing
should be in a dedicated project, which is called Ironic - these limitations
still apply, but will mostly not be be fixed in Nova bare-metal, instead in
Ironic.

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
 - Node deployment to large numbers of nodes can saturate networks - content is
   deployed using dd + iscsi (rather than e.g. bittorrent).

### Heat

Heat is the orchestration layer in TripleO - it glues the various services
together in the cluster, arbitrates deployments and reconfiguration.

Heat is quite usable in Grizzly, though some additional planned features will
make the TripleO story easier and more robust. Heat depends on the Nova API to
provision and remove instances in the cluster it is managing.

Caveats / limitations:
 - deployments/reconfigurations currently take effect immediately, rather
   than keeping a fraction of the cluster capacity unaffected. Workaround
   by defining multiple redundant groups to provide an artificial coordination
   point. A special case of this is HA pairs, where ideally Heat would know
   to take one side down, then the other.
 - deployments/reconfigurations only pay attention to the Nova API status
   rather than also coordinating with monitoring systems. Workaround by 
   tying your monitoring back into Heat to trigger rollbacks.

### os-apply-config/os-refresh-config

These tools work with the Heat delivered metadata to create configuration
files on disk (os-apply-config), and to trigger in-instance reconfiguration
including shutting down services and performing data migrations. They are new
but very simple and very focused.

os-apply-config reads a JSON metadata file and generates templates. It can be
used with any orchestration layer that generates a JSON metadata file on disk.

os-refresh-config subscribes to the Heat metadata we're using, and then invokes
hooks - it can be used to drive os-apply-config, or Chef/Puppet/Salt or other
configuration management tools.

### tripleo-image-elements

These diskimage-builder elements create build-time specialised disk/partition
images for TripleO. The elements build images with software installed but
not configured - and hooks to configure the software with os-apply-config. 
OpenStack is deployable via the elements that have been written but it is not
yet setup for full HA. Downloadable from
https://github.com/stackforge/tripleo-image-elements.

Caveats/Limitations:
 - No support for image based updates yet. (Requires separating out updateable
   configuration and persistent data from the image contents - which depends
   on cinder for baremetal).
 - Full HA is not yet implemented
   https://bugs.launchpad.net/quantum/+bug/1174132
 - Bootstrap removal is not yet implemented (depends on full HA).
 - Currently assumes two clouds: under cloud and over cloud. Long term we would
   like to be able to offer a single cloud, which is primarily (but not
   entirely) configuration.

### tripleo-heat-templates

These templates provide the rules describing how to deploy the baremetal 
undercloud and virtual overclouds.  Downloadable from
https://github.com/stackforge/tripleo-heat-templates.

Deploying
---------

As TripleO is not finished, deploying it is not as easy as we intend it to be.
Additionally as by definition it will replace existing facilities (be those
manual or automated) within an organisation, some care is needed to make
migration, or integration smooth.

This is a sufficiently complex topic, we've created a dedicated document for
it - [Deploying TripleO] (./Deploying.md). A related document is the
instructions for doing [Dev/Test of TripleO] (./devtest.md).

Architecture
------------

We start with an [image builder]
(https://github.com/stackforge/diskimage-builder/), and rules for that to
[build OpenStack images] (https://github.com/stackforge/tripleo-image-elements/).
We then use [Heat] (https://github.com/openstack/heat) to orchestrate deployment
of those images onto bare metal using the [Nova baremetal driver]
(https://wiki.openstack.org/wiki/Baremetal).

Eventually we will have the Heat instance we use to deploy both the undercloud
and overcloud hosted in the undercloud. That depends on a full-HA setup so that
we can upgrade itself using rolling deploys... and we haven't implemented the
full HA setup yet. Today, we deploy the undercloud from a Heat instance hosted
in a seed cloud just big enough to deploy the undercloud. Then the undercloud
Heat instance deploys the overcloud.

We use this self contained bare metal cloud to deploy a kvm (or Xen or
whatever) OpenStack instance as a tenant of the bare metal cloud. In future we
would like to consolidate this into one cloud, but there are technical and
security issues to overcome first.

So this gives us three clouds:

1. A KVM hosted single-node bare-metal cloud that owns a small set of machines
   we deploy the undercloud onto. This is the 'seed cloud'.
1. A baremetal hosted single-node bare-metal cloud that owns the rest of the
   datacentre and we deploy the overcloud onto. The is the 'under cloud'.
1. A baremetal hosted many-node KVM cloud which is deployed on the undercloud.
   This is the user facing cloud - the 'over cloud'.

Within each machine we use small focused tools for converting Heat metadata to
configuration files on disk, and handling updates from Heat. It is possible to
replace or augment those with Chef/Puppet/Salt - working well in existing
operational environments is a key goal for TripleO.

We have future worked planned to perform cloud capacity planning, node
allocation, and other essential operational tasks.


Development plan
================

Stage 1 - Implemented but not polished
--------------------------------------

OpenStack on OpenStack with three distinct clouds:

1. A seed cloud, runs baremetal nova-compute and deploys instances on bare
   metal. Hosted in a KVM or similar virtual machine within a manually
   installed machine. This is used to deploy the under cloud.
1. The under cloud, runs baremetal nova-compute and deploys instances on bare
   metal, is managed and used by the cloud sysadmins.
1. The over cloud, which runs using the same images as the under cloud, but as
   a tenant on the undercloud, and delivers virtualised compute machines rather
   than bare metal machines.

The overcloud runs a GRE overlay network; the undercloud runs on flat networking, 
as does the seed cloud. The seed cloud and the undercloud can use the same
network as long as non-overlapping ranges are setup.

Infrastructure like Glance and Swift will be duplicated - both clouds will need
their own, to avoid issues with skew between the APIs in the two clouds.

The under cloud will, during its deployment, include enough images to bring
up the virtualised cloud without internet access, making it suitable for
deploying behind firewalls and other restricted networking environments.

Enrollment of machines is manual, as is hardware setup including RAID.

Stage 2
-------

OpenStack on OpenStack with two distinct clouds. The seed cloud from stage 1
is replaced by a full HA configuration in the undercloud, permitting it to
host itself and do rolling deploys across it's own servers. This requires
improvements to Heat as well as a full HA setup. The initial install of the
undercloud will be done using a seed cloud, but that will hand-off to the
undercloud and stop existing once the undercloud is live.

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
detect spoofing are advised. TXT and/or UEFI secure boot may help, though
key distribution is still an issue.

Also requests from baremetal machines to the Nova/EC2 meta-data service
may be transmitted over an unsecured network, at least until full hardware
SDN is in palce. This carries the same attack vector as the PXE problems noted
above, and so should be given similar consideration.

Machine State
-------------

Currently there is no way to guarantee preservation (or deletion) of any of the
drive contents on a machine if it is deleted in nova baremetal. The planned
cinder driver will give us an API for describing what behaviour is needed on
an instance by instance basis.

See also
--------
https://github.com/tripleo/incubator-bootstrap contains the scripts we run on
the devstack based bootstrap node - but these are no longer maintained, as
we have moved to tripleo-image-element based bootstrap nodes.
