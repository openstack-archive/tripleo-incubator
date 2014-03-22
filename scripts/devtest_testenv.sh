#!/bin/bash
#
# Test environment creation for devtest.
# This creates the bridge and VM's - it won't be used in CI.

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options] {JSON-filename}"
    echo
    echo "Setup a TripleO devtest environment."
    echo
    echo "JSON-filename -- the path to write the environment description to."
    echo
    echo "Note: This adds a unique key to your authorised_keys file to permit "
    echo "virtual-power-managment calls to be made."
    echo
    exit $1
}

TEMP=`getopt -o h,c -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h) show_options 0;;
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
## ::

JSONFILE=${1:-''}

### --end
EXTRA_ARGS=${2:-''}

if [ -z "$JSONFILE" -o -n "$EXTRA_ARGS" ]; then
    show_options 1
fi

### --include

## #. Configure a network for your test environment.
##    This configures an openvswitch bridge and teaches libvirt about it.
##    ::

setup-network

## #. Configure a seed VM. This VM has a disk image manually configured by
##    later scripts, and hosts the statically configured seed which is used
##    to bootstrap a full dynamically configured baremetal cloud.
##    ::

setup-seed-vm -a $NODE_ARCH

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


## #. Create baremetal nodes for the test cluster. The final parameter to
##    create-nodes is the number of VMs to create. To change this in future
##    you can run clean-env and then recreate with more nodes.
##    ::

NODE_CNT=$(( $OVERCLOUD_COMPUTESCALE + 2 ))
create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH $NODE_CNT $SSH_USER $HOSTIP $JSONFILE

### --end
