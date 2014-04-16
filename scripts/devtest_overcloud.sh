#!/bin/bash

set -eu
set -o pipefail

SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Deploys a KVM cloud via heat."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo
    exit $1
}

TEMP=$(getopt -o h -l help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

set -x
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
OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server'}
OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS=${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:-''}
TE_DATAFILE=${TE_DATAFILE:?"TE_DATAFILE must be defined before calling this script!"}
# This will stop being a parameter once rebuild ``--preserve-ephemeral`` is fully
# merged. For now, it requires manual effort to use, so it should be opt-in.
# Since it's not an end-user thing yet either, we don't document it in the
# example prose below either.
# The patch sets needed are:
# nova: I6bf01e52589c5894eb043f2b57e915d52e81ebc3
# python-novaclient: Ib1511653904d4f95ab03fb471669175127004582
OVERCLOUD_IMAGE_UPDATE_POLICY=${OVERCLOUD_IMAGE_UPDATE_POLICY:-'REBUILD_PRESERVE_EPHEMERAL'}

### --include
## devtest_overcloud
## =================

## #. Create your overcloud control plane image.
##    
##    This is the image the undercloud
##    will deploy to become the KVM (or QEMU, Xen, etc.) cloud control plane.
##    
##    ``$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS`` and ``$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS`` are
##    meant to be used to pass additional build-time specific arguments to
##    ``disk-image-create``.
##    
##    ``$SSL_ELEMENT`` is used when building a cloud with SSL endpoints - it should be
##    set to openstack-ssl in that situation.
##    ::

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

if [ ! -e $TRIPLEO_ROOT/overcloud-control.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-control hosts \
        baremetal boot-stack cinder-api cinder-volume os-collect-config horizon \
        neutron-network-node dhcp-all-interfaces swift-proxy swift-storage \
        $DIB_COMMON_ELEMENTS $OVERCLOUD_CONTROL_DIB_EXTRA_ARGS ${SSL_ELEMENT:-} 2>&1 | \
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
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute hosts \
        baremetal nova-compute nova-kvm neutron-openvswitch-agent os-collect-config \
        dhcp-all-interfaces $DIB_COMMON_ELEMENTS $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-compute.log
fi #nodocs

## #. Load the image into Glance:
##    ::

OVERCLOUD_COMPUTE_ID=$(load-image -d $TRIPLEO_ROOT/overcloud-compute.qcow2)

## #. For running an overcloud in VM's. For Physical machines, set to kvm:
##    ::

OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-"qemu"}

## #. Set the public interface of overcloud network node::
##    ::

NeutronPublicInterface=${NeutronPublicInterface:-'eth0'}

## #. If you want to permit VM's access to bare metal networks, you need
##    to define flat-networks and bridge mappings in Neutron::
##    ::

OVERCLOUD_FLAT_NETWORKS=${OVERCLOUD_FLAT_NETWORKS:-''}
OVERCLOUD_BRIDGE_MAPPINGS=${OVERCLOUD_BRIDGE_MAPPINGS:-''}
OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE=${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE:-''}
OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE=${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE:-''}

## #. If you are using SSL, your compute nodes will need static mappings to your
##    endpoint in ``/etc/hosts`` (because we don't do dynamic undercloud DNS yet).
##    set this to the DNS name you're using for your SSL certificate - the heat
##    template looks up the controller address within the cloud::

OVERCLOUD_NAME=${OVERCLOUD_NAME:-''}

## #. Choose whether to deploy or update. Use stack-update to update::

##         HEAT_OP=stack-create

### --end

if heat stack-show $STACKNAME > /dev/null; then
    HEAT_OP=stack-update
    if (heat stack-show $STACKNAME | grep -q FAILED); then
        echo "Cannot update a failed stack" >&2
        exit 1
    fi
else
    HEAT_OP=stack-create
fi

### --include

## #. Wait for the BM cloud to register BM nodes with the scheduler::

expected_nodes=$((1+$OVERCLOUD_COMPUTESCALE))
wait_for 60 1 [ "\$(nova hypervisor-stats | awk '\$2==\"count\" { print \$4}')" -ge $expected_nodes ]

## #. Deploy an overcloud::

### --end
if [ -e tripleo-overcloud-passwords ]; then
  echo "Re-using existing passwords in $PWD/tripleo-overcloud-passwords"
  source tripleo-overcloud-passwords
else
### --include
  setup-overcloud-passwords $TRIPLEO_ROOT/tripleo-overcloud-passwords
  source $TRIPLEO_ROOT/tripleo-overcloud-passwords
fi #nodocs

make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml COMPUTESCALE=$OVERCLOUD_COMPUTESCALE
##         heat $HEAT_OP -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
##             -P "AdminToken=${OVERCLOUD_ADMIN_TOKEN}" \
##             -P "AdminPassword=${OVERCLOUD_ADMIN_PASSWORD}" \
##             -P "CinderPassword=${OVERCLOUD_CINDER_PASSWORD}" \
##             -P "CloudName=${OVERCLOUD_NAME}" \
##             -P "GlancePassword=${OVERCLOUD_GLANCE_PASSWORD}" \
##             -P "HeatPassword=${OVERCLOUD_HEAT_PASSWORD}" \
##             -P "HypervisorNeutronPhysicalBridge=${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE}" \
##             -P "HypervisorNeutronPublicInterface=${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE}" \
##             -P "NeutronFlatNetworks=${OVERCLOUD_FLAT_NETWORKS}" \
##             -P "NeutronBridgeMappings=${OVERCLOUD_BRIDGE_MAPPINGS}" \
##             -P "NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD}" \
##             -P "NovaPassword=${OVERCLOUD_NOVA_PASSWORD}" \
##             -P "NeutronPublicInterface=${NeutronPublicInterface}" \
##             -P "SwiftPassword=${OVERCLOUD_SWIFT_PASSWORD}" \
##             -P "SwiftHashSuffix=${OVERCLOUD_SWIFT_HASH}" \
##             -P "NovaComputeLibvirtType=${OVERCLOUD_LIBVIRT_TYPE}" \
##             -P "SSLCertificate=${OVERCLOUD_SSL_CERT}" \
##             -P "SSLKey=${OVERCLOUD_SSL_KEY}" \
##             overcloud

### --end

# This param name will soon change from 'notCompute' --> 'controller'
CONTROLLER_IMAGE_PARAM=notcomputeImage
if [ -e $TRIPLEO_ROOT/tripleo-heat-templates/controller.yaml ] ; then
    CONTROLLER_IMAGE_PARAM=controllerImage
fi

heat $HEAT_OP -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
    -P "AdminToken=${OVERCLOUD_ADMIN_TOKEN}" \
    -P "AdminPassword=${OVERCLOUD_ADMIN_PASSWORD}" \
    -P "CinderPassword=${OVERCLOUD_CINDER_PASSWORD}" \
    -P "CloudName=${OVERCLOUD_NAME}" \
    -P "GlancePassword=${OVERCLOUD_GLANCE_PASSWORD}" \
    -P "HeatPassword=${OVERCLOUD_HEAT_PASSWORD}" \
    -P "HypervisorNeutronPhysicalBridge=${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE}" \
    -P "HypervisorNeutronPublicInterface=${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE}" \
    -P "NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD}" \
    -P "NovaPassword=${OVERCLOUD_NOVA_PASSWORD}" \
    -P "NeutronFlatNetworks=${OVERCLOUD_FLAT_NETWORKS}" \
    -P "NeutronBridgeMappings=${OVERCLOUD_BRIDGE_MAPPINGS}" \
    -P "NeutronPublicInterface=${NeutronPublicInterface}" \
    -P "NeutronPublicInterfaceIP=${NeutronPublicInterfaceIP}" \
    -P "NeutronPublicInterfaceRawDevice=${NeutronPublicInterfaceRawDevice}" \
    -P "NeutronPublicInterfaceDefaultRoute=${NeutronPublicInterfaceDefaultRoute}" \
    -P "SwiftPassword=${OVERCLOUD_SWIFT_PASSWORD}" \
    -P "SwiftHashSuffix=${OVERCLOUD_SWIFT_HASH}" \
    -P "NovaComputeLibvirtType=${OVERCLOUD_LIBVIRT_TYPE}" \
    -P "ImageUpdatePolicy=${OVERCLOUD_IMAGE_UPDATE_POLICY}" \
    -P "$CONTROLLER_IMAGE_PARAM=${OVERCLOUD_CONTROL_ID}" \
    -P "NovaImage=${OVERCLOUD_COMPUTE_ID}" \
    -P "SSLCertificate=${OVERCLOUD_SSL_CERT}" \
    -P "SSLKey=${OVERCLOUD_SSL_KEY}" \
    $STACKNAME

### --include

##    You can watch the console via ``virsh``/``virt-manager`` to observe the PXE
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
wait_for_stack_ready 300 10 $STACKNAME
OVERCLOUD_IP=$(nova list | grep "notCompute0.*ctlplane\|controller.*ctlplane" | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")
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

## #. Export the overcloud endpoint and credentials to your test environment.
##    ::

OVERCLOUD_ENDPOINT="http://$OVERCLOUD_IP:5000/v2.0"
NEW_JSON=$(jq '.overcloud.password="'${OVERCLOUD_ADMIN_PASSWORD}'" | .overcloud.endpoint="'${OVERCLOUD_ENDPOINT}'" | .overcloud.endpointhost="'${OVERCLOUD_IP}'"' $TE_DATAFILE)
echo $NEW_JSON > $TE_DATAFILE

## #. Source the overcloud configuration::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc

## #. Exclude the overcloud from proxies::

set +u #nodocs
export no_proxy=$no_proxy,$OVERCLOUD_IP
set -u #nodocs

## #. If we updated the cloud we don't need to do admin setup again - skip down to `Wait for Nova Compute`_.

if [ "stack-create" = "$HEAT_OP" ]; then #nodocs

## #. Perform admin setup of your overcloud.
##    ::

    init-keystone -p $OVERCLOUD_ADMIN_PASSWORD $OVERCLOUD_ADMIN_TOKEN \
        $OVERCLOUD_IP admin@example.com heat-admin@$OVERCLOUD_IP \
        ${SSLBASE:+--ssl $PUBLIC_API_URL}
    setup-endpoints $OVERCLOUD_IP \
        --cinder-password $OVERCLOUD_CINDER_PASSWORD \
        --glance-password $OVERCLOUD_GLANCE_PASSWORD \
        --heat-password $OVERCLOUD_HEAT_PASSWORD \
        --neutron-password $OVERCLOUD_NEUTRON_PASSWORD \
        --nova-password $OVERCLOUD_NOVA_PASSWORD \
        --swift-password $OVERCLOUD_SWIFT_PASSWORD \
        ${SSLBASE:+--ssl $PUBLIC_API_URL}
    keystone role-create --name heat_stack_user
    # Creating these roles to be used by tenants using swift
    keystone role-create --name=swiftoperator
    keystone role-create --name=ResellerAdmin
    user-config
##             setup-neutron "" "" 10.0.0.0/8 "" "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24
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

## #. _`Wait for Nova Compute`
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
    FLOATINGIP=$(neutron floatingip-create ext-net \
        --port-id "${PORT//[[:space:]]/}" \
        | awk '$2=="floating_ip_address" {print $4}')

## #. And allow network access to it.
##    ::

    neutron security-group-rule-create default --protocol icmp \
        --direction ingress --port-range-min 8
    neutron security-group-rule-create default --protocol tcp \
        --direction ingress --port-range-min 22 --port-range-max 22

### --end
else
    FLOATINGIP=$(neutron floatingip-list \
        --quote=none -f csv -c floating_ip_address | tail -n 1)
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
