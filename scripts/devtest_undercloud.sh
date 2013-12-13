#!/bin/bash

set -eu

USE_CACHE=${USE_CACHE:-0}

### --include
## devtest_undercloud
## ==================


## #. Create your undercloud image. This is the image that the seed nova
##    will deploy to become the baremetal undercloud. Note that stackuser is only
##    there for debugging support - it is not suitable for a production network.
##    $UNDERCLOUD_DIB_EXTRA_ARGS is meant to be used to pass additional arguments
##    to disk-image-create.
##    ::

if [ ! -e $TRIPLEO_ROOT/undercloud.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/undercloud \
        boot-stack nova-baremetal os-collect-config stackuser dhcp-all-interfaces \
        neutron-dhcp-agent ${UNDERCLOUD_DIB_EXTRA_ARGS:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-undercloud.log
fi #nodocs

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

## #. Deploy an undercloud
##    ::
make -C $TRIPLEO_ROOT/tripleo-heat-templates undercloud-vm.yaml
heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/undercloud-vm.yaml \
    -P "PowerUserName=$(whoami);AdminToken=${UNDERCLOUD_ADMIN_TOKEN};AdminPassword=${UNDERCLOUD_ADMIN_PASSWORD};GlancePassword=${UNDERCLOUD_GLANCE_PASSWORD};HeatPassword=${UNDERCLOUD_HEAT_PASSWORD};NeutronPassword=${UNDERCLOUD_NEUTRON_PASSWORD};NovaPassword=${UNDERCLOUD_NOVA_PASSWORD};BaremetalArch=${NODE_ARCH};PowerManager=$POWER_MANAGER" \
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
wait_for 60 10 "echo | nc -w 1 $UNDERCLOUD_IP 22" #nodocs
ssh-keygen -R $UNDERCLOUD_IP

echo "Waiting for cloud-init to configure/restart sshd"  #nodocs
wait_for 10 5 ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no -t heat-admin@$UNDERCLOUD_IP  echo "" #nodocs

## #. Source the undercloud configuration:
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc

## #. Exclude the undercloud from proxies:
##    ::

set +u #nodocs
export no_proxy=$no_proxy,$UNDERCLOUD_IP
set -u #nodocs

## #. Perform setup of your undercloud.
##    ::

init-keystone -p $UNDERCLOUD_ADMIN_PASSWORD $UNDERCLOUD_ADMIN_TOKEN \
    $UNDERCLOUD_IP admin@example.com heat-admin@$UNDERCLOUD_IP
setup-endpoints $UNDERCLOUD_IP --glance-password $UNDERCLOUD_GLANCE_PASSWORD \
    --heat-password $UNDERCLOUD_HEAT_PASSWORD \
    --neutron-password $UNDERCLOUD_NEUTRON_PASSWORD \
    --nova-password $UNDERCLOUD_NOVA_PASSWORD
keystone role-create --name heat_stack_user

echo "Waiting for nova to initialise..."
wait_for 30 10 nova list
user-config

setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 192.0.2.1 $UNDERCLOUD_IP ctlplane


## #. Create two more 'baremetal' node(s) and register them with your undercloud. 
##    Alternately, If you are using real baremetal hardware we skip the first
##    entry (which was used by the seed) and use the remaining entries in
##    your MACS, PM_IPS, PM_USERS, and PM_PASSWORDS variables to configure
#     baremetal nodes in the undercloud (for the overcloud).
##    ::

if [ -n "$MACS" ]; then

    export UNDERCLOUD_MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 2)
    setup-baremetal $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH "$UNDERCLOUD_MACS" undercloud

else

    setup-baremetal $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH "${MACS#[^ ]* }" undercloud "${PM_IPS#[^ ]* }" "${PM_USERS#[^ ]* }" "${PM_PASSWORDS#[^ ]* }"

fi

## #. Allow the VirtualPowerManager to ssh into your host machine to power on vms:
##    ::

ssh heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

## 
### --end
