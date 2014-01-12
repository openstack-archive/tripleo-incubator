#!/bin/bash
#
# Variable definition for devtest.

### --include
## #. The devtest scripts require access to the libvirt system URI.
##    If running against a different libvirt URI you may encounter errors.
##    Export LIBVIRT_DEFAULT_URI to prevent devtest using qemu:///system
##    Check that the default libvirt connection for your user is qemu:///system.
##    If it is not, set an environment variable to configure the connection.
##    This configuration is necessary for consistency, as later steps assume
##    qemu:///system is being used.
##    ::

export LIBVIRT_DEFAULT_URI=${LIBVIRT_DEFAULT_URI:-"qemu:///system"}

## #. The vm's created by devtest will use e1000 network device emulation by
##    default.  This can be overriden to use a different network driver for
##    interfaces instead, such as virtio.  virtio provides faster network
##    performance than e1000, but may prove to be less stable.
##    ::

export LIBVIRT_NIC_DRIVER=${LIBVIRT_NIC_DRIVER:-"e1000"}

## #. Choose a base location to put all of the source code.
##    ::
##         # exports are ephemeral - new shell sessions, or reboots, and you need
##         # to redo them, or use $TRIPLEO_ROOT/tripleo-incubator/scripts/write-tripleorc
##         # and then source the generated tripleorc file.
##         export TRIPLEO_ROOT=~/tripleo
export TRIPLEO_ROOT=${TRIPLEO_ROOT:-~/.cache/tripleo} #nodocs

## 
## #. Nova tools will get installed in $TRIPLEO_ROOT/tripleo-incubator/scripts
##    - you need to add that to the PATH.
##    ::

export PATH=$TRIPLEO_ROOT/tripleo-incubator/scripts:$PATH

## #. Set the default bare metal power manager. By default devtest uses
##    nova.virt.baremetal.virtual_power_driver.VirtualPowerManager to
##    support a fully virtualized TripleO test environment. You may
##    optionally customize this setting if you are using real baremetal
##    hardware with the devtest scripts. This setting controls the
##    power manager used in both the seed VM and undercloud.
##    ::
export POWER_MANAGER=${POWER_MANAGER:-'nova.virt.baremetal.virtual_power_driver.VirtualPowerManager'}

## #. Set a list of image elements that should be included in all image builds.
##    Note that stackuser is only for debugging support - it is not suitable for
##    a production network. This is also the place to include elements such as
##    pip-cache or pypi-openstack if you intend to use them.
##    ::
export DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-"stackuser"}

## #. Set HW resources for VMs used as 'baremetal' nodes. NODE_CPU is cpu count,
##    NODE_MEM is memory (MB), NODE_DISK is disk size (GB), NODE_ARCH is
##    architecture (i386, amd64). NODE_ARCH is used also for the seed VM.
##    A note on memory sizing: TripleO images in raw form are currently
##    ~2.7Gb, which means that a tight node will end up with a thrashing page
##    cache during glance -> local + local -> raw operations. This significantly
##    impairs performance. Of the four minimum VMs for TripleO simulation, two
##    are nova baremetal nodes (seed an undercloud) and these need to be 2G or
##    larger. The hypervisor host in the overcloud also needs to be a decent size
##    or it cannot host more than one VM.
##
##    32bit VMs::
##
##         export NODE_CPU=1 NODE_MEM=2048 NODE_DISK=20 NODE_ARCH=i386
export NODE_CPU=${NODE_CPU:-1} NODE_MEM=${NODE_MEM:-2048} NODE_DISK=${NODE_DISK:-20} NODE_ARCH=${NODE_ARCH:-i386} #nodocs

##    For 64bit it is better to create VMs with more memory and storage because of
##    increased memory footprint::
##
##         export NODE_CPU=1 NODE_MEM=2048 NODE_DISK=20 NODE_ARCH=amd64
##

## #. Set distribution used for VMs (fedora, ubuntu).
##    ::
##
##         export NODE_DIST=ubuntu
##
##    for Fedora set SELinux permissive mode.
##    ::
##
##         export NODE_DIST="fedora selinux-permissive"
source $(dirname $0)/set-os-type
export NODE_DIST=${NODE_DIST:-"$TRIPLEO_OS_DISTRO"}

## #. You need to make the tripleo image elements accessible to diskimage-builder:
##    ::
export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-image-elements/elements

## #. Set the datafile to use to describe the 'hardware' in the devtest
##    environment. If this file already exists, you should skip running
##    devtest_testenv.sh as it writes to the file::

export TE_DATAFILE=${TE_DATAFILE:-"$TRIPLEO_ROOT/testenv.json"}

### --end
