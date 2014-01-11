#!/bin/bash
#
# Idempotent one-time setup for devtest.
# This can be run for CI purposes, by passing --trash-my-machine to it.
# Without that parameter, the script will error.
set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Setup the TripleO devtest environment."
    echo
    echo "Options:"
    echo "    --trash-my-machine -- make nontrivial destructive changes to the machine."
    echo "                          For details read the source."
    echo "    -c                 -- re-use existing source/images if they exist."
    echo
    exit $1
}

CONTINUE=0
USE_CACHE=0

TEMP=`getopt -o h,c -l trash-my-machine -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --trash-my-machine) CONTINUE=1; shift 1;;
        -c) USE_CACHE=1; shift 1;;
        -h) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

if [ "0" = "$CONTINUE" ]; then
    echo "Not running - this script is destructive and requires --trash-my-machine to run." >&2
    exit 1
fi

### --include
## devtest_setup
## =============

## Configuration
## -------------

## The seed instance expects to run with its eth0 connected to the outside world,
## via whatever IP range you choose to setup. You can run NAT, or not, as you
## choose. This is how we connect to it to run scripts etc - though you can
## equally log in on its console if you like.

## We use flat networking with all machines on one broadcast domain for dev-test.

## The eth1 of your seed instance should be connected to your bare metal cloud
## LAN. The seed VM uses the rfc5735 TEST-NET-1 range - 192.0.2.0/24 for
## bringing up nodes, and does its own DHCP etc, so do not connect it to a network
## shared with other DHCP servers or the like. The instructions in this document
## create a bridge device ('brbm') on your machine to emulate this with virtual
## machine 'bare metal' nodes.


## NOTE: We recommend using an apt/HTTP proxy and setting the http_proxy
##       environment variable accordingly in order to speed up the image build
##       times.  See footnote [#f3]_ to set up Squid proxy.

## NOTE: Likewise, setup a pypi mirror and use the pypi element, or use the
##       pip-cache element. (See diskimage-builder documentation for both of
##       these). Add the relevant element name to the DIB_COMMON_ELEMENTS
##       variable.

## NOTE: The CPU architecture specified in several places must be consistent.
##       The examples here use 32-bit arch for the reduced memory footprint.  If
##       you are running on real hardware, or want to test with 64-bit arch,
##       replace i386 => amd64 in all the commands below. You
##       will of course need amd64 capable hardware to do this.

## Detailed instructions
## ---------------------

## **(Note: all of the following commands should be run on your host machine, not inside the seed VM)**

## #. Before you start, check to see that your machine supports hardware
##    virtualization, otherwise performance of the test environment will be poor.
##    We are currently bringing up an LXC based alternative testing story, which
##    will mitigate this, though the deployed instances will still be full virtual
##    machines and so performance will be significantly less there without
##    hardware virtualization.

## #. As you step through the instructions several environment
##    variables are set in your shell.  These variables will be lost if
##    you exit out of your shell.  After setting variables, use
##    scripts/write-tripleorc to write out the variables to a file that
##    can be sourced later to restore the environment.

## #. Also check ssh server is running on the host machine and port 22 is open for
##    connections from virbr0 -  VirtPowerManager will boot VMs by sshing into the
##    host machine and issuing libvirt/virsh commands. The user these instructions
##    use is your own, but you can also setup a dedicated user if you choose.

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
mkdir -p $TRIPLEO_ROOT
cd $TRIPLEO_ROOT

## #. git clone this repository to your local machine.
##    ::
### --end
if [ "$USE_CACHE" == "0" ] ; then
  if [ ! -d $TRIPLEO_ROOT/tripleo-incubator ]; then
### --include
    git clone https://git.openstack.org/openstack/tripleo-incubator
### --end
  else
    cd $TRIPLEO_ROOT/tripleo-incubator ; git pull
  fi
fi
### --include

## 
## #. Nova tools get installed in $TRIPLEO_ROOT/tripleo-incubator/scripts
##    - you need to add that to the PATH.
##    ::

export PATH=$TRIPLEO_ROOT/tripleo-incubator/scripts:$PATH

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
### --end

source $TRIPLEO_ROOT/tripleo-incubator/scripts/set-os-type
if [ "$TRIPLEO_OS_DISTRO" == 'unsupported' ]; then
    echo 'Unsupported OS distro.'
    exit 1
fi
export NODE_DIST=${NODE_DIST:-"$TRIPLEO_OS_DISTRO"}

### --include

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

## #. Ensure dependencies are installed and required virsh configuration is
##    performed:
##    ::
if [ "$USE_CACHE" == "0" ] ; then #nodocs
    install-dependencies
fi #nodocs

## #. Run cleanup-env to ensure VM's and storage pools from previous devtest
##    runs are removed.
##    ::
##         cleanup-env
### --end
if [ "${TRIPLEO_CLEANUP:-1}" = "1"  ]; then
    echo "Cleaning up vm's/storage from previous devtest runs"
    cleanup-env
fi
### --include

## #. Clone/update the other needed tools which are not available as packages.
##    ::
if [ "$USE_CACHE" == "0" ] ; then #nodocs
    pull-tools
fi #nodocs

## #. You need to make the tripleo image elements accessible to diskimage-builder:
##    ::
export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-image-elements/elements

## #. Configure a network for your test environment.
##    This configures an openvswitch bridge and teaches libvirt about it.
##    ::
setup-network

## #. Configure a seed VM. This VM has a disk image manually configured by
##    later scripts, and hosts the statically configured seed which is used
##    to bootstrap a full dynamically configured baremetal cloud.
##    ::
setup-seed-vm -a $NODE_ARCH

### --end
