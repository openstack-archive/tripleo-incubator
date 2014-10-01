Deploying TripleO
=================

Components
----------

Essential Components
^^^^^^^^^^^^^^^^^^^^

Essential components make up the self-deploying infrastructure that is
the heart of TripleO.

-  Baremetal machine deployment (Nova Baremetal, soon to be 'Ironic')

-  Baremetal volume management (Cinder - not available yet)

-  Cluster orchestration (Heat)

-  Machine image creation (Diskimage-builder)

-  In-instance configuration management
   (os-apply-config+os-refresh-config, and/or Chef/Puppet/Salt)

-  Image management (Glance)

-  Network management (Neutron)

-  Authentication and service catalog (Keystone)

Additional Components
^^^^^^^^^^^^^^^^^^^^^

These components add value to the TripleO story, making it safer to
upgrade and evolve an environment, but are secondary to the core thing
itself.

-  Continuous integration (Zuul/Jenkins)

-  Monitoring and alerting (Ceilometer/nagios/etc)

Dependencies
------------

Each component can only be deployed once its dependencies are available.

TripleO is built on a Linux platform, so a Linux environment is required
both to create images and as the OS that will run on the machines. If
you have no Linux machines at all, you can download a live CD from a
number of vendors, which will permit you to run diskimage-builder to get
going.

Diskimage-builder
^^^^^^^^^^^^^^^^^

An internet connection is also required to download the various packages
used in preparing each image.

The machine images built *can* depend on Heat metadata, or they can just
contain configured Chef/Puppet/Salt credentials, depending on how much
of TripleO is in use. Avoiding Heat is useful when doing a incremental
adoption of TripleO (see later in this document).

Baremetal machine deployment
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Baremetal deployments are delivered via Nova. Additionally, the network
must be configured so that the baremetal host machine can receive TFTP
from any physical machine that is being booted.

Nova
^^^^

Nova depends on Keystone, Glance and Neutron. In future Cinder will be
one of the dependencies.

There are three ways the service can be deployed:

-  Via diskimage-builder built machine images, configured via a running
   Heat cluster. This is the normal TripleO deployment.

-  Via the special bootstrap node image, which is built by
   diskimage-builder and contains a full working stack - nova, glance,
   keystone and neutron, configured by statically generated Heat
   metadata. This approach is used to get TripleO up and running.

-  By hand - e.g. using devstack, or manually/chef/puppet/packages on a
   dedicated machine. This can be useful for incremental adoption of
   TripleO.

Cinder
^^^^^^

Cinder is needed for persistent storage on bare metal machines. That
aspect of TripleO is not yet available : when an instance is deleted,
the storage is deleted with it.

Neutron
^^^^^^^

Neutron depends on Keystone. The same three deployment options exist as
for Nova. The Neutron network node(s) must be the only DHCP servers on
the network.

Glance
^^^^^^

Glance depends on Keystone. The same three deployment options exist as
for Nova.

Keystone
^^^^^^^^

Keystone has no external dependencies. The same three deployment options
exist as for Nova.

Heat
^^^^

Heat depends on Nova, Cinder and Keystone. The same three deployment
options exist as for Nova.

In-instance configuration
^^^^^^^^^^^^^^^^^^^^^^^^^

The os-apply-config and os-refresh-config tools depend on Heat to
provide cluster configuration metadata. They can be used before Heat is
functional if a statically prepared metadata file is placed in the Heat
path : this is how the bootstrap node works.

os-apply-config and os-refresh-config can be used in concert with
Chef/Puppet/Salt, or not used at all, if you configure your services via
Chef/Puppet/Salt.

The reference TripleO elements do not depend on Chef/Puppet/Salt, to
avoid conflicting when organisations with an investment in
Chef/Puppet/Salt start using TripleO.

Deploying TripleO incrementally
-------------------------------

The general sequence is:

