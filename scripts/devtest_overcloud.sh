#!/bin/bash

set -eu
set -o pipefail

OS_PASSWORD=${OS_PASSWORD:?"OS_PASSWORD is not set. Undercloud credentials are required"}

# Parameters for tripleo-cd - see the tripleo-cd element.
# NOTE(rpodolyaka): retain backwards compatibility by accepting both positional
#                   arguments and environment variables. Positional arguments
#                   take precedence over environment variables
NeutronPublicInterface=${1:-${NeutronPublicInterface:-'eth0'}}
NeutronPublicInterfaceIP=${2:-${NeutronPublicInterfaceIP:-''}}
NeutronPublicInterfaceRawDevice=${3:-${NeutronPublicInterfaceRawDevice:-''}}
NeutronPublicInterfaceDefaultRoute=${4:-${NeutronPublicInterfaceDefaultRoute:-''}}
FLOATING_START=${5:-${FLOATING_START:-'192.0.2.45'}}
FLOATING_END=${6:-${FLOATING_END:-'192.0.2.64'}}
FLOATING_CIDR=${7:-${FLOATING_CIDR:-'192.0.2.0/24'}}
ADMIN_USERS=${8:-${ADMIN_USERS:-''}}
USERS=${9:-${USERS:-''}}
STACKNAME=${10:-overcloud}
# If set, the base name for a .crt and .key file for SSL. This will trigger
# inclusion of openstack-ssl in the build and pass the contents of the files to heat.
# Note that PUBLIC_API_URL ($12) must also be set for SSL to actually be used.
SSLBASE=${11:-''}
OVERCLOUD_SSL_CERT=${SSLBASE:+$(<$SSLBASE.crt)}
OVERCLOUD_SSL_KEY=${SSLBASE:+$(<$SSLBASE.key)}
PUBLIC_API_URL=${12:-''}
SSL_ELEMENT=${SSLBASE:+openstack-ssl}
USE_CACHE=${USE_CACHE:-0}
DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-'stackuser'}
# This will stop being a parameter once rebuild --preserve-ephemeral is fully
# merged. For now, it requires manual effort to use, so it should be opt-in.
# Since it's not an end-user thing yet either, we don't document it in the
# example prose below either.
# The patch sets needed are:
# nova: I6bf01e52589c5894eb043f2b57e915d52e81ebc3
# python-novaclient: Ib1511653904d4f95ab03fb471669175127004582
OVERCLOUD_IMAGE_UPDATE_POLICY=${OVERCLOUD_IMAGE_UPDATE_POLICY:-'REBUILD'}

### --include
## devtest_overcloud
## =================

