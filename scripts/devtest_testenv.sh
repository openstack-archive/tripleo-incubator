#!/bin/bash
#
# Test environment creation for devtest.
# This creates the bridge and VM's

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options {
    echo "Usage: $SCRIPT_NAME [options] {JSON-filename}"
    echo
    echo "Setup a TripleO devtest environment."
    echo
    echo "Options:"
    echo "    -b                     -- Name of an already existing OVS bridge to use for "
    echo "                              the public interface of the seed."
    echo "    -h                     -- This help."
    echo "    -n                     -- Test environment number to add the seed to."
    echo "    -s                     -- SSH private key path to inject into the JSON."
    echo "                              If not supplied, defaults to ~/.ssh/id_rsa_virt_power"
    echo "    --nodes NODEFILE       -- You are supplying your own list of hardware."
    echo "                              A sample nodes definition can be found in the os-cloud-config"
    echo "                              usage documentation."
    echo
    echo "    --bm-networks NETFILE  -- You are supplying your own network layout."
    echo "                              The schema for baremetal-network can be found in"
    echo "                              the devtest_setup documentation."
    echo
    echo "    --keep-vms             -- Prevent cleanup of virsh instances for"
    echo "                              undercloud and overcloud"
    echo "JSON-filename -- the path to write the environment description to."
    echo
    echo "Note: This adds a unique key to your authorised_keys file to permit "
    echo "virtual-power-managment calls to be made."
    echo
    exit $1
}

NODES_PATH=
NETS_PATH=
NUM=
OVSBRIDGE=
SSH_KEY=~/.ssh/id_rsa_virt_power
KEEP_VMS=

TEMP=$(getopt -o h,n:,b:,s: -l nodes:,bm-networks:,keep-vms -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --nodes) NODES_PATH="$2"; shift 2;;
        --bm-networks) NETS_PATH="$2"; shift 2;;
        --keep-vms) KEEP_VMS=1; shift;;
        -b) OVSBRIDGE="$2" ; shift 2 ;;
        -h) show_options 0;;
        -n) NUM="$2" ; shift 2 ;;
        -s) SSH_KEY="$2" ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

### --include
## devtest_testenv
## ===============

#XXX: When updating, sync with the call in devtest.sh #nodocs

## .. note::

##   This script is usually called from ``devtest.sh`` as
##   ``devtest_testenv.sh $TE_DATAFILE`` so we should declare
##   a JSONFILE variable (which equals to the first positional
##   argument) explicitly.
##   ::

##      JSONFILE=${JSONFILE:-$TE_DATAFILE}

### --end
JSONFILE=${1:-''}
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
##    are nova baremetal nodes (seed and undercloud) and these need to be 3G or
##    larger. The hypervisor host in the overcloud also needs to be a decent size
##    or it cannot host more than one VM. The NODE_DISK is set to support
##    building 5 overcloud nodes when not using Ironic. If you are building a
##    larger overcloud than this without using Ironic you may need to increase
##    NODE_DISK.

##    NODE_CNT specifies how many VMs to define using virsh. NODE_CNT
##    defaults to 15, or 0 if NODES_PATH is provided.

### --end
##    This number is intentionally higher than required as the
##    definitions are cheap (until the VM is activated the only cost
##    is a small amount of disk space) but growing this number in our
##    CI environment is expensive.
### --include

##    32bit VMs
##    ::

##         NODE_CPU=1 NODE_MEM=3072 NODE_DISK=40 NODE_ARCH=i386


### --end

if [ -n "$NODES_PATH" ]; then
    NODE_CNT=${NODE_CNT:-0}
else
    NODE_CNT=${NODE_CNT:-15}
fi

NODE_CPU=${NODE_CPU:-1} NODE_MEM=${NODE_MEM:-3072} NODE_DISK=${NODE_DISK:-40} NODE_ARCH=${NODE_ARCH:-i386}



### --include
##    For 64bit it is better to create VMs with more memory and storage because of
##    increased memory footprint (we suggest 4GB)::

##         NODE_CPU=1 NODE_MEM=4096 NODE_DISK=40 NODE_ARCH=amd64