-  Examine the current state of TripleO and assess where non-automated
   solutions will be needed for your environment. E.g. at the time of
   writing VLAN support requires baking the VLAN configuration into your
   built disk images.

-  Decide how much of TripleO you will adopt. See `Example deployments (possible today)`_
   below.

-  Install diskimage-builder somewhere and use it to build the disk
   images your configuration will require.

-  Bring up the aspects of TripleO you will be using, starting with a
   boot-stack node (which you can run in a KVM VM in your datacentre),
   using that to bring up an actual machine and transfer bare metal
   services onto it, and then continuing up the stack.

Current caveats / workarounds
-----------------------------

These are all documented in README.rst and in the
`TripleO bugtracker`_.

.. _`TripleO bugtracker`: https://launchpad.net/tripleo

No API driven persistent storage
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Every 'nova boot' will reset the data on the machine it deploys to. To
do incremental image based updates they have to be done within the
runnning image. 'takeovernode' can do that, but as yet we have not
written rules to split out persistent data into another partition - so
some assembly required.

VLANs for physical nodes require customised images (rather than just metadata).
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you require VLANs you should create a diskimage-builder element to
add the vlan package and vlan configuration to /etc/network/interfaces
as a first-boot rule.

New seed image creation returns tmpfs space errors (systems with < 9GB of RAM)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Creating a new seed image takes up to 4.5GB of space inside a /tmp/imageXXXXX
directory. tmpfs can take up to 50% of RAM and systems with less than 9GB of
RAM will fail in this step. When using ``diskimage-builder`` directly, you can
prevent the space errors by:

- avoiding tmpfs with ``--no-tmpfs`` or
- specifying a minimum tmpfs size required with ``--min-tmpfs`` (which can be used
  in conjunction with setting the environment variable ``TMP_DIR`` to override the
  default temporary directory)

If you are using ``boot-seed-vm``, set the environment variable ``DIB_NO_TMPFS=1``.

Example deployments (possible today)
------------------------------------

Baremetal only
^^^^^^^^^^^^^^

In this scenario you make use of the baremetal driver to deploy
unspecialised machine images, and perform specialisation using
Chef/Puppet/Salt - whatever configuration management toolchain you
prefer. The baremetal host system is installed manually, but a TripleO
image is used to deploy it.

It scales within any one broadcast domain to the capacity of the single
baremetal host.

Prerequisites
~~~~~~~~~~~~~

-  A boot-stack image setup to run in KVM.

-  A vanilla image.

-  A userdata script to configure new instances to run however you want.

-  A machine installed with your OS of choice in your datacentre.

-  Physical machines configured to netboot in preference to local boot.

-  A list of the machines + their IPMI details + mac addresses.

-  A network range larger than the maximum number of concurrent deploy
   operations to run in parallel.

-  A network to run the instances on large enough to supply one ip per
   instance.

HOWTO
~~~~~

-  Build the images you need (add any local elements you need to the
   commands)

-  Copy ``tripleo-image-elements/elements/seed-stack-config/config.json`` to
   ``tripleo-image-elements/elements/seed-stack-config/local.json`` and
   change the virtual power manager to 'nova...impi.IPMI'.
   https://bugs.launchpad.net/tripleo/+bug/1178547::

    disk-image-create -o bootstrap vm boot-stack local-config ubuntu
    disk-image-create -o ubuntu ubuntu

   The ``local-config`` element will copy your ssh key and your HTTP proxy
   settings in the disk image during the creation process.

   The ``stackuser`` element will create a user ``stack`` with the password ``stack``.

   ``disk-image-create`` will create a image with a very small disk size
   that at to be resized for example by cloud-init. You can use
   ``DIB_IMAGE_SIZE`` to increase this initial size, in GB.

-  Setup a VM using bootstrap.qcow2 on your existing machine, with eth1
   bridged into your datacentre LAN.

-  Run up that VM, which will create a self contained nova baremetal
   install.

