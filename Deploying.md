Deploying TripleO
=================

# Components

## Essential Components

Essential components make up the self-deploying infrastructure that is the
heart of TripleO.

* Baremetal machine deployment (Nova Baremetal, soon to be 'Ironic')

* Baremetal volume management (Cinder - not available yet)

* Cluster orchestration (Heat)

* Machine image creation (Diskimage-builder)

* In-instance configuration management (os-config-applier+os-refresh-config,
  and/or Chef/Puppet/Salt)

* Image management (Glance)

* Network management (Quantum)

* Authentication and service catalog (Keystone)

## Additional Components

These components add value to the TripleO story, making it safer to upgrade and
evolve an environment, but are secondary to the core thing itself.

* Continuous integration (Zuul/Jenkins)

* Monitoring and alerting (Ceilometer/nagios/etc)

# Dependencies

Each component can only be deployed once its dependencies are available.

TripleO is built on a Linux platform, so a Linux environment is required both
to create images and as the OS that will run on the machines. If you have no
Linux machines at all, you can download a live CD from a number of vendors,
which will permit you to run diskimage-builder to get going.

## Diskimage-builder

An internet connection is also required to download the various packages used
in preparing each image.

The machine images built *can* depend on Heat metadata, or they can just
contain configured Chef/Puppet/Salt credentials, depending on how much of
TripleO is in use. Avoiding Heat is useful when doing a incremental adoption
of TripleO (see later in this document).

## Baremetal machine deployment

Baremetal deployments are delivered via Nova. Additionally, the network must
be configured so that the baremetal host machine can receive TFTP from any
physical machine that is being booted. 

## Nova

Nova depends on Keystone, Glance and Quantum. In future Cinder
will be one of the dependencies.

There are three ways the service can be deployed:

* Via diskimage-builder built machine images, configured via a running Heat
  cluster. This is the normal TripleO deployment.

* Via the special bootstrap node image, which is built by diskimage-builder and
  contains a full working stack - nova, glance, keystone and quantum,
  configured by statically generated Heat metadata. This approach is used to 
  get TripleO up and running.

* By hand - e.g. using devstack, or manually/chef/puppet/packages on a
  dedicated machine. This can be useful for incremental adoption of TripleO.

## Cinder

Cinder is needed for persistent storage on bare metal machines. That aspect of
TripleO is not yet available : when an instance is deleted, the storage is
deleted with it.

## Quantum

Quantum depends on Keystone. The same three deployment options exist as for
Nova. The Quantum network node(s) must be the only DHCP servers on the network.

## Glance

Glance depends on Keystone. The same three deployment options exist as for
Nova.

## Keystone

Keystone has no external dependencies. The same three deployment options exist
as for Nova.

## Heat

Heat depends on Nova, Cinder and Keystone. The same three deployment options
exist as for Nova.

## In-instance configuration

The os-config-applier and os-refresh-config tools depend on Heat to provide
cluster configuration metadata. They can be used before Heat is functional
if a statically prepared metadata file is placed in the Heat path : this is
how the bootstrap node works.

os-config-applier and os-refresh-config can be used in concert with 
Chef/Puppet/Salt, or not used at all, if you configure your services via
Chef/Puppet/Salt.

The reference TripleO elements do not depend on Chef/Puppet/Salt, to avoid
conflicting when organisations with an investment in Chef/Puppet/Salt start
using TripleO.

# Deploying TripleO incrementally

The general sequence is:

* Examine the current state of TripleO and assess where non-automated solutions
  will be needed for your environment. E.g. at the time of writing VLAN support
  requires baking the VLAN configuration into your built disk images.

* Decide how much of TripleO you will adopt. See 'Example deployments' below.

* Install diskimage-builder somewhere and use it to build the disk images your
  configuration will require.

* Bring up the aspects of TripleO you will be using, starting with a boot-stack
  node (which you can run in a KVM VM in your datacentre), using that to bring
  up an actual machine and transfer bare metal services onto it, and then
  continuing up the stack.

# Current caveats / workarounds

