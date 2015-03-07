OpenStack on OpenStack, or TripleO
==================================

Welcome to our TripleO incubator! TripleO is our pithy term for OpenStack
deployed on and with OpenStack. This repository is our staging area, where we
incubate new ideas and new tools which get us closer to our goal.

As an incubation area, we move tools to permanent homes in OpenStack Infra once
they have proved that they do need to exist.  Other times we will propose the
tool for inclusion in an existing project (such as nova or glance).

What is TripleO?
----------------

TripleO is an endeavour to drive down the effort required to deploy an
OpenStack cloud, increase the reliability of deployments and configuration
changes - and hopefully consolidate the disparate operations projects around
OpenStack.

TripleO is the use of a self hosted OpenStack infrastructure - that is
OpenStack bare metal (nova and cinder) + Heat + diskimage-builder + in-image
orchestration such as Chef or Puppet - to install, maintain and upgrade itself.

This is combined with Continuous Integration / Continuous Deployment (CICD) of
the environment to reduce the opportunity for failures to sneak into
production.

Finally end user services such as OpenStack compute virtual machine hosts, or
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
(perhaps) not what will be used in production. In particular, we don't have
a full HA story in place, which leads to requiring a long lived seed facility
rather than a fully self-sustaining infrastructure.  We track bugs affecting
TripleO itself at https://bugs.launchpad.net/tripleo/.

Diskimage-builder
^^^^^^^^^^^^^^^^^

The lowest layer in the dependency stack, diskimage-builder, can be used to
customise generic disk images for use with Nova bare metal. It can also be
used to provide build-time specialisation for disk images. Diskimage-builder
is quite mature and can be downloaded from
https://git.openstack.org/cgit/openstack/diskimage-builder.

Nova bare-metal / Ironic
^^^^^^^^^^^^^^^^^^^^^^^^

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
 - Dynamic VLAN support is not yet implemented (but was specced at the Havana
   summit). Workaround is to manually configure it via Nova userdata.
   https://bugs.launchpad.net/tripleo/+bug/1174149
 - Node deployment to large numbers of nodes can saturate networks - content is
   deployed using dd + iscsi (rather than e.g. bittorrent).

Heat
^^^^

Heat is the orchestration layer in TripleO - it glues the various services
together in the cluster, arbitrates deployments and reconfiguration.

Heat is mature, though some additional planned features will make the
TripleO story easier and more robust. Heat depends on the Nova API to
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

os-apply-config/os-refresh-config/os-collect-config
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

These tools work with the Heat delivered metadata to create configuration
files on disk (os-apply-config), and to trigger in-instance reconfiguration
including shutting down services and performing data migrations. They are new
but very simple and very focused.

os-apply-config reads a JSON metadata file and generates templates. It can be
used with any orchestration layer that generates a JSON metadata file on disk.

os-refresh-config runs scripts grouped by common stages of system state
and ordered by lexical sorting. It can be used to drive any tool set, and
in TripleO is used to drive os-apply-config as well as service-specific
state management and migration scripts.

os-collect-config subscribes to the Heat metadata we're using, and then invokes
hooks - it can be used to drive os-refresh-config, or Chef/Puppet/Salt or other
configuration management tools.

tripleo-image-elements
^^^^^^^^^^^^^^^^^^^^^^

These diskimage-builder elements create build-time specialised disk/partition
images for TripleO. The elements build images with software installed but
not configured - and hooks to configure the software with os-apply-config.
OpenStack is deployable via the elements that have been written but it is not
yet setup for full HA. Downloadable from
https://git.openstack.org/cgit/openstack/tripleo-image-elements.

Caveats/Limitations:
 - Bootstrap removal is not yet implemented (depends on full HA).
 - Currently assumes two clouds: under cloud and over cloud. Long term we would
   like to be able to offer a single cloud for environments where that makes
   sense such as running a very minimal number of nodes but still wanting HA.
   This is primarily (but not entirely) configuration.

tripleo-heat-templates
^^^^^^^^^^^^^^^^^^^^^^

These templates provide the rules describing how to deploy the baremetal
undercloud and virtual overclouds. This also includes a python module used
for merging templates to allow template snippet re-use.  Downloadable from
https://git.openstack.org/cgit/openstack/tripleo-heat-templates

Deploying
---------

As TripleO is not finished, deploying it is not as easy as we intend it to be.
Additionally as by definition it will replace existing facilities (be those
manual or automated) within an organisation, some care is needed to make
migration, or integration smooth.

This is a sufficiently complex topic, we've created a dedicated document for it
- :doc:`deploying`.  A related document is the instructions for doing
:doc:`dev/test of TripleO <devtest>`.

Architecture
------------

