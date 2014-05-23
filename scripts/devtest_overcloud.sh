#!/bin/bash

set -eu
set -o pipefail

SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

BUILD_ONLY=
HEAT_ENV=

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Deploys a KVM cloud via heat."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo "      --build-only   -- build the needed images but don't deploy them."
    echo "      --heat-env     -- path to a JSON heat environment file."
    echo "                        Defaults to \$TRIPLEO_ROOT/overcloud-env.json."
    echo
    exit $1
}

TEMP=$(getopt -o h -l build-only,heat-env:help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --build-only) BUILD_ONLY="1"; shift 1;;
        --heat-env) HEAT_ENV="$2"; shift 2;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

set -x
if [ -z "$BUILD_ONLY" ]; then
    OS_PASSWORD=${OS_PASSWORD:?"OS_PASSWORD is not set. Undercloud credentials are required"}
fi

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
NeutronControlPlaneID=$(neutron net-show ctlplane | grep ' id ' | awk '{print $4}')
# This will stop being a parameter once rebuild ``--preserve-ephemeral`` is fully
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

## #. Create your overcloud control plane image.

##    This is the image the undercloud
##    will deploy to become the KVM (or QEMU, Xen, etc.) cloud control plane.

##    ``$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS`` and ``$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS`` are
##    meant to be used to pass additional build-time specific arguments to
##    ``disk-image-create``.

##    ``$SSL_ELEMENT`` is used when building a cloud with SSL endpoints - it should be
##    set to openstack-ssl in that situation.
##    ::

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

## #. Undercloud UI needs SNMPd for monitoring of every Overcloud node
##    ::

if [ "$USE_UNDERCLOUD_UI" -ne 0 ] ; then
    OVERCLOUD_CONTROL_DIB_EXTRA_ARGS="$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS snmpd"
    OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS="$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS snmpd"
fi

