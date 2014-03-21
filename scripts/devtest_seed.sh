#!/bin/bash

set -eux
set -o pipefail

USE_CACHE=${USE_CACHE:-0}

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
TMP=`mktemp`
if [ $USE_IRONIC -eq 0 ]; then
# Sets:
# - bm node arch
# - bm power manager
# - ssh power host
# - ssh power key
# - ssh power user

    jq -s '.[1] as $config |(.[0].nova.baremetal |= (.virtual_power.user=$config["ssh-user"]|.virtual_power.ssh_host=$config["host-ip"]|.virtual_power.ssh_key=$config["ssh-key"]|.arch=$config.arch|.power_manager=$config.power_manager))| .[0]' config.json $TE_DATAFILE > local.json
else

    jq -s '.[1]' config.json $TE_DATAFILE > local.json
fi
### --end
# If running in a CI environment then the user and ip address should be read
# from the json describing the environment
REMOTE_OPERATIONS=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key remote-operations --type raw --key-default '')
if [ -n "$REMOTE_OPERATIONS" ] ; then
    HOST_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key host-ip --type netaddress --key-default '')
    SSH_USER=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key ssh-user --type raw --key-default 'root')
    sed -i "s/\"192.168.122.1\"/\"$HOST_IP\"/" local.json
    sed -i "s/\"user\": \".*\?\",/\"user\": \"$SSH_USER\",/" local.json
fi
### --include

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

cd $TRIPLEO_ROOT
if [ "$USE_CACHE" == "0" ] ; then #nodocs
    boot-seed-vm -a $NODE_ARCH $NODE_DIST neutron-dhcp-agent 2>&1 | \
        tee $TRIPLEO_ROOT/dib-seed.log
else #nodocs
    boot-seed-vm -c -a $NODE_ARCH $NODE_DIST neutron-dhcp-agent 2>&1 | tee $TRIPLEO_ROOT/dib-seed.log #nodocs
fi #nodocs

##    boot-seed-vm will start a VM and copy your SSH pub key into the VM so that
##    you can log into it with 'ssh stack@192.0.2.1'.
##
##    The IP address of the VM is printed out at the end of boot-seed-vm, or
##    you can query the testenv json which is updated by boot-seed-vm::

SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress)

## #. Add a route to the baremetal bridge via the seed node (we do this so that
##    your host is isolated from the networking of the test environment.
##    ::

# These are not persistent, if you reboot, re-run them.
ROUTE_DEV=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-route-dev --type netdevice --key-default virbr0)
sudo ip route del 192.0.2.0/24 dev $ROUTE_DEV || true
sudo ip route add 192.0.2.0/24 dev $ROUTE_DEV via $SEED_IP

## #. Mask the seed API endpoint out of your proxy settings
##    ::

set +u #nodocs
export no_proxy=$no_proxy,192.0.2.1
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

echo "Waiting for nova to initialise..."
wait_for 50 10 nova list
user-config

echo "Waiting for Nova Compute to be available"
wait_for 30 10 nova service-list --binary nova-compute 2\>/dev/null \| grep 'enabled.*\ up\ '
echo "Waiting for neutron API and L2 agent to be available"
wait_for 30 10 neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*\"" #nodocs

setup-neutron 192.0.2.2 192.0.2.20 192.0.2.0/24 192.0.2.1 192.0.2.1 ctlplane

## #. Register "bare metal" nodes with nova and setup Nova baremetal flavors.
##    When using VMs Nova will PXE boot them as though they use physical
##    hardware.
##    If you want to create the VM yourself see footnote [#f2]_ for details
##    on its requirements.
##    If you want to use real baremetal see footnote [#f3]_ for details.
##    ::

setup-baremetal --service-host seed --nodes <(jq '[.nodes[0]]' $TE_DATAFILE)

##    If you need to collect the MAC address separately, see scripts/get-vm-mac.

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
##    * When calling setup-baremetal you can set the MAC, IP address, user,
##      and password parameters which should all be space delemited lists
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

