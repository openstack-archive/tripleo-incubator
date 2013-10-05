#!/bin/bash

set -eu

### --include
## devtest_undercloud
## ==================


## #. Create your undercloud image. This is the image that the seed nova
##    will deploy to become the baremetal undercloud. Note that stackuser is only
##    there for debugging support - it is not suitable for a production network.
##    ::

$TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
    -a $NODE_ARCH -o $TRIPLEO_ROOT/undercloud \
    boot-stack nova-baremetal os-collect-config stackuser $DHCP_DRIVER

## #. Load the undercloud image into Glance:
##    ::

load-image $TRIPLEO_ROOT/undercloud.qcow2

## #. Create secrets for the cloud. The secrets will be written to a file
##    (tripleo-passwords by default) that you need to source into your shell
##    environment.  Note that you can also make or change these later and
##    update the heat stack definition to inject them - as long as you also
##    update the keystone recorded password. Note that there will be a window
##    between updating keystone and instances where they will disagree and
##    service will be down. Instead consider adding a new service account and
##    changing everything across to it, then deleting the old account after
##    the cluster is updated.
##    ::

setup-undercloud-passwords
source tripleo-undercloud-passwords

## #. Deploy an undercloud::

if [ "$DHCP_DRIVER" != "bm-dnsmasq" ]; then
    UNDERCLOUD_NATIVE_PXE=""
else
    UNDERCLOUD_NATIVE_PXE=";NeutronNativePXE=True"
fi

heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/undercloud-vm.yaml \
    -P "PowerUserName=$(whoami);AdminToken=${UNDERCLOUD_ADMIN_TOKEN};AdminPassword=${UNDERCLOUD_ADMIN_PASSWORD};GlancePassword=${UNDERCLOUD_GLANCE_PASSWORD};HeatPassword=${UNDERCLOUD_HEAT_PASSWORD};NeutronPassword=${UNDERCLOUD_NEUTRON_PASSWORD};NovaPassword=${UNDERCLOUD_NOVA_PASSWORD};BaremetalArch=${NODE_ARCH}$UNDERCLOUD_NATIVE_PXE" \
    undercloud

##    You can watch the console via virsh/virt-manager to observe the PXE
##    boot/deploy process.  After the deploy is complete, it will reboot into the
##    image.
## 
## #. Get the undercloud IP from 'nova list'
##    ::

echo "Waiting for seed nova to configure undercloud node..." #nodocs
wait_for 60 10 "nova list | grep ctlplane" #nodocs
export UNDERCLOUD_IP=$(nova list | grep ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

echo "Waiting for undercloud node to configure br-ctlplane..." #nodocs
wait_for 60 10 "echo | nc -w 1 $UNDERCLOUD_IP 22" >/dev/null #nodocs
ssh-keygen -R $UNDERCLOUD_IP

## #. Source the undercloud configuration:
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc

## #. Exclude the undercloud from proxies:
##    ::

export no_proxy=$no_proxy,$UNDERCLOUD_IP

## #. Perform setup of your undercloud.
##    ::

init-keystone -p $UNDERCLOUD_ADMIN_PASSWORD $UNDERCLOUD_ADMIN_TOKEN \
    $UNDERCLOUD_IP admin@example.com heat-admin@$UNDERCLOUD_IP
setup-endpoints $UNDERCLOUD_IP --glance-password $UNDERCLOUD_GLANCE_PASSWORD \
    --heat-password $UNDERCLOUD_HEAT_PASSWORD \
    --neutron-password $UNDERCLOUD_NEUTRON_PASSWORD \
    --nova-password $UNDERCLOUD_NOVA_PASSWORD
keystone role-create --name heat_stack_user
user-config
setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 $UNDERCLOUD_IP ctlplane
if [ "$DHCP_DRIVER" != "bm-dnsmasq" ]; then
    # See bug 1231366 - this may become part of setup-neutron if that is
    # determined to be not a bug.
    UNDERCLOUD_DHCP_AGENT_UUID=$(neutron agent-list | awk '/DHCP/ { print $2 }')
    neutron dhcp-agent-network-add $UNDERCLOUD_DHCP_AGENT_UUID ctlplane
fi

## #. Create two more 'baremetal' node(s) and register them with your undercloud.
##    ::

export UNDERCLOUD_MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 2)
setup-baremetal $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH "$UNDERCLOUD_MACS" undercloud

## #. Allow the VirtualPowerManager to ssh into your host machine to power on vms:
##    ::

ssh heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

##
### --end