if [ ! -e $TRIPLEO_ROOT/overcloud-control.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-control ntp hosts \
        baremetal boot-stack cinder-api cinder-volume cinder-tgt ceilometer-collector \
        ceilometer-api ceilometer-agent-central ceilometer-agent-notification \
        os-collect-config horizon neutron-network-node dhcp-all-interfaces \
        swift-proxy swift-storage keepalived \
        $DIB_COMMON_ELEMENTS $OVERCLOUD_CONTROL_DIB_EXTRA_ARGS ${SSL_ELEMENT:-} 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-control.log
fi #nodocs

## #. Unless you are just building the images, load the image into Glance.

##    ::

if [ -z "$BUILD_ONLY" ]; then #nodocs
OVERCLOUD_CONTROL_ID=$(load-image -d $TRIPLEO_ROOT/overcloud-control.qcow2)
fi #nodocs

## #. Create your overcloud compute image. This is the image the undercloud
##    deploys to host KVM (or QEMU, Xen, etc.) instances.
##    ::

if [ ! -e $TRIPLEO_ROOT/overcloud-compute.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
        -a $NODE_ARCH -o $TRIPLEO_ROOT/overcloud-compute ntp hosts \
        baremetal nova-compute nova-kvm neutron-openvswitch-agent os-collect-config \
        dhcp-all-interfaces $DIB_COMMON_ELEMENTS $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-overcloud-compute.log
fi #nodocs

## #. Load the image into Glance. If you are just building the images you are done.
##    ::
### --end

if [ -n "$BUILD_ONLY" ]; then
  exit 0
fi

### --include
OVERCLOUD_COMPUTE_ID=$(load-image -d $TRIPLEO_ROOT/overcloud-compute.qcow2)

## #. For running an overcloud in VM's. For Physical machines, set to kvm:
##    ::

OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-"qemu"}

## #. Set the public interface of overcloud network node::
##    ::

NeutronPublicInterface=${NeutronPublicInterface:-'eth0'}

## #. Set the NTP server for the overcloud::
##    ::

OVERCLOUD_NTP_SERVER=${OVERCLOUD_NTP_SERVER:-''}

## #. If you want to permit VM's access to bare metal networks, you need
##    to define flat-networks and bridge mappings in Neutron::
##    ::

OVERCLOUD_FLAT_NETWORKS=${OVERCLOUD_FLAT_NETWORKS:-''}
OVERCLOUD_BRIDGE_MAPPINGS=${OVERCLOUD_BRIDGE_MAPPINGS:-''}
OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE=${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE:-''}
OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE=${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE:-''}
OVERCLOUD_VIRTUAL_INTERFACE=${OVERCLOUD_VIRTUAL_INTERFACE:-'br-ex'}

## #. If you are using SSL, your compute nodes will need static mappings to your
##    endpoint in ``/etc/hosts`` (because we don't do dynamic undercloud DNS yet).
##    set this to the DNS name you're using for your SSL certificate - the heat
##    template looks up the controller address within the cloud::

OVERCLOUD_NAME=${OVERCLOUD_NAME:-''}

## #. TripleO explicitly models key settings for OpenStack, as well as settings
##    that require cluster awareness to configure. To configure arbitrary
##    additional settings, provide a JSON string with them in the structure
##    required by the template ExtraConfig parameter.

OVERCLOUD_EXTRA_CONFIG=${OVERCLOUD_EXTRA_CONFIG:-''}

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

expected_nodes=$(( $OVERCLOUD_COMPUTESCALE + $OVERCLOUD_CONTROLSCALE ))
wait_for 60 1 [ "\$(nova hypervisor-stats | awk '\$2==\"count\" { print \$4}')" -ge $expected_nodes ]

## #. Create unique credentials::

### --end
if [ -e tripleo-overcloud-passwords ]; then
  echo "Re-using existing passwords in $PWD/tripleo-overcloud-passwords"
  # Add any new passwords since the file was generated
  setup-overcloud-passwords tripleo-overcloud-passwords
  source tripleo-overcloud-passwords
else
### --include
  setup-overcloud-passwords $TRIPLEO_ROOT/tripleo-overcloud-passwords
  source $TRIPLEO_ROOT/tripleo-overcloud-passwords
fi #nodocs

## #. We need an environment file to store the parameters we're gonig to give
##    heat.::

HEAT_ENV=${HEAT_ENV:-"${TRIPLEO_ROOT}/overcloud-env.json"}

## #. Read the heat env in for updating.::

if [ -e "${HEAT_ENV}" ]; then
    ENV_JSON=$(cat "${HEAT_ENV}")
else
    ENV_JSON='{"parameters":{}}'
fi

export CERT_TMP_DIR=$(mktemp -t -d --tmpdir=${TMP_DIR:-/tmp} cert.XXXXXXXX)
generate-keystone-pki $CERT_TMP_DIR
CA_KEY=$(<$CERT_TMP_DIR/ca_key.pem)
CA_CERT=$(<$CERT_TMP_DIR/ca_cert.pem)
SIGNING_KEY=$(<$CERT_TMP_DIR/signing_key.pem)
SIGNING_CERT=$(<$CERT_TMP_DIR/signing_cert.pem)
rm -rf $CERT_TMP_DIR

## #. Set parameters we need to deploy a KVM cloud.::

ENV_JSON=$(jq '.parameters += {
    "AdminPassword": "'"${OVERCLOUD_ADMIN_PASSWORD}"'",
    "AdminToken": "'"${OVERCLOUD_ADMIN_TOKEN}"'",
    "CinderPassword": "'"${OVERCLOUD_CINDER_PASSWORD}"'",
    "CloudName": "'"${OVERCLOUD_NAME}"'",
    "GlancePassword": "'"${OVERCLOUD_GLANCE_PASSWORD}"'",
    "HeatPassword": "'"${OVERCLOUD_HEAT_PASSWORD}"'",
    "HypervisorNeutronPhysicalBridge": "'"${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE}"'",
    "HypervisorNeutronPublicInterface": "'"${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE}"'",
    "NeutronBridgeMappings": "'"${OVERCLOUD_BRIDGE_MAPPINGS}"'",
    "NeutronFlatNetworks": "'"${OVERCLOUD_FLAT_NETWORKS}"'",
    "NeutronPassword": "'"${OVERCLOUD_NEUTRON_PASSWORD}"'",
    "NeutronPublicInterface": "'"${NeutronPublicInterface}"'",
    "NovaComputeLibvirtType": "'"${OVERCLOUD_LIBVIRT_TYPE}"'",
    "NovaPassword": "'"${OVERCLOUD_NOVA_PASSWORD}"'",
    "NtpServer": "'"${OVERCLOUD_NTP_SERVER}"'",
    "SwiftHashSuffix": "'"${OVERCLOUD_SWIFT_HASH}"'",
    "SwiftPassword": "'"${OVERCLOUD_SWIFT_PASSWORD}"'",
    "NovaImage": "'"${OVERCLOUD_COMPUTE_ID}"'",
    "SSLCertificate": "'"${OVERCLOUD_SSL_CERT}"'",
    "SSLKey": "'"${OVERCLOUD_SSL_KEY}"'",
    "KeystoneCAKey": "'"${CA_KEY}"'",
    "KeystoneCACertificate": "'"${CA_CERT}"'",
    "KeystoneSigningKey": "'"${SIGNING_KEY}"'",
    "KeystoneSigningCertificate": "'"${SIGNING_CERT}"'"
  }' <<< $ENV_JSON)
# Preserve user supplied buffer size in the environment, defaulting to 100 for VM usage.
ENV_JSON=$(jq '.parameters.MysqlInnodbBufferPoolSize=(.parameters.MysqlInnodbBufferPoolSize | 100)' <<< $ENV_JSON)

### --end
# Options we haven't documented as such
ENV_JSON=$(jq '.parameters += {
    "ImageUpdatePolicy": "'${OVERCLOUD_IMAGE_UPDATE_POLICY}'",
    "NeutronPublicInterfaceDefaultRoute": "'${NeutronPublicInterfaceDefaultRoute}'",
    "NeutronPublicInterfaceIP": "'${NeutronPublicInterfaceIP}'",
    "NeutronPublicInterfaceRawDevice": "'${NeutronPublicInterfaceRawDevice}'",
    "NeutronControlPlaneID": "'${NeutronControlPlaneID}'"
  }
  | {"parameters": {"ControlVirtualInterface": "'${OVERCLOUD_VIRTUAL_INTERFACE}'"}} + .' <<< $ENV_JSON)
### --include

## #. Save the finished environment file.::

jq . > "${HEAT_ENV}" <<< $ENV_JSON

## #. Deploy an overcloud::

make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml \
           COMPUTESCALE=$OVERCLOUD_COMPUTESCALE \
           CONTROLSCALE=$OVERCLOUD_CONTROLSCALE \
##         heat $HEAT_OP -e $TRIPLEO_ROOT/overcloud-env.json \
##             -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
##             -P "ExtraConfig=${OVERCLOUD_EXTRA_CONFIG}" \
##             overcloud

### --end

# This param name will soon change from 'notCompute' --> 'controller'
CONTROLLER_IMAGE_PARAM=notcomputeImage
if [ -e $TRIPLEO_ROOT/tripleo-heat-templates/controller.yaml ] ; then
    CONTROLLER_IMAGE_PARAM=controllerImage
fi

heat $HEAT_OP -e $TRIPLEO_ROOT/overcloud-env.json \
    -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
    -P "ExtraConfig=${OVERCLOUD_EXTRA_CONFIG}" \
    -P "$CONTROLLER_IMAGE_PARAM=${OVERCLOUD_CONTROL_ID}" \
    $STACKNAME

### --include

##    You can watch the console via ``virsh``/``virt-manager`` to observe the PXE
##    boot/deploy process.  After the deploy is complete, the machines will reboot
##    and be available.

## #. While we wait for the stack to come up, build an end user disk image and
##    register it with glance.::

TEST_IMAGE_DIB_EXTRA_ARGS=${TEST_IMAGE_DIB_EXTRA_ARGS:-''} #nodocs
if [ ! -e $TRIPLEO_ROOT/user.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
    USE_CIRROS=${USE_CIRROS:-0} #nodocs
    if [ "$USE_CIRROS" == "0" ] ; then #nodocs
        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST vm $TEST_IMAGE_DIB_EXTRA_ARGS \
            -a $NODE_ARCH -o $TRIPLEO_ROOT/user 2>&1 | tee $TRIPLEO_ROOT/dib-user.log
### --end
    else
        VERSION=$($TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/version/released >(cat) 1>&2)
        IMAGE_ID=cirros-${VERSION}-${NODE_ARCH/amd64/x86_64}-disk.img
        MD5SUM=$($TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/${VERSION}/MD5SUMS >(cat) 1>&2 | awk '/$IMAGE_ID/ {print $1}')
        $TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/${VERSION}/${IMAGE_ID} $TRIPLEO_ROOT/user.qcow2}
        pushd $TRIPLEO_ROOT
        echo "$MD5SUM user.qcow2" | md5sum --check -
        popd
    fi
fi
### --include
## #. Get the overcloud IP from 'nova list'
##    ::

echo "Waiting for the overcloud stack to be ready" #nodocs
# Make time out 60 mins as like the Heat stack-create default timeout.
wait_for_stack_ready 360 10 $STACKNAME
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
        --ceilometer-password $OVERCLOUD_CEILOMETER_PASSWORD \
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