There is a :download:`high level presentation <../../presentations/TripleO
architecture overview.odp>` accompanying these docs.

We start with an `image builder
<https://git.openstack.org/cgit/openstack/diskimage-builder/>`_, and rules for
that to `build OpenStack images
<https://git.openstack.org/cgit/openstack/tripleo-image-elements/>`_.  We then
use `Heat <https://git.openstack.org/cgit/openstack/heat>`_ to orchestrate
deployment of those images onto bare metal. Currently Heat can use either the
`Nova baremetal driver <https://wiki.openstack.org/wiki/Baremetal>`_ or `Ironic
<https://wiki.openstack.org/wiki/Ironic>`_ - Ironic is the default. Both are
tested in our CI process.

Eventually, we will have the Heat instance hosted in only the undercloud,
which we'll use to deploy both the undercloud and overcloud. That depends
on a full-HA setup so that it can upgrade itself using rolling deploys...
and we haven't implemented the full HA setup yet. Today, we deploy the
undercloud from a Heat instance hosted in a seed cloud just big enough
to deploy the undercloud. Then the undercloud Heat instance deploys the
overcloud.

We use this self contained bare metal cloud to deploy a kvm (or Xen or
whatever) OpenStack instance as a tenant of the bare metal cloud. In the
future we would like to consolidate this into one cloud, but there are
technical and security issues to overcome first.

So this gives us three clouds:

1. A KVM hosted single-node bare-metal cloud that owns a small set of machines
   we deploy the undercloud onto. This is the 'seed cloud'.
2. A baremetal hosted single-node bare-metal cloud that owns the rest of the
   datacentre and we deploy the overcloud onto. The is the 'under cloud'.
3. A baremetal hosted many-node KVM cloud which is deployed on the undercloud.
   This is the user facing cloud - the 'over cloud'.

Within each machine we use small focused tools for converting Heat metadata to
configuration files on disk, and handling updates from Heat. It is possible to
replace or augment those with Chef/Puppet/Salt - working well in existing
operational environments is a key goal for TripleO.

We have future worked planned to perform cloud capacity planning, node
allocation, and other essential operational tasks.


Development plan
----------------


Stage 1 - Implemented but not polished
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

OpenStack on OpenStack with three distinct clouds:

1. A seed cloud, runs baremetal nova-compute and deploys instances on bare
   metal. Hosted in a KVM or similar virtual machine within a manually
   installed machine. This is used to deploy the under cloud.
2. The under cloud, runs baremetal nova-compute and deploys instances on bare
   metal, is managed and used by the cloud sysadmins.
3. The over cloud, which runs using the same images as the under cloud, but as
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

Stage 2 - being worked on
^^^^^^^^^^^^^^^^^^^^^^^^^

OpenStack on OpenStack with two distinct clouds. The seed cloud from stage 1
is replaced by a full HA configuration in the undercloud, permitting it to
host itself and do rolling deploys across it's own servers. This requires
improvements to Heat as well as a full HA setup. The initial install of the
undercloud will be done using a seed cloud, but that will hand-off to the
undercloud and stop existing once the undercloud is live.

Stage N
^^^^^^^

OpenStack on itself: OpenStack on OpenStack with one cloud:

1. The under cloud is used as in Stage 1.
2. KVM or Xen Nova compute nodes are deployed into the cloud as part of the
   admin tenant, and offer their compute capacity to the under cloud.
