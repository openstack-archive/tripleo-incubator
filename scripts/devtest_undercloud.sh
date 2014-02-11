#!/bin/bash

set -eu
set -o pipefail

USE_CACHE=${USE_CACHE:-0}
TE_DATAFILE=${1:?"A test environment description is required as \$1."}

### --include
## devtest_undercloud
## ==================


## #. Create your undercloud image. This is the image that the seed nova
##    will deploy to become the baremetal undercloud. $UNDERCLOUD_DIB_EXTRA_ARGS is
##    meant to be used to pass additional arguments to disk-image-create.
##    ::

if [ ! -e $TRIPLEO_ROOT/undercloud.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/undercloud \
        boot-stack nova-baremetal os-collect-config dhcp-all-interfaces \
        neutron-dhcp-agent $DIB_COMMON_ELEMENTS ${UNDERCLOUD_DIB_EXTRA_ARGS:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-undercloud.log
fi #nodocs

## #. Load the undercloud image into Glance:
##    ::

UNDERCLOUD_ID=$(load-image $TRIPLEO_ROOT/undercloud.qcow2)

## #. Create secrets for the cloud. The secrets will be written to a file
##    (tripleo-undercloud-passwords by default) that you need to source into
##    your shell environment.
##    Note that you can also make or change these later and
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
    -P "PowerUserName=$(whoami);AdminToken=${UNDERCLOUD_ADMIN_TOKEN};AdminPassword=${UNDERCLOUD_ADMIN_PASSWORD};GlancePassword=${UNDERCLOUD_GLANCE_PASSWORD};HeatPassword=${UNDERCLOUD_HEAT_PASSWORD};NeutronPassword=${UNDERCLOUD_NEUTRON_PASSWORD};NovaPassword=${UNDERCLOUD_NOVA_PASSWORD};BaremetalArch=${NODE_ARCH};PowerManager=$POWER_MANAGER;undercloudImage=${UNDERCLOUD_ID}" \
    undercloud

##    You can watch the console via virsh/virt-manager to observe the PXE
##    boot/deploy process.  After the deploy is complete, it will reboot into the
##    image.
## 
## #. Get the undercloud IP from 'nova list'
##    ::

echo "Waiting for the undercloud stack to be ready" #nodocs
wait_for 220 10 stack-ready undercloud
export UNDERCLOUD_IP=$(nova list | grep ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

## #. We don't (yet) preserve ssh keys on rebuilds.
##    ::

ssh-keygen -R $UNDERCLOUD_IP

## #. Exclude the undercloud from proxies:
##    ::

set +u #nodocs
export no_proxy=$no_proxy,$UNDERCLOUD_IP
set -u #nodocs

## #. Export the undercloud endpoint and credentials to your test environment.
##    ::

UNDERCLOUD_ENDPOINT="http://$UNDERCLOUD_IP:5000/v2.0"
NEW_JSON=$(jq '.undercloud.password="'${UNDERCLOUD_ADMIN_PASSWORD}'" | .undercloud.endpoint="'${UNDERCLOUD_ENDPOINT}'" | .undercloud.endpointhost="'${UNDERCLOUD_IP}'"' $TE_DATAFILE)
echo $NEW_JSON > $TE_DATAFILE

## #. Source the undercloud configuration:
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc

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

setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 192.0.2.1 $UNDERCLOUD_IP ctlplane

## #. Register two baremetal nodes with your undercloud.
##    ::

MAC_RANGE="2-$(( $OVERCLOUD_COMPUTESCALE + 2 ))"
UNDERCLOUD_MACS=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key node-macs --type raw | cut -d' ' -f $MAC_RANGE )
UNDERCLOUD_PM_IPS=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key node-pm-ips --type raw --key-default '' | cut -d' ' -f $MAC_RANGE )
UNDERCLOUD_PM_USERS=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key node-pm-users --type raw --key-default '' | cut -d' ' -f $MAC_RANGE )
UNDERCLOUD_PM_PASSWORDS=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key node-pm-passwords --type raw --key-default '' | cut -d' ' -f $MAC_RANGE )
setup-baremetal $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH "$UNDERCLOUD_MACS" undercloud "$UNDERCLOUD_PM_IPS" "$UNDERCLOUD_PM_USERS" "$UNDERCLOUD_PM_PASSWORDS"

## #. Allow the VirtualPowerManager to ssh into your host machine to power on vms:
##    ::

ssh heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

## 
### --end