-  Reconfigure the networking within the VM to match your physical
   network. https://bugs.launchpad.net/tripleo/+bug/1178397
   https://bugs.launchpad.net/tripleo/+bug/1178099

-  If you had exotic hardware needs, replace the deploy images that the
   bootstack creates. https://bugs.launchpad.net/tripleo/+bug/1178094

-  Enroll your vanilla image into the glance of that install. Be sure to
   use ``tripleo-incubator/scripts/load-image`` as that will extract the
   kernel and ramdisk and register them appropriately with glance.

-  Enroll your other datacentre machines into that nova baremetal
   install. A script that takes your machine inventory and prints out
   something like::

    nova baremetal-node-create --pm_user XXX --pm_address YYY --pm_password ZZZ COMPUTEHOST 24 98304 2048 MAC

   can be a great help - and can be run from outside the environment.

-  Setup admin users with SSH keypairs etc. e.g.::

    nova keypair-add --pub-key .ssh/authorized_keys default

-  Boot them using the ubuntu.qcow2 image, with appropriate user data to
   connect to your Chef/Puppet/Salt environments.

Baremetal with Heat
^^^^^^^^^^^^^^^^^^^

In this scenario you use the baremetal driver to deploy specialised
machine images which are orchestrated by Heat.

Prerequisites.
~~~~~~~~~~~~~~

-  A boot-stack image setup to run in KVM.

-  A vanilla image with cfn-tools installed.

-  A seed machine installed with your OS of choice in your datacentre.

HOWTO
~~~~~

-  Build the images you need (add any local elements you need to the
   commands)::

    disk-image-create -o bootstrap vm boot-stack ubuntu heat-api
    disk-image-create -o ubuntu ubuntu cfn-tools

-  Setup a VM using bootstrap.qcow2 on your existing machine, with eth1
   bridged into your datacentre LAN.

-  Run up that VM, which will create a self contained nova baremetal
   install.

-  Enroll your vanilla image into the glance of that install.

-  Enroll your other datacentre machines into that nova baremetal
   install.

-  Setup admin users with SSH keypairs etc.

-  Create a Heat stack with your application topology. Be sure to use
   the image id of your cfn-tools customised image.

GRE Neutron OpenStack managed by Heat
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

In this scenario we build on Baremetal with Heat to deploy a full
OpenStack orchestrated by Heat, with specialised disk images for
different OpenStack node roles.

Prerequisites.
~~~~~~~~~~~~~~

- A boot-stack image setup to run in KVM.

- A vanilla image with cfn-tools installed.

- A seed machine installed with your OS of choice in your datacentre.

- At least 4 machines in your datacentre, one of which manually installed with
  a recent Linux (libvirt 1.0+ or newer required).

- L2 network with private address range

- L3 accessible management network (via the L2 default router)

- VLAN with public IP ranges on it

Needed data
~~~~~~~~~~~

- a JSON file describing your baremetal machines in a format described
  in :ref:`devtest-environment-configuration` (see: nodes), making sure to
  include all MAC addresses for all network interface cards as well as the
  IPMI (address, user, password) details for them.

- 2 spare contiguous ip addresses on your L2 network for seed deployment.

- 1 spare ip address for your seed VM, and one spare for talking to it on it's
  bridge (seedip, seediplink)

- 3 spare ip addresses for your undercloud tenant network + neutron services.

- Public IP address to be your undercloud endpoint

- Public IP address to be your overcloud endpoint

Install Seed
~~~~~~~~~~~~

Follow the 'devtest' guide but edit the seed config.json to:

- change the dnsmasq range to the seed deployment range

- change the heat endpoint details to refer to your seed ip address

- change the ctlplane ip and cidr to match your seed ip address

- change the power manager line nova.virt.baremetal.ipmi.IPMI and
  remove the virtual subsection.

