#!/bin/bash
#
# Test environment creation for devtest.
# This creates the bridge and VM's

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options] {JSON-filename}"
    echo
    echo "Setup a TripleO devtest environment."
    echo
    echo "Options:"
    echo "    -b                     -- Name of an already existing OVS bridge to use for "
    echo "                              the public interface of the seed."
    echo "    -h                     -- This help."
    echo "    -n                     -- Test environment number to add the seed to."
    echo "    --bridge-to-interface [interface]"
    echo "                           -- When running with physical undercloud and overcloud"
    echo "                              hosts, the seed needs to be able to communicate with"
    echo "                              the physical network of the host somehow, and this"
    echo "                              option is intended to provide for defining the host"
    echo "                              interface with which to do that."
    echo "    --nodes NODEFILE       -- You are supplying your own list of hardware."
    echo "                              The schema for nodes can be found in the devtest_setup"
    echo "                              documentation."
    echo
    echo "JSON-filename -- the path to write the environment description to."
    echo
    echo "Note: This adds a unique key to your authorised_keys file to permit "
    echo "virtual-power-managment calls to be made."
    echo
    exit $1
}

NODES_PATH=
NUM=
OVSBRIDGE=
BRIDGE_INTERFACE=

TEMP=$(getopt -o h,n:,b: -l bridge-to-interface:,nodes: -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --bridge-to-interface) BRIDGE_INTERFACE="$2"; shift 2;;
        --nodes) NODES_PATH="$2"; shift 2;;
        -b) OVSBRIDGE="$2" ; shift 2 ;;
        -h) show_options 0;;
        -n) NUM="$2" ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

### --include
## devtest_testenv
## ===============

#XXX: When updating, sync with the call in devtest.sh #nodocs

## .. note::
##
##   This script is usually called from ``devtest.sh`` as
##   ``devtest_testenv.sh $TE_DATAFILE``
##
##   When this script is called for setting up a real hardware the above changes
##   so that the seed can communicat on the physical network.
##   ``devtest_testenv.sh $TE_DATAFILE --bridge-to-interface [interface]``
## ::

JSONFILE=${1:-''}

### --end
EXTRA_ARGS=${2:-''}

if [ -z "$JSONFILE" -o -n "$EXTRA_ARGS" ]; then
    show_options 1
fi

### --include

## #. Set HW resources for VMs used as 'baremetal' nodes. NODE_CPU is cpu count,
##    NODE_MEM is memory (MB), NODE_DISK is disk size (GB), NODE_ARCH is
##    architecture (i386, amd64). NODE_ARCH is used also for the seed VM.
##    A note on memory sizing: TripleO images in raw form are currently
##    ~2.7Gb, which means that a tight node will end up with a thrashing page
##    cache during glance -> local + local -> raw operations. This significantly
##    impairs performance. Of the four minimum VMs for TripleO simulation, two
##    are nova baremetal nodes (seed and undercloud) and these need to be 2G or
##    larger. The hypervisor host in the overcloud also needs to be a decent size
##    or it cannot host more than one VM.
##
##    32bit VMs
##    ::
##
##         NODE_CPU=1 NODE_MEM=2048 NODE_DISK=30 NODE_ARCH=i386
##
NODE_CPU=${NODE_CPU:-1} NODE_MEM=${NODE_MEM:-2048} NODE_DISK=${NODE_DISK:-30} NODE_ARCH=${NODE_ARCH:-i386} #nodocs

##    For 64bit it is better to create VMs with more memory and storage because of
##    increased memory footprint::
##
##         NODE_CPU=1 NODE_MEM=2048 NODE_DISK=30 NODE_ARCH=amd64
##

## #. Configure a network for your test environment.
##    This configures an openvswitch bridge and teaches libvirt about it.
##    ::

setup-network "$NUM" "$BRIDGE_INTERFACE"

## #. Configure a seed VM. This VM has a disk image manually configured by
##    later scripts, and hosts the statically configured seed which is used
##    to bootstrap a full dynamically configured baremetal cloud.
##    ::

SEED_ARGS="-a $NODE_ARCH"
if [ -n "$NUM" -a -n "$OVSBRIDGE" ]; then
    SEED_ARGS="$SEED_ARGS -o seed_${NUM} -b brbm${NUM} -p $OVSBRIDGE"
fi
setup-seed-vm $SEED_ARGS

## #. What user will be used to ssh to run virt commands to control our
##    emulated baremetal machines.
##    ::

SSH_USER=$(whoami)

## #. What IP address to ssh to for virsh operations.
##    ::

HOSTIP=${HOSTIP:-192.168.122.1}

## #. If a static SEEDIP is in use, define it here. If not defined it will be
##    looked up in the ARP table by the seed MAC address during seed deployment.
##    ::

SEEDIP=${SEEDIP:-''}

## #. Ensure we can ssh into the host machine to turn VMs on and off.
##    The private key we create will be embedded in the seed VM, and delivered
##    dynamically by heat to the undercloud VM.
##    ::

# generate ssh authentication keys if they don't exist
if [ ! -f ~/.ssh/id_rsa_virt_power ]; then
    ssh-keygen -t rsa -N "" -C virtual-power-key -f ~/.ssh/id_rsa_virt_power
fi

# make the local id_rsa_virt_power.pub be in ``.ssh/authorized_keys`` before
# that is copied into images via ``local-config``
if ! grep -qF "$(cat ~/.ssh/id_rsa_virt_power.pub)" ~/.ssh/authorized_keys; then
    cat ~/.ssh/id_rsa_virt_power.pub >> ~/.ssh/authorized_keys
    chmod 0600 ~/.ssh/authorized_keys
fi

## #. Wrap this all up into JSON.
##    ::

jq "." <<EOF > $JSONFILE
{
    "arch":"$NODE_ARCH",
    "host-ip":"$HOSTIP",
    "power_manager":"$POWER_MANAGER",
    "seed-ip":"$SEEDIP",
    "ssh-key":"$(cat ~/.ssh/id_rsa_virt_power)",
    "ssh-user":"$SSH_USER"
}
EOF

## #. If you have an existing set of nodes to use, use them.
##    ::

if [ -n "$NODES_PATH" ]; then #nodocs
JSON=$(jq -s '.[0].nodes=.[1] | .[0]' $JSONFILE $NODES_PATH)
echo "${JSON}" > $JSONFILE
else #nodocs
## #. Create baremetal nodes for the test cluster. The final parameter to
##    create-nodes is the number of VMs to create. To change this in future
##    you can run clean-env and then recreate with more nodes.
##    ::

NODE_CNT=$(( $OVERCLOUD_COMPUTESCALE + 2 ))
create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH $NODE_CNT $SSH_USER $HOSTIP $JSONFILE
### --end
fi