## #. Create your overcloud control plane image. This is the image the undercloud
##    will deploy to become the KVM (or QEMU, Xen, etc.) cloud control plane.
##    $OVERCLOUD_DIB_EXTRA_ARGS is meant to be used to pass additional build-time
##    specific arguments to disk-image-create.
##    SSL_ELEMENT is used when building a cloud with SSL endpoints - it should be
##    set to openstack-ssl in that situation.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-control.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-control \
        boot-stack cinder-api cinder-volume os-collect-config \
        neutron-network-node dhcp-all-interfaces swift-proxy swift-storage \
        $DIB_COMMON_ELEMENTS ${OVERCLOUD_DIB_EXTRA_ARGS:-} ${SSL_ELEMENT:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-control.log
fi #nodocs

## #. Load the image into Glance:
##    ::

OVERCLOUD_CONTROL_ID=$(load-image -d $TRIPLEO_ROOT/overcloud-control.qcow2)

## #. Create your overcloud compute image. This is the image the undercloud
##    deploys to host KVM (or QEMU, Xen, etc.) instances.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-compute.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute \
        nova-compute nova-kvm neutron-openvswitch-agent os-collect-config \
        dhcp-all-interfaces $DIB_COMMON_ELEMENTS ${OVERCLOUD_DIB_EXTRA_ARGS:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-compute.log
fi #nodocs

## #. Load the image into Glance:
##    ::

OVERCLOUD_COMPUTE_ID=$(load-image -d $TRIPLEO_ROOT/overcloud-compute.qcow2)

## #. For running an overcloud in VM's::
##    ::

OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-";NovaComputeLibvirtType=qemu"}

## #. Set the public interface of overcloud network node::
##    ::

NeutronPublicInterface=${NeutronPublicInterface:-'eth0'}

## #. Choose whether to deploy or update. Use stack-update to update::

##         HEAT_OP=stack-create

### --end

if heat stack-show $STACKNAME > /dev/null; then
    HEAT_OP=stack-update
else
    HEAT_OP=stack-create
fi

### --include

## #. Deploy an overcloud::

setup-overcloud-passwords
source tripleo-overcloud-passwords

make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml COMPUTESCALE=2
##         heat $HEAT_OP -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
##             -P "AdminToken=${OVERCLOUD_ADMIN_TOKEN};AdminPassword=${OVERCLOUD_ADMIN_PASSWORD};CinderPassword=${OVERCLOUD_CINDER_PASSWORD};GlancePassword=${OVERCLOUD_GLANCE_PASSWORD};HeatPassword=${OVERCLOUD_HEAT_PASSWORD};NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD};NovaPassword=${OVERCLOUD_NOVA_PASSWORD};NeutronPublicInterface=${NeutronPublicInterface};SwiftPassword=${OVERCLOUD_SWIFT_PASSWORD};SwiftHashSuffix=${OVERCLOUD_SWIFT_HASH}${OVERCLOUD_LIBVIRT_TYPE};SSLCertificate=${OVERCLOUD_SSL_CERT};SSLKey=${OVERCLOUD_SSL_KEY}" \
##             overcloud

### --end

heat $HEAT_OP -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
    -P "AdminToken=${OVERCLOUD_ADMIN_TOKEN};AdminPassword=${OVERCLOUD_ADMIN_PASSWORD};CinderPassword=${OVERCLOUD_CINDER_PASSWORD};GlancePassword=${OVERCLOUD_GLANCE_PASSWORD};HeatPassword=${OVERCLOUD_HEAT_PASSWORD};NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD};NovaPassword=${OVERCLOUD_NOVA_PASSWORD};NeutronPublicInterface=${NeutronPublicInterface};NeutronPublicInterfaceIP=${NeutronPublicInterfaceIP};NeutronPublicInterfaceRawDevice=${NeutronPublicInterfaceRawDevice};NeutronPublicInterfaceDefaultRoute=${NeutronPublicInterfaceDefaultRoute};SwiftPassword=${OVERCLOUD_SWIFT_PASSWORD};SwiftHashSuffix=${OVERCLOUD_SWIFT_HASH}${OVERCLOUD_LIBVIRT_TYPE};ImageUpdatePolicy=${OVERCLOUD_IMAGE_UPDATE_POLICY};notcomputeImage=${OVERCLOUD_CONTROL_ID};NovaImage=${OVERCLOUD_COMPUTE_ID};SSLCertificate=${OVERCLOUD_SSL_CERT};SSLKey=${OVERCLOUD_SSL_KEY}" \
    $STACKNAME

### --include

##    You can watch the console via virsh/virt-manager to observe the PXE
##    boot/deploy process.  After the deploy is complete, the machines will reboot
##    and be available.

## #. While we wait for the stack to come up, build an end user disk image and
##    register it with glance.::

if [ ! -e $TRIPLEO_ROOT/user.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST vm \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/user 2>&1 | tee $TRIPLEO_ROOT/dib-user.log
fi #nodocs

## #. Get the overcloud IP from 'nova list'
##    ::

echo "Waiting for the overcloud stack to be ready" #nodocs
wait_for 220 10 stack-ready $STACKNAME #nodocs
##         wait_for 220 10 stack-ready overcloud
export OVERCLOUD_IP=$(nova list | grep notcompute.*ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")
### --end
# If we're forcing a specific public interface, we'll want to advertise that as
# the public endpoint for APIs.
if [ -n "$NeutronPublicInterfaceIP" ]; then
    OVERCLOUD_IP=$(echo ${NeutronPublicInterfaceIP} | sed -e s,/.*,,)
fi

### --include

## #. We don't (yet) preserve ssh keys on rebuilds.
##    ::

ssh-keygen -R $OVERCLOUD_IP

## #. Source the overcloud configuration::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc

## #. Exclude the overcloud from proxies::

set +u #nodocs
export no_proxy=$no_proxy,$OVERCLOUD_IP
set -u #nodocs

## #. If we updated the cloud we don't need to do admin setup again - skip down to 'Wait for nova-compute'.

if [ "stack-create" = "$HEAT_OP" ]; then #nodocs

## #. Perform admin setup of your overcloud.
##    ::

init-keystone -p $OVERCLOUD_ADMIN_PASSWORD $OVERCLOUD_ADMIN_TOKEN \
    $OVERCLOUD_IP admin@example.com heat-admin@$OVERCLOUD_IP \
    ${SSLBASE:+--ssl $PUBLIC_API_URL}
setup-endpoints $OVERCLOUD_IP --cinder-password $OVERCLOUD_CINDER_PASSWORD \
    --glance-password $OVERCLOUD_GLANCE_PASSWORD \
    --heat-password $OVERCLOUD_HEAT_PASSWORD \
    --neutron-password $OVERCLOUD_NEUTRON_PASSWORD \
    --nova-password $OVERCLOUD_NOVA_PASSWORD \
    --swift-password $OVERCLOUD_SWIFT_PASSWORD \
    ${SSLBASE:+--ssl $PUBLIC_API_URL}
keystone role-create --name heat_stack_user
user-config
##         setup-neutron "" "" 10.0.0.0/8 "" "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24
setup-neutron "" "" 10.0.0.0/8 "" "" "" $FLOATING_START $FLOATING_END $FLOATING_CIDR #nodocs

## #. If you want a demo user in your overcloud (probably a good idea).
##    ::

os-adduser -p $OVERCLOUD_DEMO_PASSWORD demo demo@example.com

## #. Workaround https://bugs.launchpad.net/diskimage-builder/+bug/1211165.
##    ::

nova flavor-delete m1.tiny
nova flavor-create m1.tiny 1 512 2 1

## #. Register the end user image with glance.
##    ::

glance image-create --name user --public --disk-format qcow2 \
    --container-format bare --file $TRIPLEO_ROOT/user.qcow2

fi #nodocs

## #. Wait for Nova Compute
##    ::

wait_for 30 10 nova service-list --binary nova-compute 2\>/dev/null \| grep 'enabled.*\ up\ '

## #. Wait for L2 Agent On Nova Compute
##    ::

wait_for 30 10 neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*$STACKNAME-novacompute\"" #nodocs
##         wait_for 30 10 neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*overcloud-novacompute\""

## #. Log in as a user.
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc-user

## #. If you just created the cloud you need to add your keypair to your user.
##    ::

if [ "stack-create" = "$HEAT_OP" ] ; then #nodocs
user-config

## #. So that you can deploy a VM.
##    ::

nova boot --key-name default --flavor m1.tiny --image user demo

## #. Add an external IP for it.
##    ::

wait_for 10 5 neutron port-list -f csv -c id --quote none \| grep id
PORT=$(neutron port-list -f csv -c id --quote none | tail -n1)
FLOATINGIP=$(neutron floatingip-create ext-net --port-id "${PORT//[[:space:]]/}" | awk '$2=="floating_ip_address" {print $4}')

## #. And allow network access to it.
##    ::

neutron security-group-rule-create default --protocol icmp \
    --direction ingress --port-range-min 8 --port-range-max 8
neutron security-group-rule-create default --protocol tcp \
    --direction ingress --port-range-min 22 --port-range-max 22

### --end
else
FLOATINGIP=$(neutron floatingip-list --quote=none -f csv -c floating_ip_address | tail -n 1)
nova stop demo
sleep 5
nova start demo
fi
### --include

## #. After which, you should be able to ping it
##    ::

wait_for 30 10 ping -c 1 $FLOATINGIP

### --end

if [ -n "$ADMIN_USERS" ]; then
    source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc
    assert-admin-users "$ADMIN_USERS"
    assert-users "$ADMIN_USERS"
fi

if [ -n "$USERS" ] ; then
    source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc
    assert-users "$USERS"
fi