- setup proxy arp (this and the related bits are used to avoid messing about
  with the public NIC and bridging: you may choose to use that approach
  instead...)::

    sudo sysctl  net/ipv4/conf/all/proxy_arp=1
    arp -s <seedip> -i <external_interface> -D <external_interface> pub
    ip addr add <seediplink>/32 dev brbm
    ip route add <seedip>/32 dev brbm src <seediplink>

- setup ec2 metadata support::

    iptables -t nat -A PREROUTING -d 169.254.169.254/32 -i <external_interface> -p tcp -m tcp --dport 80 -j DNAT --to-destination <seedip>:8775

- setup DHCP relay::

    sudo apt-get install dhcp-helper

  and configure it with ``-s <seedip>``
  Note that isc-dhcp-relay fails to forward responses correctly, so dhcp-helper is preferred
  ( https://bugs.launchpad.net/ubuntu/+bug/1233953 ).

  Also note that dnsmasq may have to be stopped as they both listen to ``*:dhcps``
  ( https://bugs.launchpad.net/ubuntu/+bug/1233954 ).

  Disable the ``filter-bootps`` cronjob (``./etc/cron.d/filter-bootp``) inside the seed vm and reset the table::

    sudo iptables  -F FILTERBOOTPS

  edit /etc/init/novabm-dnsmasq.conf::

    exec dnsmasq --conf-file= \
    --keep-in-foreground \
    --port=0 \
    --dhcp-boot=pxelinux.0,<seedip>,<seedip> \
    --bind-interfaces \
    --pid-file=/var/run/dnsmasq.pid \
    --interface=br-ctlplane \
    --dhcp-range=<seed_deploy_start>,<seed_deploy_end>,<network_cidr>

- When you setup the seed, use <seedip> instead of 192.0.2.1, and you may need to edit seedrc.

- For setup-neutron:
  setup-neutron <start of seed deployment> <end of seed deployment> <cidr of network> <seedip> <metadata server> ctlplane

- Validate networking:

  - From outside the seed host you should be able to ping <seedip>
  - From the seed VM you should be able to ping <all ipmi addresses>
  - From outside the seed host you should be able to get a response from the dnsmasq running on <seedip>

- Create your deployment ramdisk with baremetal in mind::

    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST -a \
    $NODE_ARCH -o $TRIPLEO_ROOT/undercloud  boot-stack nova-baremetal \
    os-collect-config stackuser $DHCP_DRIVER -p linux-image-generic mellanox \
    serial-console --offline

- If your hardware has something other than eth0 plugged into the network,
  fix your file injection template -
  ``/opt/stack/nova/nova/virt/baremetal/net-static.ubuntu.template`` inside the
  seed vm, replacing the enumerated interface values with the right interface
  to use (e.g. auto eth2... iface eth2 inet static..)

Deploy Undercloud
~~~~~~~~~~~~~~~~~

Use ``heat stack-create`` per the devtest documentation to boot your undercloud.
But use the ``undercloud-bm.yaml`` file rather ``than undercloud-vm.yaml``.

Once it's booted:

- ``modprobe 8021q``

- edit ``/etc/network/interfaces`` and define your vlan

- delete the default route on your internal network

- add a targeted route to your management l3 range via the internal network router

- add a targeted route to ``169.254.169.254`` via <seedip>

- ``ifup`` the vlan interface

- fix your resolv.conf

- configure the undercloud per devtest.

- upgrade your quotas::

    nova quota-update --cores node_size*machine_count --instances machine_count --ram node_size*machine_count admin-tenant-id


Deploy Overcloud
~~~~~~~~~~~~~~~~

Follow devtest again, but modify the images you build per the undercloud notes, and for machines you put public services on, follow the undercloud notes to fix them up.

Example deployments (future)
----------------------------

WARNING: Here be draft notes.

VM seed + bare metal under cloud
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

-  need to be aware nova metadata wont be available after booting as the
   default rule assumes this host never initiates requests
   ( https://bugs.launchpad.net/tripleo/+bug/1178487 ).
