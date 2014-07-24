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

TEMP=$(getopt -o h -l build-only,heat-env:,help -n $SCRIPT_NAME -- "$@")
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
OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server cinder-tgt'}
OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS=${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:-''}
TE_DATAFILE=${TE_DATAFILE:?"TE_DATAFILE must be defined before calling this script!"}

if [ "${USE_MARIADB:-}" = 1 ] ; then
    OVERCLOUD_CONTROL_DIB_EXTRA_ARGS="$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS mariadb-rpm"
    OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS="$OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS mariadb-dev-rpm"
elif [ "${USE_PERCONA:-}" = 1 ] ; then
    OVERCLOUD_CONTROL_DIB_EXTRA_ARGS="$OVERCLOUD_CONTROL_DIB_EXTRA_ARGS percona"
fi

# A client-side timeout in minutes for creating or updating the overcloud
# Heat stack.
OVERCLOUD_STACK_TIMEOUT=${OVERCLOUD_STACK_TIMEOUT:-60}

# The private instance fixed IP network range
OVERCLOUD_FIXED_RANGE_CIDR=${OVERCLOUD_FIXED_RANGE_CIDR:-"10.0.0.0/8"}

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
        baremetal boot-stack cinder-api cinder-volume ceilometer-collector \
        ceilometer-api ceilometer-agent-central ceilometer-agent-notification \
        os-collect-config horizon neutron-network-node dhcp-all-interfaces \
        swift-proxy swift-storage keepalived haproxy \
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
wait_for 60 1 wait_for_hypervisor_stats $expected_nodes

## #. Set password for Overcloud SNMPd, same password needs to be set in Undercloud Ceilometer

UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD=${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD:-''}

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
### --end
    if [ "$(stat -c %a ${HEAT_ENV})" != "600" ]; then
        echo "Error: Heat environment cache \"${HEAT_ENV}\" not set to permissions of 0600."
# We should exit 1 so all the users from before the permissions
# requirement dont have their HEAT_ENV files ignored in a nearly silent way
        exit 1
    fi
### --include
    ENV_JSON=$(cat "${HEAT_ENV}")
else
    ENV_JSON='{"parameters":{}}'
fi

## #. Set parameters we need to deploy a KVM cloud.::

ENV_JSON=$(jq '.parameters = {
    "MysqlInnodbBufferPoolSize": 100
  } + .parameters + {
    "AdminPassword": "'"${OVERCLOUD_ADMIN_PASSWORD}"'",
    "AdminToken": "'"${OVERCLOUD_ADMIN_TOKEN}"'",
    "CeilometerPassword": "'"${OVERCLOUD_CEILOMETER_PASSWORD}"'",
    "CeilometerMeteringSecret": "'"${OVERCLOUD_CEILOMETER_SECRET}"'",
    "CinderPassword": "'"${OVERCLOUD_CINDER_PASSWORD}"'",
    "CloudName": "'"${OVERCLOUD_NAME}"'",
    "controllerImage": "'"${OVERCLOUD_CONTROL_ID}"'",
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
    "SSLKey": "'"${OVERCLOUD_SSL_KEY}"'"
  }' <<< $ENV_JSON)

### --end
# Options we haven't documented as such
NeutronControlPlaneID=$(neutron net-show ctlplane | grep ' id ' | awk '{print $4}')
ENV_JSON=$(jq '.parameters = {
    "ControlVirtualInterface": "'${OVERCLOUD_VIRTUAL_INTERFACE}'"
  } + .parameters + {
    "NeutronPublicInterfaceDefaultRoute": "'${NeutronPublicInterfaceDefaultRoute}'",
    "NeutronPublicInterfaceIP": "'${NeutronPublicInterfaceIP}'",
    "NeutronPublicInterfaceRawDevice": "'${NeutronPublicInterfaceRawDevice}'",
    "NeutronControlPlaneID": "'${NeutronControlPlaneID}'",
    "SnmpdReadonlyUserPassword": "'${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}'",
  }' <<< $ENV_JSON)

### --include

## #. Save the finished environment file.::

jq . > "${HEAT_ENV}" <<< $ENV_JSON
chmod 0600 "${HEAT_ENV}"

## #. Add Keystone certs/key into the environment file.::

generate-keystone-pki --heatenv $HEAT_ENV

## #. Deploy an overcloud::

make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml \
           COMPUTESCALE=$OVERCLOUD_COMPUTESCALE \
           CONTROLSCALE=$OVERCLOUD_CONTROLSCALE \
