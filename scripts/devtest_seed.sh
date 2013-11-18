#!/bin/bash

set -eu

### --include
## devtest_seed
## ============



## #. Create and start your seed VM. This script invokes diskimage-builder with
##    suitable paths and options to create and start a VM that contains an
##    all-in-one OpenStack cloud with the baremetal driver enabled, and
##    preconfigures it for a development environment. Note that the seed has
##    minimal variation in it's configuration: the goal is to bootstrap with
##    a known-solid config.
##    ::

cd $TRIPLEO_ROOT/tripleo-image-elements/elements/seed-stack-config
sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" config.json
# If you use 64bit VMs (NODE_ARCH=amd64), update also architecture.
sed -i "s/\"arch\": \"i386\",/\"arch\": \"$NODE_ARCH\",/" config.json

cd $TRIPLEO_ROOT
boot-seed-vm -a $NODE_ARCH $NODE_DIST neutron-dhcp-agent

##    boot-seed-vm will start a VM and copy your SSH pub key into the VM so that
##    you can log into it with 'ssh root@192.0.2.1'.
## 
##    The IP address of the VM is printed out at the end of boot-elements, or
##    you can use the get-vm-ip script::

export SEED_IP=`get-vm-ip seed`

## #. Add a route to the baremetal bridge via the seed node (we do this so that
##    your host is isolated from the networking of the test environment.
##    ::

# These are not persistent, if you reboot, re-run them.
sudo ip route del 192.0.2.0/24 dev virbr0 || true
sudo ip route add 192.0.2.0/24 dev virbr0 via $SEED_IP

## #. Mask the SEED_IP out of your proxy settings
##    ::

set +u #nodocs
export no_proxy=$no_proxy,192.0.2.1,$SEED_IP
set -u #nodocs

## #. If you downloaded a pre-built seed image you will need to log into it
##    and customise the configuration within it. See footnote [#f1]_.)
## 
## #. Setup a prompt clue so you can tell what cloud you have configured.
##    (Do this once).
##    ::
## 
##      source $TRIPLEO_ROOT/tripleo-incubator/cloudprompt

## #. Source the client configuration for the seed cloud.
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/seedrc

## #. Perform setup of your seed cloud.
##    ::

echo "Waiting for seed node to configure br-ctlplane..." #nodocs
wait_for 30 10 ping -c 1 192.0.2.1
ssh-keyscan -t rsa 192.0.2.1 >>~/.ssh/known_hosts
init-keystone -p unset unset 192.0.2.1 admin@example.com root@192.0.2.1
setup-endpoints 192.0.2.1 --glance-password unset --heat-password unset --neutron-password unset --nova-password unset
keystone role-create --name heat_stack_user
user-config
setup-neutron 192.0.2.2 192.0.2.3 192.0.2.0/24 192.0.2.1 192.0.2.1 ctlplane

## #. Create a 'baremetal' node out of a KVM virtual machine and collect
##    its MAC address.
##    Nova will PXE boot this VM as though it is physical hardware.
##    If you want to create the VM yourself, see footnote [#f2]_ for details on
##    its requirements. The parameter to create-nodes is VM count.
##    ::

export SEED_MACS=$(create-nodes $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH 1)
setup-baremetal $NODE_CPU $NODE_MEM $NODE_DISK $NODE_ARCH "$SEED_MACS" seed

##    If you need to collect the MAC address separately, see scripts/get-vm-mac.
## 
## #. Allow the VirtualPowerManager to ssh into your host machine to power on vms:
##    ::

ssh root@192.0.2.1 "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

## .. rubric:: Footnotes
## 
## .. [#f1] Customize a downloaded seed image.
## 
##    If you downloaded your seed VM image, you may need to configure it.
##    Setup a network proxy, if you have one (e.g. 192.168.2.1 port 8080)
##    ::
## 
##         # Run within the image!
##         echo << EOF >> ~/.profile
##         export no_proxy=192.0.2.1
##         export http_proxy=http://192.168.2.1:8080/
##         EOF
## 
##    Add an ~/.ssh/authorized_keys file. The image rejects password authentication
##    for security, so you will need to ssh out from the VM console. Even if you
##    don't copy your authorized_keys in, you will still need to ensure that
##    /home/stack/.ssh/authorized_keys on your seed node has some kind of
##    public SSH key in it, or the openstack configuration scripts will error.
## 
##    You can log into the console using the username 'stack' password 'stack'.
## 
## .. [#f2] Requirements for the "baremetal node" VMs
## 
##    If you don't use create-nodes, but want to create your own VMs, here are some
##    suggestions for what they should look like.
## 
##    * each VM should have 1 NIC
##    * eth0 should be on brbm
##    * record the MAC addresses for the NIC of each VM.
##    * give each VM no less than 2GB of disk, and ideally give them
##      more than NODE_DISK, which defaults to 20GB
##    * 1GB RAM is probably enough (512MB is not enough to run an all-in-one
##      OpenStack), and 768M isn't enough to do repeated deploys with.
##    * if using KVM, specify that you will install the virtual machine via PXE.
##      This will avoid KVM prompting for a disk image or installation media.
## 
## .. [#f3] Notes when using real bare metal
## 
##    If you want to use real bare metal see the following.
## 
##    * When calling setup-baremetal you can set MACS, PM_IPS, PM_USERS,
##      and PM_PASSWORDS parameters which should all be space delemited lists
##      that correspond to the MAC addresses and power management commands
##      your real baremetal machines require. See scripts/setup-baremetal
##      for details.
## 
##    * If you see over-mtu packets getting dropped when iscsi data is copied
##      over the control plane you may need to increase the MTU on your brbm
##      interfaces. Symptoms that this might be the cause include:
##      ::
## 
##        iscsid: log shows repeated connection failed errors (and reconnects)
##        dmesg shows:
##            openvswitch: vnet1: dropped over-mtu packet: 1502 > 1500
## 
### --end
