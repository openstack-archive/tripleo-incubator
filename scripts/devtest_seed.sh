#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Deploys a baremetal cloud via virsh."
    echo
    echo "Options:"
    echo "      -h              -- this help"
    echo "      -c              -- re-use existing source/images if they exist."
    echo "      --build-only    -- build the needed images but don't deploy them."
    echo "      --debug-logging -- Turn on debug logging in the seed. Sets both the"
    echo "                         OS_DEBUG_LOGGING env var and the debug environment"
    echo "                         json values."
    echo "      --all-nodes     -- use all the nodes in the testenv rather than"
    echo "                        just the first one."
    echo
    exit $1
}

BUILD_ONLY=
DEBUG_LOGGING=

TEMP=$(getopt -o c,h -l all-nodes,build-only,debug-logging,help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --all-nodes) ALL_NODES="true"; shift 1;;
        -c) USE_CACHE=1; shift 1;;
        --build-only) BUILD_ONLY="--build-only"; shift 1;;
        --debug-logging)
            DEBUG_LOGGING="seed-debug-logging"
            export OS_DEBUG_LOGGING="1"
            shift 1
            ;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

set -x
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

## #. Ironic and Nova-Baremetal require different metadata to operate.
##    ::

if [ $USE_IRONIC -eq 0 ]; then
# Unsets .ironic as it's unused.
# TODO replace "ironic": {} with del(.ironic) when jq 1.3 is widely available.
# Sets:
# - bm node arch
# - bm power manager
# - ssh power host
# - ssh power key
# - ssh power user
    jq -s '
        .[1] as $config
        | .[0]
        | .nova.baremetal as $bm
        | . + {
            "ironic": {},
            "nova": (.nova + {
                "baremetal": ($bm + {
                    "arch": $config.arch,
                    "power_manager": $config.power_manager,
                    "virtual_power": ($bm.virtual_power + {
                        "user": $config["ssh-user"],
                        "ssh_host": $config["host-ip"],
                        "ssh_key": $config["ssh-key"]
                    })
                })
            })
        }' config.json $TE_DATAFILE > tmp_local.json
else
# Unsets .nova.baremetal as it's unused.
# TODO replace "baremetal": {} with del(.baremetal) when jq 1.3 is widely available.
# Sets:
# - ironic.virtual_power_ssh_key.
# - nova.compute_driver to ironic.nova.virt.ironic.driver.IronicDriver.
# - nova.compute_manager to avoid race conditions on ironic startup.
    jq -s '
        .[1] as $config
        | .[0]
        | . + {
            "ironic": (.ironic + {
                "virtual_power_ssh_key": $config["ssh-key"],
            }),
            "nova": (.nova  + {
                "baremetal": {},
                "compute_driver": "nova.virt.ironic.driver.IronicDriver",
                "compute_manager": "ironic.nova.compute.manager.ClusteredComputeManager",
                "scheduler_host_manager": "nova.scheduler.ironic_host_manager.IronicHostManager",
            })
        }' config.json $TE_DATAFILE > tmp_local.json
fi

# Add Keystone certs/key into the environment file
generate-keystone-pki --heatenv tmp_local.json -s

# Get details required to set-up a callback heat call back from the seed from os-collect-config.
HOST_IP=$(os-apply-config -m $TE_DATAFILE --key host-ip --type netaddress --key-default '192.168.122.1')
COMP_IP=$(ip route get "$HOST_IP" | awk '/'"$HOST_IP"'/ {print $NF}')

SEED_COMP_PORT="${SEED_COMP_PORT:-27410}"
SEED_IMAGE_ID="${SEED_IMAGE_ID:-seedImageID}"

# Firewalld interferes with our seed completion signal
if systemctl status firewalld; then
    if ! sudo firewall-cmd --list-ports | grep "$SEED_COMP_PORT/tcp"; then
        echo 'Firewalld is running and the seed completion port is not open.'
        echo 'To continue you must either stop firewalld or open the port with:'
        echo "sudo firewall-cmd --add-port=$SEED_COMP_PORT/tcp"
        exit 1
    fi
fi

