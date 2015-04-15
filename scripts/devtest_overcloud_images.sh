#!/bin/bash

set -eu
set -o pipefail

USE_CACHE=${USE_CACHE:-0}
DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-'stackuser'}
OVERCLOUD_CONTROL_DIB_ELEMENTS=${OVERCLOUD_CONTROL_DIB_ELEMENTS:-'ntp hosts baremetal boot-stack cinder-api ceilometer-collector ceilometer-api ceilometer-agent-central ceilometer-agent-notification ceilometer-alarm-notifier ceilometer-alarm-evaluator os-collect-config horizon neutron-network-node dhcp-all-interfaces swift-proxy swift-storage keepalived haproxy sysctl'}
OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server cinder-tgt'}
OVERCLOUD_COMPUTE_DIB_ELEMENTS=${OVERCLOUD_COMPUTE_DIB_ELEMENTS:-'ntp hosts baremetal nova-compute nova-kvm neutron-openvswitch-agent os-collect-config dhcp-all-interfaces sysctl'}
OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS=${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:-''}

OVERCLOUD_BLOCKSTORAGE_DIB_ELEMENTS=${OVERCLOUD_BLOCKSTORAGE_DIB_ELEMENTS:-'ntp hosts baremetal os-collect-config dhcp-all-interfaces sysctl'}
OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS=${OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS:-'cinder-tgt'}
SSL_ELEMENT=${SSLBASE:+openstack-ssl}

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

##    This is the image the undercloud
##    will deploy to become the KVM (or QEMU, Xen, etc.) cloud control plane.

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
##    is the image the undercloud deploys for the additional cinder-volume instances.
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

## #. Distributed virtual routing can be enabled by setting the environment variable
##    ``OVERCLOUD_DISTRIBUTED_ROUTERS`` to ``True``.  By default the legacy centralized
##    routing is enabled.

##    If enabling distributed virtual routing for Neutron on the overcloud the compute node
##    must have the ``neutron-router`` element installed.
##    ::

OVERCLOUD_DISTRIBUTED_ROUTERS=${OVERCLOUD_DISTRIBUTED_ROUTERS:-'False'}
if [ $OVERCLOUD_DISTRIBUTED_ROUTERS == "True" ]; then
    OVERCLOUD_COMPUTE_DIB_ELEMENTS="$OVERCLOUD_COMPUTE_DIB_ELEMENTS neutron-router"
fi

## #. Create your overcloud compute image. This is the image the undercloud
##    deploys to host KVM (or QEMU, Xen, etc.) instances.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-compute.qcow2 -o "$USE_CACHE" == "0" ]; then
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute \
        $OVERCLOUD_COMPUTE_DIB_ELEMENTS $DIB_COMMON_ELEMENTS \
        $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-compute.log
fi
### --end