##         heat $HEAT_OP -e $TRIPLEO_ROOT/overcloud-env.json \
##             -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
##             -P "ExtraConfig=${OVERCLOUD_EXTRA_CONFIG}" \
##             overcloud

### --end


# create stack with a 6 hour timeout, and allow wait_for_stack_ready
# to impose a realistic timeout.
heat $HEAT_OP -e $TRIPLEO_ROOT/overcloud-env.json \
    -t 360 \
    -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
    -P "ExtraConfig=${OVERCLOUD_EXTRA_CONFIG}" \
    $STACKNAME

### --include

##    You can watch the console via ``virsh``/``virt-manager`` to observe the PXE
##    boot/deploy process.  After the deploy is complete, the machines will reboot
##    and be available.

## #. While we wait for the stack to come up, build an end user disk image and
##    register it with glance.::

USER_IMG_NAME="user.qcow2"
### --end
USE_CIRROS=${USE_CIRROS:-0}
if [ "$USE_CIRROS" != "0" ]; then
    USER_IMG_NAME="user-cirros.qcow2"
fi

TEST_IMAGE_DIB_EXTRA_ARGS=${TEST_IMAGE_DIB_EXTRA_ARGS:-''}
if [ ! -e $TRIPLEO_ROOT/$USER_IMG_NAME -o "$USE_CACHE" == "0" ] ; then
    if [ "$USE_CIRROS" == "0" ] ; then
### --include
        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST vm $TEST_IMAGE_DIB_EXTRA_ARGS \
            -a $NODE_ARCH -o $TRIPLEO_ROOT/user 2>&1 | tee $TRIPLEO_ROOT/dib-user.log
### --end
    else
        VERSION=$($TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/version/released >(cat) 1>&2)
        IMAGE_ID=cirros-${VERSION}-${NODE_ARCH/amd64/x86_64}-disk.img
        MD5SUM=$($TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/${VERSION}/MD5SUMS >(cat) 1>&2 | awk "/$IMAGE_ID/ {print \$1}")
        $TRIPLEO_ROOT/diskimage-builder/elements/cache-url/bin/cache-url \
            http://download.cirros-cloud.net/${VERSION}/${IMAGE_ID} $TRIPLEO_ROOT/$USER_IMG_NAME
        pushd $TRIPLEO_ROOT
        echo "$MD5SUM *$USER_IMG_NAME" | md5sum --check -
        popd
    fi
fi
### --include
## #. Get the overcloud IP from 'nova list'
##    ::

echo "Waiting for the overcloud stack to be ready" #nodocs
wait_for_stack_ready $(($OVERCLOUD_STACK_TIMEOUT * 60 / 10)) 10 $STACKNAME
OVERCLOUD_ENDPOINT=$(heat output-show $STACKNAME KeystoneURL|sed 's/^"\(.*\)"$/\1/')
OVERCLOUD_IP=$(echo $OVERCLOUD_ENDPOINT | awk -F '[/:]' '{print $4}')
### --end
# If we're forcing a specific public interface, we'll want to advertise that as
# the public endpoint for APIs.
if [ -n "$NeutronPublicInterfaceIP" ]; then
    OVERCLOUD_IP=$(echo ${NeutronPublicInterfaceIP} | sed -e s,/.*,,)
    OVERCLOUD_ENDPOINT="http://$OVERCLOUD_IP:5000/v2.0"
fi

### --include

## #. We don't (yet) preserve ssh keys on rebuilds.
##    ::

ssh-keygen -R $OVERCLOUD_IP

## #. Export the overcloud endpoint and credentials to your test environment.
##    ::

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

    init-keystone -o $OVERCLOUD_IP -t $OVERCLOUD_ADMIN_TOKEN \
        -e admin.example.com -p $OVERCLOUD_ADMIN_PASSWORD -u heat-admin \
        ${SSLBASE:+-s $PUBLIC_API_URL}
    # Creating these roles to be used by tenants using swift
    keystone role-create --name=swiftoperator
    keystone role-create --name=ResellerAdmin
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
    user-config
##             setup-neutron "" "" 10.0.0.0/8 "" "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24
    setup-neutron "" "" $OVERCLOUD_FIXED_RANGE_CIDR "" "" "" $FLOATING_START $FLOATING_END $FLOATING_CIDR #nodocs

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
        --container-format bare --file $TRIPLEO_ROOT/$USER_IMG_NAME

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