# Apply custom BM network settings to the seeds local.json config
# Because the seed runs under libvirt and usually isn't in routing tables for
# access to the networks behind it, we setup masquerading for the bm networks,
# which permits outbound access from the machines we've deployed.
# If the seed is not the router (e.g. real machines are being used) then these
# rules are harmless.
BM_NETWORK_CIDR=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.cidr --type raw --key-default '192.0.2.0/24')
BM_VLAN_SEED_TAG=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.seed.public_vlan.tag --type netaddress --key-default '')
BM_VLAN_SEED_IP=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.seed.public_vlan.ip --type netaddress --key-default '')
if [ -n "$BM_VLAN_SEED_IP" ]; then
    BM_VLAN_SEED_IP_ADDR=$(python -c "import netaddr; print netaddr.IPNetwork('$BM_VLAN_SEED_IP').ip")
    BM_VLAN_SEED_IP_CIDR=$(python -c "import netaddr; print '%s/%s' % (netaddr.IPNetwork('$BM_VLAN_SEED_IP').network, netaddr.IPNetwork('$BM_VLAN_SEED_IP').prefixlen)")
    echo "{ \"ovs\": {\"public_interface_tag\": \"${BM_VLAN_SEED_TAG}\", \"public_interface_tag_ip\": \"${BM_VLAN_SEED_IP}\"}, \"masquerade\": [\"${BM_VLAN_SEED_IP}\"] }" > bm-vlan.json
else
    echo "{ \"ovs\": {}, \"masquerade\": [] }" > bm-vlan.json
