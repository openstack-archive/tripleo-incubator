#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Builds overcloud images using defined environment variables."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo "      -c             -- re-use existing source/images if they exist."
    exit $1
}

TEMP=$(getopt -o c,h,help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then
    echo "Terminating..." >&2;
    exit 1;
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -c) USE_CACHE=1; shift 1;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

USE_CACHE=${USE_CACHE:-0}
DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-'stackuser'}
OVERCLOUD_CONTROL_DIB_ELEMENTS=${OVERCLOUD_CONTROL_DIB_ELEMENTS:-'ntp hosts baremetal boot-stack cinder-api ceilometer-collector ceilometer-api ceilometer-agent-central ceilometer-agent-notification ceilometer-alarm-notifier ceilometer-alarm-evaluator os-collect-config horizon neutron-network-node dhcp-all-interfaces swift-proxy swift-storage keepalived haproxy sysctl'}
OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server cinder-tgt'}
OVERCLOUD_COMPUTE_DIB_ELEMENTS=${OVERCLOUD_COMPUTE_DIB_ELEMENTS:-'ntp hosts baremetal nova-compute nova-kvm neutron-openvswitch-agent os-collect-config dhcp-all-interfaces sysctl'}
OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS=${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:-''}

OVERCLOUD_BLOCKSTORAGE_DIB_ELEMENTS=${OVERCLOUD_BLOCKSTORAGE_DIB_ELEMENTS:-'ntp hosts baremetal os-collect-config dhcp-all-interfaces sysctl'}
OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS=${OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS:-'cinder-tgt'}
SSL_ELEMENT=${SSLBASE:+openstack-ssl}
TE_DATAFILE=${TE_DATAFILE:?"TE_DATAFILE must be defined before calling this script!"}

if [ "${USE_MARIADB:-}" = 1 ] ; then
    OVERCLOUD_CONTROL_DIB_EXTRA_ARGS="$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS mariadb-rpm"
    OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS="$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS mariadb-dev-rpm"
    OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS="$OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS mariadb-dev-rpm"
fi

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

### --include
## devtest_overcloud_images
## ========================
## Build images with environment variables. This script works best
## when using tripleo-image-elements for Overcloud configuration.

## #. Undercloud UI needs SNMPd for monitoring of every Overcloud node
##    ::

if [ "$USE_UNDERCLOUD_UI" -ne 0 ] ; then
    OVERCLOUD_CONTROL_DIB_EXTRA_ARGS="$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS snmpd"
    OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS="$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS snmpd"
    OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS="$OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS snmpd"
fi

## #. Create your overcloud control plane image.

##    ``$OVERCLOUD_*_DIB_EXTRA_ARGS`` (CONTROL, COMPUTE, BLOCKSTORAGE) are
##    meant to be used to pass additional build-time specific arguments to
##    ``disk-image-create``.

##    ``$SSL_ELEMENT`` is used when building a cloud with SSL endpoints - it should be
##    set to openstack-ssl in that situation.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-control.qcow2 -o "$USE_CACHE" == "0" ] ; then
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-control \
        $OVERCLOUD_CONTROL_DIB_ELEMENTS \
        $DIB_COMMON_ELEMENTS $OVERCLOUD_CONTROL_DIB_EXTRA_ARGS ${SSL_ELEMENT:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-control.log
fi

## #. Create your block storage image if some block storage nodes are to be used. This
##    is the image the undercloud deploys for the additional cinder-volume nodes.
##    ::

if [ ${OVERCLOUD_BLOCKSTORAGESCALE:-0} -gt 0 ]; then
    if [ ! -e $TRIPLEO_ROOT/overcloud-cinder-volume.qcow2 -o "$USE_CACHE" == "0" ]; then
        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
            -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-cinder-volume \
            $OVERCLOUD_BLOCKSTORAGE_DIB_ELEMENTS $DIB_COMMON_ELEMENTS \
            $OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS 2>&1 | \
            tee $TRIPLEO_ROOT/dib-overcloud-cinder-volume.log
    fi
fi

##    If enabling distributed virtual routing for Neutron on the overcloud the compute node
##    must have the ``neutron-router`` element installed.
##    ::

OVERCLOUD_DISTRIBUTED_ROUTERS=${OVERCLOUD_DISTRIBUTED_ROUTERS:-'False'}
OVERCLOUD_L3=${OVERCLOUD_L3:-'relocate'}
if [ $OVERCLOUD_DISTRIBUTED_ROUTERS == "True" -o $OVERCLOUD_L3 == "dvr"  ]; then
    OVERCLOUD_COMPUTE_DIB_ELEMENTS="$OVERCLOUD_COMPUTE_DIB_ELEMENTS neutron-router"
fi

## #. Create your overcloud compute image. This is the image the undercloud
##    deploys to host the overcloud Nova compute hypervisor components.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-compute.qcow2 -o "$USE_CACHE" == "0" ]; then
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute \
        $OVERCLOUD_COMPUTE_DIB_ELEMENTS $DIB_COMMON_ELEMENTS \
        $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-compute.log
fi
### --end
