#!/bin/bash

set -eu

# Parameters for tripleo-cd - see the tripleo-cd element.
NeutronPublicInterface=${1:-'eth0'}
NeutronPublicInterfaceIP=${2:-''}
NeutronPublicInterfaceRawDevice=${3:-''}
NeutronPublicInterfaceDefaultRoute=${4:-''}
FLOATING_START=${5:-'192.0.2.45'}
FLOATING_END=${6:-'192.0.2.64'}
FLOATING_CIDR=${7:-'192.0.2.0/24'}
ADMIN_USERS=${8:-''}
USERS=${9:-''}

### --include
## devtest_overcloud
## =================

## #. Create your overcloud control plane image. This is the image the undercloud
##    will deploy to become the KVM (or QEMU, Xen, etc.) cloud control plane.
##    Note that stackuser is only there for debugging support - it is not
##    suitable for a production network.
##    ::

$TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
    -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-control \
    boot-stack cinder os-collect-config neutron-network-node notcompute \
    dhcp-all-interfaces stackuser 2>&1 | \
    tee $TRIPLEO_ROOT/dib-overcloud-control.log

## #. Load the image into Glance:
##    ::

load-image -d $TRIPLEO_ROOT/overcloud-control.qcow2

## #. Create your overcloud compute image. This is the image the undercloud
##    deploys to host KVM (or QEMU, Xen, etc.) instances. Note that stackuser 
##    is only there for debugging support - it is not suitable for a production
##    network.
##    ::

$TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
    -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute \
    nova-compute nova-kvm neutron-openvswitch-agent os-collect-config \
    dhcp-all-interfaces stackuser 2>&1 | \
    tee $TRIPLEO_ROOT/dib-overcloud-compute.log

## #. Load the image into Glance:
##    ::

load-image -d $TRIPLEO_ROOT/overcloud-compute.qcow2

## #. For running an overcloud in VM's::
##    ::

OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-";NovaComputeLibvirtType=qemu"}

## #. Delete any previous overcloud::

##         heat stack-delete overcloud || true

### --end

# Should really be wait_for, but it can't cope with complex if/or yet.
tries=0
while true;
    do (heat stack-show overcloud > /dev/null) || break
    if [ $((++tries)) -gt 120 ] ; then
        echo ERROR: Giving up waiting for overcloud delete to complete after 120 attempts.
        exit 1
    fi
    heat stack-delete overcloud || true
    # Don't busy-spin
    sleep 2;
done

### --include

## #. Deploy an overcloud::

setup-overcloud-passwords
source tripleo-overcloud-passwords

make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml
heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
    -P "AdminToken=${OVERCLOUD_ADMIN_TOKEN};AdminPassword=${OVERCLOUD_ADMIN_PASSWORD};CinderPassword=${OVERCLOUD_CINDER_PASSWORD};GlancePassword=${OVERCLOUD_GLANCE_PASSWORD};HeatPassword=${OVERCLOUD_HEAT_PASSWORD};NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD};NovaPassword=${OVERCLOUD_NOVA_PASSWORD};NeutronPublicInterface=${NeutronPublicInterface};NeutronPublicInterfaceIP=${NeutronPublicInterfaceIP};NeutronPublicInterfaceRawDevice=${NeutronPublicInterfaceRawDevice};NeutronPublicInterfaceDefaultRoute=${NeutronPublicInterfaceDefaultRoute}${OVERCLOUD_LIBVIRT_TYPE}" \
    overcloud

##    You can watch the console via virsh/virt-manager to observe the PXE
##    boot/deploy process.  After the deploy is complete, the machines will reboot
##    and be available.

## #. While we wait for the stack to come up, build an end user disk image and
##    register it with glance.::

$TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST vm \
    -a $NODE_ARCH -o $TRIPLEO_ROOT/user 2>&1 | tee $TRIPLEO_ROOT/dib-user.log

## #. Get the overcloud IP from 'nova list'
##    ::

echo "Waiting for the stack to be ready" #nodocs
wait_for 190 10 stack-ready overcloud
export OVERCLOUD_IP=$(nova list | grep notcompute.*ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")
### --end
# If we're forcing a specific public interface, we'll want to advertise that as
# the public endpoint for APIs.
if [ -n "$NeutronPublicInterfaceIP" ]; then
    OVERCLOUD_IP=$(echo ${NeutronPublicInterfaceIP} | sed -e s,/.*,,)
fi

### --include
ssh-keygen -R $OVERCLOUD_IP

## #. Source the overcloud configuration::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc

## #. Exclude the undercloud from proxies::

set +u #nodocs
export no_proxy=$no_proxy,$OVERCLOUD_IP
set -u #nodocs

## #. Perform admin setup of your overcloud.
##    ::

init-keystone -p $OVERCLOUD_ADMIN_PASSWORD $OVERCLOUD_ADMIN_TOKEN \
    $OVERCLOUD_IP admin@example.com heat-admin@$OVERCLOUD_IP
setup-endpoints $OVERCLOUD_IP --cinder-password $OVERCLOUD_CINDER_PASSWORD \
    --glance-password $OVERCLOUD_GLANCE_PASSWORD \
    --heat-password $OVERCLOUD_HEAT_PASSWORD \
    --neutron-password $OVERCLOUD_NEUTRON_PASSWORD \
    --nova-password $OVERCLOUD_NOVA_PASSWORD
keystone role-create --name heat_stack_user
user-config
##         setup-neutron "" "" 10.0.0.0/8 "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24
setup-neutron "" "" 10.0.0.0/8 "" "" $FLOATING_START $FLOATING_END $FLOATING_CIDR #nodocs

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

## #. Log in as a user.
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc-user
user-config

## #. Deploy your image.
##    ::

nova boot --key-name default --flavor m1.tiny --image user demo

## #. Add an external IP for it.
##    ::

PORT=$(neutron port-list -f csv -c id --quote none | tail -n1)
neutron floatingip-create ext-net --port-id "${PORT//[[:space:]]/}"

## #. And allow network access to it.
##    ::

neutron security-group-rule-create default --protocol icmp \
    --direction ingress --port-range-min 8 --port-range-max 8
neutron security-group-rule-create default --protocol tcp \
    --direction ingress --port-range-min 22 --port-range-max 22

##
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