fi
BM_BRIDGE_ROUTE=$(jq -r '.["baremetal-network"].seed.physical_bridge_route // {}' $TE_DATAFILE)
BM_CTL_ROUTE_PREFIX=$(jq -r '.["baremetal-network"].seed.physical_bridge_route.prefix // ""' $TE_DATAFILE)
BM_CTL_ROUTE_VIA=$(jq -r '.["baremetal-network"].seed.physical_bridge_route.via // ""' $TE_DATAFILE)
jq -s '
    .[1]["baremetal-network"] as $bm
    | ($bm.seed.ip // "192.0.2.1") as $bm_seed_ip
    | .[2] as $bm_vlan
    | .[3] as $bm_bridge_route
    | .[0]
    | . + {
    "local-ipv4": $bm_seed_ip,
    "completion-signal": ("http://'"${COMP_IP}"':'"${SEED_COMP_PORT}"'"),
    "instance-id": "'"${SEED_IMAGE_ID}"'",
    "bootstack": (.bootstack + {
        "public_interface_ip": ($bm_seed_ip + "/'"${BM_NETWORK_CIDR##*/}"'"),
        "masquerade_networks": ([$bm.cidr // "192.0.2.0/24"] + $bm_vlan.masquerade)
    }),
    "heat": (.heat + {
        "watch_server_url": ("http://" + $bm_seed_ip + ":8003"),
        "waitcondition_server_url": ("http://" + $bm_seed_ip + ":8000/v1/waitcondition"),
        "metadata_server_url": ("http://" + $bm_seed_ip + ":8000")
    }),
    "neutron": (.neutron + {
        "ovs": (.neutron.ovs + $bm_vlan.ovs + {"local_ip": $bm_seed_ip } + {
        "physical_bridge_route": $bm_bridge_route
        })
    })
}' tmp_local.json $TE_DATAFILE bm-vlan.json <(echo "$BM_BRIDGE_ROUTE") > local.json
rm tmp_local.json
rm bm-vlan.json

### --end
# If running in a CI environment then the user and ip address should be read
# from the json describing the environment
REMOTE_OPERATIONS=$(os-apply-config -m $TE_DATAFILE --key remote-operations --type raw --key-default '')
if [ -n "$REMOTE_OPERATIONS" ] ; then
    SSH_USER=$(os-apply-config -m $TE_DATAFILE --key ssh-user --type raw --key-default 'root')
    sed -i "s/\"192.168.122.1\"/\"$HOST_IP\"/" local.json
    sed -i "s/\"user\": \".*\?\",/\"user\": \"$SSH_USER\",/" local.json
fi
### --include

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

## #. If you are only building disk images, there is no reason to boot the
##    seed VM. Instead, pass ``--build-only`` to tell boot-seed-vm not to boot
##    the vm it builds.

##    If you want to use a previously built image rather than building a new
##    one, passing ``-c`` will boot the existing image rather than creating
##    a new one.

##    ::

cd $TRIPLEO_ROOT
##         boot-seed-vm -a $NODE_ARCH $NODE_DIST neutron-dhcp-agent
### --end
if [ "$USE_CACHE" == "0" ] ; then
    CACHE_OPT=
else
    CACHE_OPT="-c"
fi
boot-seed-vm $CACHE_OPT $BUILD_ONLY -a $NODE_ARCH $NODE_DIST $DEBUG_LOGGING neutron-dhcp-agent 2>&1 | \
        tee $TRIPLEO_ROOT/dib-seed.log

if [ -n "${BUILD_ONLY}" ]; then
    exit 0
fi
### --include

## #. If you're just building images, you're done with this script. Move on
##    to :doc:`devtest_undercloud`

##    ``boot-seed-vm`` will start a VM containing your SSH key for the root user.
## 
##    The IP address of the VM's eth0 is printed out at the end of boot-seed-vm, or
##    you can query the testenv json which is updated by boot-seed-vm::

SEED_IP=$(os-apply-config -m $TE_DATAFILE --key seed-ip --type netaddress)

## #. Add a route to the baremetal bridge via the seed node (we do this so that
##    your host is isolated from the networking of the test environment.
##    We only add this route if the baremetal seed IP is used as the
##    gateway (the route is typically not required if you are using
##    a pre-existing baremetal network)
##    ::

# These are not persistent, if you reboot, re-run them.

BM_NETWORK_SEED_IP=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.seed.ip --type raw --key-default '192.0.2.1')
BM_NETWORK_GATEWAY=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.gateway-ip --type raw --key-default '192.0.2.1')
if [ $BM_NETWORK_GATEWAY = $BM_NETWORK_SEED_IP -o $BM_NETWORK_GATEWAY = ${BM_VLAN_SEED_IP_ADDR:-''} ]; then
    ROUTE_DEV=$(os-apply-config -m $TE_DATAFILE --key seed-route-dev --type netdevice --key-default virbr0)
    sudo ip route replace $BM_NETWORK_CIDR dev $ROUTE_DEV via $SEED_IP
    if [ -n "$BM_VLAN_SEED_IP" ]; then
        sudo ip route replace $BM_VLAN_SEED_IP_CIDR via $SEED_IP
    fi
fi

## #. Mask the seed API endpoint out of your proxy settings
##    ::

set +u #nodocs
export no_proxy=$no_proxy,$BM_NETWORK_SEED_IP
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

## #. If Ironic is in use, we need to setup a user for it.
##    ::

if [ $USE_IRONIC -eq 0 ]; then
    IRONIC_OPT=
else
    IRONIC_OPT="--ironic-password unset"
fi

## #. Perform setup of your seed cloud.
##    ::

echo "Waiting for seed node to configure br-ctlplane..." #nodocs

# Listen on SEED_COMP_PORT for a callback from os-collect-config. This is
# similar to how Heat waits, but Heat does not run on the seed.
timeout 480 sh -c 'printf "HTTP/1.0 200 OK\r\n\r\n\r\n" | nc -l '"$COMP_IP"' '"$SEED_COMP_PORT"' | grep '"$SEED_IMAGE_ID"

# Wait for network
wait_for -w 10 --delay 1 -- ping -c 1 $BM_NETWORK_SEED_IP

# If ssh-keyscan fails to connect, it returns 0. So grep to see if it succeeded
ssh-keyscan -t rsa $BM_NETWORK_SEED_IP | tee -a ~/.ssh/known_hosts | grep -q "^$BM_NETWORK_SEED_IP ssh-rsa "

init-keystone -o $BM_NETWORK_SEED_IP -t unset -e admin@example.com -p unset --no-pki-setup
setup-endpoints $BM_NETWORK_SEED_IP --glance-password unset --heat-password unset --neutron-password unset --nova-password unset $IRONIC_OPT
keystone role-create --name heat_stack_user
# Creating these roles to be used by tenants using swift
keystone role-create --name=swiftoperator
keystone role-create --name=ResellerAdmin

echo "Waiting for nova to initialise..."
wait_for -w 500 --delay 10 -- nova list
user-config

echo "Waiting for Nova Compute to be available"
wait_for -w 300 --delay 10 -- nova service-list --binary nova-compute 2\>/dev/null \| grep 'enabled.*\ up\ '
echo "Waiting for neutron API and L2 agent to be available"
wait_for -w 300 --delay 10 -- neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*\"" #nodocs

BM_NETWORK_SEED_RANGE_START=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.seed.range-start --type raw --key-default '192.0.2.2')
BM_NETWORK_SEED_RANGE_END=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.seed.range-end --type raw --key-default '192.0.2.20')

if [ -n "$BM_VLAN_SEED_TAG" ]; then
    # With a public VLAN, the gateway address is on the public LAN.
    CTL_GATEWAY=
else
    CTL_GATEWAY=$BM_NETWORK_GATEWAY
fi

SEED_NAMESERVER=$(os-apply-config -m $TE_DATAFILE --key seed.nameserver --type netaddress --key-default "${SEED_NAMESERVER:-}")
NETWORK_JSON=$(mktemp)
jq "." <<EOF > $NETWORK_JSON
{
    "physical": {
        "gateway": "$CTL_GATEWAY",
        "metadata_server": "$BM_NETWORK_SEED_IP",
        "cidr": "$BM_NETWORK_CIDR",
        "allocation_start": "$BM_NETWORK_SEED_RANGE_START",
        "allocation_end": "$BM_NETWORK_SEED_RANGE_END",
        "name": "ctlplane",
        "nameserver": "$SEED_NAMESERVER"
    }
}
EOF
if [ -n "$BM_CTL_ROUTE_PREFIX" -a -n "$BM_CTL_ROUTE_VIA" ]; then
    EXTRA_ROUTE="{\"destination\": \"$BM_CTL_ROUTE_PREFIX\", \"nexthop\": \"$BM_CTL_ROUTE_VIA\"}"
    TMP_NETWORK=$(mktemp)
    jq ".[\"physical\"][\"extra_routes\"]=[$EXTRA_ROUTE]" < $NETWORK_JSON > $TMP_NETWORK
    mv $TMP_NETWORK $NETWORK_JSON
fi
setup-neutron -n $NETWORK_JSON
rm $NETWORK_JSON
# Is there a public network as well? If so configure it.
if [ -n "$BM_VLAN_SEED_TAG" ]; then
    BM_VLAN_SEED_START=$(jq -r '.["baremetal-network"].seed.public_vlan.start' $TE_DATAFILE)
    BM_VLAN_SEED_END=$(jq -r '.["baremetal-network"].seed.public_vlan.finish' $TE_DATAFILE)
    BM_VLAN_SEED_TAG=$(jq -r '.["baremetal-network"].seed.public_vlan.tag' $TE_DATAFILE)

    PUBLIC_NETWORK_JSON=$(mktemp)
    jq "." <<EOF > $PUBLIC_NETWORK_JSON
{
    "physical": {
        "gateway": "$BM_NETWORK_GATEWAY",
        "metadata_server": "$BM_NETWORK_SEED_IP",
        "cidr": "$BM_VLAN_SEED_IP_CIDR",
        "allocation_start": "$BM_VLAN_SEED_START",
        "allocation_end": "$BM_VLAN_SEED_END",
        "name": "public",
        "nameserver": "$SEED_NAMESERVER",
        "segmentation_id": "$BM_VLAN_SEED_TAG",
        "physical_network": "ctlplane",
        "enabled_dhcp": false
    }
}
EOF
    setup-neutron -n $PUBLIC_NETWORK_JSON
    rm $PUBLIC_NETWORK_JSON
fi

## #. Nova quota runs up with the defaults quota so overide the default to
##    allow unlimited cores, instances and ram.
##    ::

nova quota-update --cores -1 --instances -1 --ram -1 $(keystone tenant-get admin | awk '$2=="id" {print $4}')


## #. Register "bare metal" nodes with nova and setup Nova baremetal flavors.
##    When using VMs Nova will PXE boot them as though they use physical
##    hardware.
##    If you want to create the VM yourself see footnote [#f2]_ for details
##    on its requirements.
##    If you want to use real baremetal see footnote [#f3]_ for details.
##    If you are building an undercloud, register only the first node.
##    ::

if [ -z "${ALL_NODES:-}" ]; then #nodocs
    setup-baremetal --service-host seed --nodes <(jq '[.nodes[0]]' $TE_DATAFILE)
else #nodocs

##    Otherwise, if you are skipping the undercloud, you should register all
##    the nodes.::

    setup-baremetal --service-host seed --nodes <(jq '.nodes' $TE_DATAFILE)
fi #nodocs

##    If you need to collect the MAC address separately, see ``scripts/get-vm-mac``.

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