## #. Configure a network for your test environment.
##    This configures an openvswitch bridge and teaches libvirt about it.
##    ::

setup-network $NUM

## #. Configure a seed VM. This VM has a disk image manually configured by
##    later scripts, and hosts the statically configured seed which is used
##    to bootstrap a full dynamically configured baremetal cloud. The seed VM
##    specs can be configured with the environment variables SEED_CPU and
##    SEED_MEM (MB). It defaults to the NODE_CPU and NODE_MEM values, since
##    the seed is equivalent to an undercloud in resource requirements.
##    ::

BRIDGE=
SEED_ARGS="-a $NODE_ARCH"
if [ -n "$NUM" ]; then
    SEED_ARGS="$SEED_ARGS -o seed_${NUM}"
fi
if [ -n "$OVSBRIDGE" ]; then
    BRIDGE="brbm${NUM}"
    SEED_ARGS="$SEED_ARGS -b $BRIDGE -p $OVSBRIDGE"
fi
SEED_CPU=${SEED_CPU:-${NODE_CPU}}
SEED_MEM=${SEED_MEM:-${NODE_MEM}}

## #. Clean up any prior environment.  Unless the --keep-vms argument is
##    passed to the script, VMs for the undercloud and overcloud are
##    destroyed
##    ::

if [ -z "$KEEP_VMS" ]; then
    if [ -n "$NUM" ]; then
        cleanup-env -n $NUM
    else
        cleanup-env
    fi
fi

#Now start creating the new environment
setup-seed-vm $SEED_ARGS -c ${SEED_CPU} -m $((1024 * ${SEED_MEM}))

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

if [ -n "$NETS_PATH" ]; then
    # if the value is not set try the default 192.0.2.1.
    SEEDIP=$(jq '.["seed"]["ip"] // "192.0.2.1"' -r $NETS_PATH)
else
    SEEDIP=${SEEDIP:-''}
fi


## #. Set the default bare metal power manager. By default devtest uses
##    nova.virt.baremetal.virtual_power_driver.VirtualPowerManager to
##    support a fully virtualized TripleO test environment. You may
##    optionally customize this setting if you are using real baremetal
##    hardware with the devtest scripts. This setting controls the
##    power manager used in both the seed VM and undercloud for Nova Baremetal.
##    ::

POWER_MANAGER=${POWER_MANAGER:-'nova.virt.baremetal.virtual_power_driver.VirtualPowerManager'}

## #. Ensure we can ssh into the host machine to turn VMs on and off.
##    The private key we create will be embedded in the seed VM, and delivered
##    dynamically by heat to the undercloud VM.
##    ::

# generate ssh authentication keys if they don't exist
if [ ! -f $SSH_KEY ]; then
    ssh-keygen -t rsa -N "" -C virtual-power-key -f $SSH_KEY
fi

# make the local id_rsa_virt_power.pub be in ``.ssh/authorized_keys`` before
# that is copied into images via ``local-config``
if ! grep -qF "$(cat ${SSH_KEY}.pub)" ~/.ssh/authorized_keys; then
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
    "ssh-key":"$(cat $SSH_KEY)",
    "ssh-user":"$SSH_USER"
}
EOF

## #. If you have an existing bare metal cloud network to use, use it. See
##    `baremetal-network` section in :ref:`devtest-environment-configuration`
##    for more details
##    ::

devtest_update_network.sh ${NETS_PATH:+--bm-networks $NETS_PATH} $JSONFILE

## #. If you have an existing set of nodes to use, use them.
##    ::

if [ -n "$NODES_PATH" ]; then
    JSON=$(jq -s '.[0].nodes=.[1] | .[0]' $JSONFILE $NODES_PATH)
    echo "${JSON}" > $JSONFILE
else

## #. Create baremetal nodes for the test cluster. If the required number of
##    VMs changes in future, you can run cleanup-env and then recreate with
##    more nodes.
##    ::

create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH $NODE_CNT $SSH_USER $HOSTIP $JSONFILE $BRIDGE
### --end
fi
