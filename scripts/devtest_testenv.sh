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

JSONFILE=${1:-''}
EXTRA_ARGS=${2:-''}

if [ -z "$JSONFILE" -o -n "$EXTRA_ARGS" ]; then
    show_options 1
fi

### --include
## devtest_testenv
## ===============

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
##    create-nodes is the number of VMs to create. To change this in future
##    you can either run clean-env and then recreate with more nodes, or
##    use create-nodes to make more nodes then add their macs to your
##    testenv.json.
##    ::

export MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 3 | tr '\r\n' ' ')

## #. What IP address to ssh to for virsh operations.
##    ::

export HOSTIP=${HOSTIP:-192.168.122.1}

## #. If a static SEEDIP is in use, define it here. If not defined it will be
##    looked up in the ARP table by the seed MAC address during seed deployment.
##    ::

export SEEDIP=${SEEDIP:-''}

echo "{\"host-ip\":\"$HOSTIP\", \"seed-ip\":\"$SEEDIP\", \"node-macs\":\"$MACS\"}" > ${JSONFILE:-$TE_DATAFILE}

### --end