3. Low overhead services can be redeployed as virtual machines rather than
   physical (as long as they are machines which the cluster can be rebooted
   without.

Neutron will be in use everywhere, in two layers: The hardware nodes will
talk to Openflow switches, allowing secure switching of a hardware node between
use as a cloud component and use by a tenant of the cloud. When a node is
being used a cloud component, traffic from the node itself will flow onto the
cloud's own network (managed by Neutron), and traffic from instances running
on that node will participate in their own Neutron defined networks.

Infrastructure such as Glance, Swift and Keystone will be solely owned by the
one cloud: there is no duplication needed.

Developer introduction and guidelines
-------------------------------------

Principles
^^^^^^^^^^

1. Developer tools (like disk-image-builder) should have a non-intrusive
   footprint on the machine of users. Requiring changing of global settings
   is poor form.
2. Where possible we run upstream code and settings without modification - e.g.
   we strongly prefer to use upstream defaults rather than our own. Only if
   there is no right setting in production should we change things.
3. We only prototype tools in tripleo-incubator: when they are ready for
   production use with stable APIs, we move them to some appropriate
   repository.
4. We include everyone who wants to deploy OpenStack using OpenStack tooling
   in the TripleO community - we support folk that want to use packages
   rather than source, or Xen rather than KVM, or Puppet / chef / salt etc.
5. Simple is hard to achieve but very valuable - and we value it. Things
   that complect or confound concepts may need more design work to work well.
6. We use OpenStack projects in preference to any others (even possibly to the
   exclusion of alternative backends). For instance, we have a hard dependency
   on Heat, rather than alternative cluster definition tools. This says nothing
   about the quality of such tools, rather that we want a virtuous circle where
   we can inform Heat about the needs of folk deploying cluster tools, and make
   Heat better to meet our needs - and benefit when Heat improves due to the
   effort of other people.

Getting started
^^^^^^^^^^^^^^^

See the TripleO userguide for basic setup instructions - as a developer you
need to be set up as a user too.

Efficient development
^^^^^^^^^^^^^^^^^^^^^

When working on overcloud features using virtual machines, just register all
your nodes directly with the seed - the seed and the undercloud are
functionally identical and can both deploy an overcloud.

When building lots of images, be sure to pass -u and --offline into
diskimage-builder. One way to do this is via ``DIB_COMMON_ELEMENTS`` though this
doesn't affect the demo `user` image we build at the end of
``devtest_overcloud.sh``. To affect that, export ``NODE_DIST`` - which will affect
all images. e.g. ``ubuntu --offline -u``. --offline prevents all cache
freshness checks and ensures the elements like ``pypi`` which use some online
resources disable those resources (if possible).

Always setup a network local distribution mirror - squid is great, but package
metadata is typically not cacheable or highly mutable, and a local mirror will
be a big timesaver.

Also always setup a local pypi mirror - either with pypi-mirror (we have
instructions in the diskimage-builder ``pypi`` element README.md) or
bandersnatch. Using pypi-mirror consumes less bandwidth and builds a mirror of
wheels as well, which provides further performance benefits.

Run small steps - TripleO is composed of small composable tools. Do not use
``devtest.sh`` as the entry point for development - it's a full run of the
logic of TripleO end to end, but most folk will be working on e.g. just the
overcloud, or undercloud deployment, or changing cinder scaling rules etc.

For many tasks even the ``devtest_overcloud.sh`` scoped scripts may be too
large and interfere with efficient development. Dive under and run the
core tools directly - that's what they are for.

Iterating on in-instance code
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

There are broadly three sets of code for TripleO - the heat templates which
define the cluster, the code that runs within instances to map heat metadata
to configuration files, restart servies etc, and code that runs after deployment
to customise the deployed cloud using APIs.

The best way to experiment with in-instance code is to build images and deploy
them but then if it fails ssh into the instance, tweak the state and re-run the
code (e.g. by running ``os-collect-config --force --one``).

Iterating on heat templates
^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can use heat stack-update to update a deployed stack which will take effect
immediately as long as the image id's have not changed - this permits testing
different metadata mappings without waiting for full initial deployments to take
effect.

Iterating on post-deploy code
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Generally speaking, just run API calls to put state back to whatever it would
be before your code runs. E.g. if you are testing nova flavor management code
you might delete all the flavors and recreate the initial defaults, then just
run your specific code again.

Caveats
-------

It is important to consider some unresolved issues in this plan.

.. _tested_platforms:

Tested platforms
^^^^^^^^^^^^^^^^

At this moment, the distributions that are tested by the CI systems are Ubuntu
and Fedora. Currently, we specifically test Ubuntu Trusty VMs and Fedora 20 VMs,
each running on both Ubuntu Trusty and Fedora 20 hosts.

Therefore, we encourage users to use these versions of either Ubuntu or Fedora
to have a smooth experience.

You may be able to run devtest on other distributions, as the devtest code
tries to identify the OS you use and match it against all major distributions
(CentOS, Debian, Fedora, openSUSE, RHEL, SUSE and Ubuntu).

By default, the undercloud and overcloud images will be built using the same OS
that devtest is running on, but this can be changed via environment variables
to decouple them.

If you use any other distribution not listed above, the script will identify
your machine as unsupported.

Security
^^^^^^^^

Nova baremetal does nothing to secure transfers via PXE on the
network. This means that a node spoofing DHCP and TFTP on the provisioning
network could potentially compromise a new machine. As these networks
should be under full control of the user, strategies to eliminate and/or
detect spoofing are advised. TXT and/or UEFI secure boot may help, though
key distribution is still an issue.

Also requests from baremetal machines to the Nova/EC2 meta-data service
may be transmitted over an unsecured network, at least until full hardware
SDN is in place. This carries the same attack vector as the PXE problems noted
above, and so should be given similar consideration.

Machine State
^^^^^^^^^^^^^

Currently there is no way to guarantee preservation (or deletion) of any of the
drive contents on a machine if it is deleted in nova baremetal. The planned
cinder driver will give us an API for describing what behaviour is needed on
an instance by instance basis.
