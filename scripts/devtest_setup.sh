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

## Devtest test environment configuration
## --------------------------------------

## Devtest uses a JSON file to describe the test environment that OpenStack will
## run within. The JSON file path is given by $TE_DATAFILE. The JSON file contains
## the following keys:

## #. host-ip: The IP address of the host which will run the seed VM using virsh.

## #. seed-ip: The IP address of the seed VM (if known). If not known, it is
##    looked up locally in the ARP table.

## #. ssh-key: The private part of an SSH key to be used when performing virsh
##    commands on $host-ip.

## #. ssh-user: The SSH username to use when performing virsh commands on
##    $host-ip.

## #. node-macs: A space separated string containing the MAC addresses of eth0 of
##    each of the emulated bare metal VMs.

## XXX: We're currently migrating to that structure - some code still uses
##      environment variables instead.

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

if [ "$NODE_DIST" == 'unsupported' ]; then
    echo 'Unsupported OS distro.'
    exit 1
fi

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

## #. Configure a network for your test environment.
##    This configures an openvswitch bridge and teaches libvirt about it.
##    ::
setup-network

## #. Configure a seed VM. This VM has a disk image manually configured by
##    later scripts, and hosts the statically configured seed which is used
##    to bootstrap a full dynamically configured baremetal cloud.
##    ::
setup-seed-vm -a $NODE_ARCH

## #. Create baremetal nodes for the test cluster. The final parameter to
##    create-nodes is the number of VMs to create.

export SEED_MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 1)
export UNDERCLOUD_MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 2)

### --end