These are all documented in README.md and in the [TripleO bugtracker]
(https://launchpad.net/tripleo).

## No API driven persistent storage

Every 'nova boot' will reset the data on the machine it deploys to. To do
incremental image based updates they have to be done within the runnning image.
'takeovernode' can do that, but as yet we have not written rules to split out
persistent data into another partition - so some assembly required.

## VLANs for physical nodes require customised images (rather than just metadata).

If you require VLANs you should create a diskimage-builder element to add the vlan
package and vlan configuration to /etc/network/interfaces as a first-boot rule.

# Example deployments (possible today)

## Baremetal only

In this scenario you make use of the baremetal driver to deploy unspecialised
machine images, and perform specialisation using Chef/Puppet/Salt -
whatever configuration management toolchain you prefer. The baremetal host
system is installed manually, but a TripleO image is used to deploy it.

It scales within any one broadcast domain to the capacity of the single
baremetal host.

### Prerequisites

* A boot-stack image setup to run in KVM.

* A vanilla image.

* A userdata script to configure new instances to run however you want.

* A machine installed with your OS of choice in your datacentre.

* Physical machines configured to netboot in preference to local boot.

* A list of the machines + their IPMI details + mac addresses.

### HOWTO

* Build the images you need (add any local elements you need to the commands)

    disk-image-create -o bootstrap vm boot-stack ubuntu
    disk-image-create -o ubuntu ubuntu

* Setup a VM using bootstrap.qcow2 on your existing machine, with eth1 bridged
  into your datacentre LAN.

* Run up that VM, which will create a self contained nova baremetal install.

* Reconfigure the networking within the VM to match your physical network.
  https://bugs.launchpad.net/tripleo/+bug/1178397 
  https://bugs.launchpad.net/tripleo/+bug/1178099

* If you had exotic hardware needs, replace the deploy images that the
  bootstack creates.
  https://bugs.launchpad.net/tripleo/+bug/1178094

* Enroll your vanilla image into the glance of that install.

* Enroll your other datacentre machines into that nova baremetal install.

* Setup admin users with SSH keypairs etc.

* Boot them using the ubuntu.qcow2 image, with appropriate user data to 
  connect to your Chef/Puppet/Salt environments.

## Baremetal with Heat

In this scenario you use the baremetal driver to deploy specialised machine
images which are orchestrated by Heat.

### Prerequisites.

* A boot-stack image setup to run in KVM.

* A vanilla image with cfn-tools installed.

* A seed machine installed with your OS of choice in your datacentre.

### HOWTO

* Build the images you need (add any local elements you need to the commands)

    disk-image-create -o bootstrap vm boot-stack ubuntu heat-api
    disk-image-create -o ubuntu ubuntu cfn-tools

* Setup a VM using bootstrap.qcow2 on your existing machine, with eth1 bridged
  into your datacentre LAN.

* Run up that VM, which will create a self contained nova baremetal install.

* Enroll your vanilla image into the glance of that install.

* Enroll your other datacentre machines into that nova baremetal install.

* Setup admin users with SSH keypairs etc.

* Create a Heat stack with your application topology. Be sure to use the image
  id of your cfn-tools customised image.

## Flat-networking OpenStack managed by Heat

In this scenario we build on Baremetal with Heat to deploy a full OpenStack
orchestrated by Heat, with specialised disk images for different OpenStack node
roles.

### Prerequisites.

* A boot-stack image setup to run in KVM.

* A vanilla image with cfn-tools installed.

* A seed machine installed with your OS of choice in your datacentre.

### HOWTO

* Build the images you need (add any local elements you need to the commands)

    disk-image-create -o bootstrap vm boot-stack ubuntu heat-api stackuser
    disk-image-create -o ubuntu ubuntu cfn-tools

* Setup a VM using bootstrap.qcow2 on your existing machine, with eth1 bridged
  into your datacentre LAN.

* Run up that VM, which will create a self contained nova baremetal install.

* Enroll your vanilla image into the glance of that install.

* Enroll your other datacentre machines into that nova baremetal install.

* Setup admin users with SSH keypairs etc.

* Create a Heat stack with your application topology. Be sure to use the image
  id of your cfn-tools customised image.


# Example deployments (future)

WARNING: Here be draft notes.

## VM seed + bare metal under cloud
* need to be aware nova metadata wont be available after booting as the default
  rule assumes this host never initiates requests.
  https://bugs.launchpad.net/tripleo/+bug/1178487

