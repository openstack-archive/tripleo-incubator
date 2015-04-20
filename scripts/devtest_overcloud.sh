#!/bin/bash

set -eu
set -o pipefail

SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

BUILD_ONLY=
DEBUG_LOGGING=
HEAT_ENV=
DISK_IMAGES_CONFIG=${OVERCLOUD_DISK_IMAGES_CONFIG:-''}
COMPUTE_FLAVOR="baremetal"
CONTROL_FLAVOR="baremetal"
BLOCKSTORAGE_FLAVOR="baremetal"
SWIFTSTORAGE_FLAVOR="baremetal"

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Deploys a KVM cloud via heat."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo "      -c             -- re-use existing source/images if they exist."
    echo "      --build-only   -- build the needed images but don't deploy them."
    echo "      --no-mergepy   -- use the standalone Heat templates (default)."
    echo "      --debug-logging -- Turn on debug logging in the built overcloud."
    echo "                         Sets both OS_DEBUG_LOGGING and the heat Debug parameter."
    echo "      --heat-env     -- path to a JSON heat environment file."
    echo "                        Defaults to \$TRIPLEO_ROOT/overcloud-env.json."
    echo "       --compute-flavor -- Nova flavor to use for compute nodes."
    echo "                           Defaults to 'baremetal'."
    echo "       --control-flavor -- Nova flavor to use for control nodes."
    echo "                           Defaults to 'baremetal'."
    echo "       --block-storage-flavor -- Nova flavor to use for block "
    echo "                                 storage nodes."
    echo "                                 Defaults to 'baremetal'."
    echo "       --swift-storage-flavor -- Nova flavor to use for swift "
    echo "                                 storage nodes."
    echo "                                 Defaults to 'baremetal'."
    echo
    exit $1
}

TEMP=$(getopt -o c,h -l build-only,no-mergepy,debug-logging,heat-env:,compute-flavor:,control-flavor:,block-storage-flavor:,swift-storage-flavor:,help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then
    echo "Terminating..." >&2;
    exit 1;
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -c) USE_CACHE=1; shift 1;;
        --build-only) BUILD_ONLY="1"; shift 1;;
        --no-mergepy)
            USE_MERGEPY=0
            echo "Warning: --no-mergepy is the default now, option is DEPRECATED" >&2
            shift 1
            ;;
        --debug-logging)
            DEBUG_LOGGING="1"
            export OS_DEBUG_LOGGING="1"
            shift 1
            ;;
        --heat-env) HEAT_ENV="$2"; shift 2;;
        --disk-images-config) DISK_IMAGES_CONFIG="$2"; shift 2;;
        --compute-flavor) COMPUTE_FLAVOR="$2"; shift 2;;
        --control-flavor) CONTROL_FLAVOR="$2"; shift 2;;
        --block-storage-flavor) BLOCKSTORAGE_FLAVOR="$2"; shift 2;;
        --swift-storage-flavor) SWIFTSTORAGE_FLAVOR="$2"; shift 2;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

set -x

### --include
## devtest_overcloud
## =================

## #. Build images. There are two helper scripts which can be
##    used to build images. The first method uses environment
##    variables to create a specific image for each overcloud
##    role. This method works best if you are using tripleo-image-elements
##    for configuration (which requires per role image customization).
##    See :doc:`devtest_overcloud_images` for documentation.
##    This method is currently the default.


##    Another option is to make use of the build-images script which
##    dynamically creates a set of images using a YAML (or JSON) config
##    file (see the build-images script for details and the expected config
##    file format). This method is typically preferred when using
##    tripleo-puppet-elements (Puppet) for configuration which
##    allows the contents and number of images used to deploy an
##    overcloud to be more flexibly defined. Example:

##         build-images -d -c $DISK_IMAGES_CONFIG

### --end
USE_CACHE=${USE_CACHE:-0}
if [ -n "$DISK_IMAGES_CONFIG" ]; then
    USE_CACHE=$USE_CACHE build-images -d -c $DISK_IMAGES_CONFIG
else
    USE_CACHE=$USE_CACHE devtest_overcloud_images.sh
    # use a default disk images YAML file to load images
    DISK_IMAGES_CONFIG="$TRIPLEO_ROOT/tripleo-incubator/scripts/overcloud_disk_images.yaml"
fi
if [ -n "$BUILD_ONLY" ]; then
    echo "--build-only is deprecated. Please use devtest_overcloud_images.sh instead."
    exit 0
fi


OS_PASSWORD=${OS_PASSWORD:?"OS_PASSWORD is not set. Undercloud credentials are required"}

# Parameters for tripleo-cd - see the tripleo-cd element.
# NOTE(rpodolyaka): retain backwards compatibility by accepting both positional
#                   arguments and environment variables. Positional arguments
#                   take precedence over environment variables
NeutronPublicInterface=${1:-${NeutronPublicInterface:-'nic1'}}
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
TE_DATAFILE=${TE_DATAFILE:?"TE_DATAFILE must be defined before calling this script!"}

# A client-side timeout in minutes for creating or updating the overcloud
# Heat stack.
OVERCLOUD_STACK_TIMEOUT=${OVERCLOUD_STACK_TIMEOUT:-60}

# The private instance fixed IP network range
OVERCLOUD_FIXED_RANGE_CIDR=${OVERCLOUD_FIXED_RANGE_CIDR:-"10.0.0.0/8"}
OVERCLOUD_FIXED_RANGE_GATEWAY=${OVERCLOUD_FIXED_RANGE_GATEWAY:-"10.0.0.1"}
OVERCLOUD_FIXED_RANGE_NAMESERVER=${OVERCLOUD_FIXED_RANGE_NAMESERVER:-"8.8.8.8"}

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)

### --include

## #. Load all images into Glance (based on the provided disk images config).
##    This captures all the Glance IDs into a Heat env file which maps
##    them to the appropriate parameter names. This allows us some
##    amount of flexability how many images to use for the overcloud
##    deployment.
##    ::

OVERCLOUD_IMAGE_IDS_ENV=${OVERCLOUD_IMAGE_IDS_ENV:-"${TRIPLEO_ROOT}/overcloud-images-env.yaml"}
load-images -d --remove -c $DISK_IMAGES_CONFIG -o $OVERCLOUD_IMAGE_IDS_ENV

## #. For running an overcloud in VM's. For Physical machines, set to kvm:
##    ::

OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-"qemu"}

## #. Set the public interface of overcloud network node::
##    ::

NeutronPublicInterface=${NeutronPublicInterface:-'nic1'}

## #. Set the NTP server for the overcloud::
##    ::

OVERCLOUD_NTP_SERVER=${OVERCLOUD_NTP_SERVER:-''}

## #. If you want to permit VM's access to bare metal networks, you need
##    to define flat-networks and bridge mappings in Neutron. We default
##    to creating one called datacentre, which we use to grant external
##    network access to VMs::
##    ::

OVERCLOUD_FLAT_NETWORKS=${OVERCLOUD_FLAT_NETWORKS:-'datacentre'}
OVERCLOUD_BRIDGE_MAPPINGS=${OVERCLOUD_BRIDGE_MAPPINGS:-'datacentre:br-ex'}
OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE=${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE:-'br-ex'}
OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE=${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE:-'nic1'}
OVERCLOUD_VIRTUAL_INTERFACE=${OVERCLOUD_VIRTUAL_INTERFACE:-'br-ex'}

## #. If you are using SSL, your compute nodes will need static mappings to your
##    endpoint in ``/etc/hosts`` (because we don't do dynamic undercloud DNS yet).
##    set this to the DNS name you're using for your SSL certificate - the heat
##    template looks up the controller address within the cloud::

OVERCLOUD_NAME=${OVERCLOUD_NAME:-''}

## #. Detect if we are deploying with a VLAN for API endpoints / floating IPs.
##    This is done by looking for a 'public' network in Neutron, and if found
##    we pull out the VLAN id and pass that into Heat, as well as using a VLAN
##    enabled Heat template.
##    ::

if (neutron net-list | grep -q public); then
    VLAN_ID=$(neutron net-show public | awk '/provider:segmentation_id/ { print $4 }')
    NeutronPublicInterfaceTag="$VLAN_ID"
    # This should be in the heat template, but see
    # https://bugs.launchpad.net/heat/+bug/1336656
    # note that this will break if there are more than one subnet, as if
    # more reason to fix the bug is needed :).
    PUBLIC_SUBNET_ID=$(neutron net-show public | awk '/subnets/ { print $4 }')
    VLAN_GW=$(neutron subnet-show $PUBLIC_SUBNET_ID | awk '/gateway_ip/ { print $4}')
    BM_VLAN_CIDR=$(neutron subnet-show $PUBLIC_SUBNET_ID | awk '/cidr/ { print $4}')
    NeutronPublicInterfaceDefaultRoute="${VLAN_GW}"
    export CONTROLEXTRA=overcloud-vlan-port.yaml
else
    VLAN_ID=
    NeutronPublicInterfaceTag=
fi

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
        echo "Updating a failed stack; this is a new ability and may cause problems." >&2
    fi
else
    HEAT_OP=stack-create
fi

### --include

## #. Wait for the BM cloud to register BM nodes with the scheduler::

expected_nodes=$(( $OVERCLOUD_COMPUTESCALE + $OVERCLOUD_CONTROLSCALE + $OVERCLOUD_BLOCKSTORAGESCALE ))
wait_for -w $((60 * $expected_nodes)) --delay 10 -- wait_for_hypervisor_stats $expected_nodes

## #. Set password for Overcloud SNMPd, same password needs to be set in Undercloud Ceilometer

UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD=$(os-apply-config -m $TE_DATAFILE --key undercloud.ceilometer_snmpd_password --type raw --key-default '')
if [ -z "$UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD" ]; then #nodocs
    UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD=$(os-make-password)
fi #nodocs

## #. Create unique credentials::

### --end
# NOTE(tchaypo): We used to write these passwords in $CWD; so check to see
# if the file exists there first. As well as providing backwards
# compatibility, this allows for people to run multiple test environments on
# the same machine - just make sure to have a different directory for
# running the scripts for each different environment you wish to use.
#
# If we can't find the file in $CWD we look in the new default location.
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

NeutronControlPlaneID=$(neutron net-show ctlplane | grep ' id ' | awk '{print $4}')
ENV_JSON=$(jq '.parameters = {
"MysqlInnodbBufferPoolSize": 100
} + .parameters + {
"AdminPassword": "'"${OVERCLOUD_ADMIN_PASSWORD}"'",
"AdminToken": "'"${OVERCLOUD_ADMIN_TOKEN}"'",
"CeilometerPassword": "'"${OVERCLOUD_CEILOMETER_PASSWORD}"'",
"CeilometerMeteringSecret": "'"${OVERCLOUD_CEILOMETER_SECRET}"'",
"CinderPassword": "'"${OVERCLOUD_CINDER_PASSWORD}"'",
"CloudName": "'"${OVERCLOUD_NAME}"'",
"GlancePassword": "'"${OVERCLOUD_GLANCE_PASSWORD}"'",
"HeatPassword": "'"${OVERCLOUD_HEAT_PASSWORD}"'",
"HeatStackDomainAdminPassword":  "'"${OVERCLOUD_HEAT_STACK_DOMAIN_PASSWORD}"'",
"HypervisorNeutronPhysicalBridge": "'"${OVERCLOUD_HYPERVISOR_PHYSICAL_BRIDGE}"'",
"HypervisorNeutronPublicInterface": "'"${OVERCLOUD_HYPERVISOR_PUBLIC_INTERFACE}"'",
"NeutronBridgeMappings": "'"${OVERCLOUD_BRIDGE_MAPPINGS}"'",
"NeutronControlPlaneID": "'${NeutronControlPlaneID}'",
"NeutronFlatNetworks": "'"${OVERCLOUD_FLAT_NETWORKS}"'",
"NeutronPassword": "'"${OVERCLOUD_NEUTRON_PASSWORD}"'",
"NeutronPublicInterface": "'"${NeutronPublicInterface}"'",
"NeutronPublicInterfaceTag": "'"${NeutronPublicInterfaceTag}"'",
"NovaComputeLibvirtType": "'"${OVERCLOUD_LIBVIRT_TYPE}"'",
"NovaPassword": "'"${OVERCLOUD_NOVA_PASSWORD}"'",
"NtpServer": "'"${OVERCLOUD_NTP_SERVER}"'",
"SwiftHashSuffix": "'"${OVERCLOUD_SWIFT_HASH}"'",
"SwiftPassword": "'"${OVERCLOUD_SWIFT_PASSWORD}"'",
"SSLCertificate": "'"${OVERCLOUD_SSL_CERT}"'",
"SSLKey": "'"${OVERCLOUD_SSL_KEY}"'",
"OvercloudComputeFlavor": "'"${COMPUTE_FLAVOR}"'",
"OvercloudControlFlavor": "'"${CONTROL_FLAVOR}"'",
"OvercloudBlockStorageFlavor": "'"${BLOCKSTORAGE_FLAVOR}"'",
"OvercloudSwiftStorageFlavor": "'"${SWIFTSTORAGE_FLAVOR}"'"
}' <<< $ENV_JSON)

### --end
if [ "$DEBUG_LOGGING" = "1" ]; then
    ENV_JSON=$(jq '.parameters = .parameters + {
    "Debug": "True",
    }' <<< $ENV_JSON)
fi
### --include


## #. We enable the automatic relocation of L3 routers in Neutron by default,
##    alternatively you can use the L3 agents high availability mechanism
##    (only works with three or more controller nodes) or the distributed virtul
##    routing mechanism (deploying routers on compute nodes).  Set the environment
##    variable ``OVERCLOUD_L3`` to ``relocate``, ``ha`` or ``dvr``.
##    ::

OVERCLOUD_L3=${OVERCLOUD_L3:-'relocate'}

## #. If enabling distributed virtual routing on the overcloud, some values need
##    to be set so that Neutron DVR will work.
##    ::

if [ ${OVERCLOUD_DISTRIBUTED_ROUTERS:-'False'} == "True" -o $OVERCLOUD_L3 == "dvr" ]; then
    ENV_JSON=$(jq '.parameters = {} + .parameters + {
    "NeutronDVR": "True",
    "NeutronTunnelTypes": "vxlan",
    "NeutronNetworkType": "vxlan",
    "NeutronMechanismDrivers": "openvswitch,l2population",
    "NeutronAllowL3AgentFailover": "False",
    }' <<< $ENV_JSON)
fi


if [ ${OVERCLOUD_L3_HA:-'False'} == "True" -o $OVERCLOUD_L3 == "ha" ]; then
    ENV_JSON=$(jq '.parameters = {} + .parameters + {
    "NeutronL3HA": "True",
    "NeutronAllowL3AgentFailover": "False",
    }' <<< $ENV_JSON)
fi

### --end
# Options we haven't documented as such
ENV_JSON=$(jq '.parameters = {
"ControlVirtualInterface": "'${OVERCLOUD_VIRTUAL_INTERFACE}'"
} + .parameters + {
"NeutronPublicInterfaceDefaultRoute": "'${NeutronPublicInterfaceDefaultRoute}'",
"NeutronPublicInterfaceIP": "'${NeutronPublicInterfaceIP}'",
"NeutronPublicInterfaceRawDevice": "'${NeutronPublicInterfaceRawDevice}'",
"SnmpdReadonlyUserPassword": "'${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}'",
}' <<< $ENV_JSON)

RESOURCE_REGISTRY=
RESOURCE_REGISTRY_PATH=${RESOURCE_REGISTRY_PATH:-"$TRIPLEO_ROOT/tripleo-heat-templates/overcloud-resource-registry.yaml"}

if [ "$USE_MERGEPY" -eq 0 ]; then
    RESOURCE_REGISTRY="-e $RESOURCE_REGISTRY_PATH"
    ENV_JSON=$(jq '.parameters = .parameters + {
    "ControllerCount": '${OVERCLOUD_CONTROLSCALE}',
    "ComputeCount": '${OVERCLOUD_COMPUTESCALE}'
    }' <<< $ENV_JSON)
    if [ -e "$TRIPLEO_ROOT/tripleo-heat-templates/cinder-storage.yaml" ]; then
        ENV_JSON=$(jq '.parameters = .parameters + {
        "BlockStorageCount": '${OVERCLOUD_BLOCKSTORAGESCALE}'
        }' <<< $ENV_JSON)
    fi
fi

CUSTOM_HEAT_ENVIRONMENT=
OVERCLOUD_CUSTOM_HEAT_ENV=${OVERCLOUD_CUSTOM_HEAT_ENV:-''}
if [ -n "$OVERCLOUD_CUSTOM_HEAT_ENV" ]; then
  CUSTOM_HEAT_ENVIRONMENT="-e $OVERCLOUD_CUSTOM_HEAT_ENV"
fi

### --include

## #. Save the finished environment file.::

jq . > "${HEAT_ENV}" <<< $ENV_JSON
chmod 0600 "${HEAT_ENV}"

## #. Add Keystone certs/key into the environment file.::

generate-keystone-pki --heatenv $HEAT_ENV

## #. Deploy an overcloud::

##         heat $HEAT_OP -e "$HEAT_ENV" \
##             -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
##             -P "ExtraConfig=${OVERCLOUD_EXTRA_CONFIG}" \
##             overcloud

### --end

if [ "$USE_MERGEPY" -eq 1 ]; then
    make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml \
            COMPUTESCALE=$OVERCLOUD_COMPUTESCALE,${OVERCLOUD_COMPUTE_BLACKLIST:-} \
            CONTROLSCALE=$OVERCLOUD_CONTROLSCALE,${OVERCLOUD_CONTROL_BLACKLIST:-} \
            BLOCKSTORAGESCALE=$OVERCLOUD_BLOCKSTORAGESCALE
    OVERCLOUD_TEMPLATE=$TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml
else
    OVERCLOUD_TEMPLATE=$TRIPLEO_ROOT/tripleo-heat-templates/overcloud-without-mergepy.yaml
fi

# create stack with a 6 hour timeout, and allow wait_for_stack_ready
# to impose a realistic timeout.
heat $HEAT_OP -e "$HEAT_ENV" \
    -e $OVERCLOUD_IMAGE_IDS_ENV \
    $RESOURCE_REGISTRY \
    $CUSTOM_HEAT_ENVIRONMENT \
    -t 360 \
    -f "$OVERCLOUD_TEMPLATE" \
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
## #. Get the overcloud IP from the heat stack
##    ::

echo "Waiting for the overcloud stack to be ready" #nodocs
wait_for_stack_ready -w $(($OVERCLOUD_STACK_TIMEOUT * 60)) 10 $STACKNAME
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
        -e admin@example.com -p $OVERCLOUD_ADMIN_PASSWORD \
        ${SSLBASE:+-s $PUBLIC_API_URL} --no-pki-setup
    # Creating these roles to be used by tenants using swift
    openstack role create swiftoperator
    openstack role create ResellerAdmin
    setup-endpoints $OVERCLOUD_IP \
        --cinder-password $OVERCLOUD_CINDER_PASSWORD \
        --glance-password $OVERCLOUD_GLANCE_PASSWORD \
        --heat-password $OVERCLOUD_HEAT_PASSWORD \
        --neutron-password $OVERCLOUD_NEUTRON_PASSWORD \
        --nova-password $OVERCLOUD_NOVA_PASSWORD \
        --swift-password $OVERCLOUD_SWIFT_PASSWORD \
        --ceilometer-password $OVERCLOUD_CEILOMETER_PASSWORD \
        ${SSLBASE:+--ssl $PUBLIC_API_URL}
    openstack role create heat_stack_user
    user-config
    BM_NETWORK_GATEWAY=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key baremetal-network.gateway-ip --type raw --key-default '192.0.2.1')
    OVERCLOUD_NAMESERVER=$(os-apply-config -m $TE_DATAFILE --key overcloud.nameserver --type netaddress --key-default "$OVERCLOUD_FIXED_RANGE_NAMESERVER")
    NETWORK_JSON=$(mktemp)
    jq "." <<EOF > $NETWORK_JSON
{
    "float": {
        "cidr": "$OVERCLOUD_FIXED_RANGE_CIDR",
        "name": "default-net",
        "nameserver": "$OVERCLOUD_NAMESERVER",
        "segmentation_id": "$NeutronPublicInterfaceTag",
        "physical_network": "datacentre",
        "gateway": "$OVERCLOUD_FIXED_RANGE_GATEWAY"
    },
    "external": {
        "name": "ext-net",
        "cidr": "$FLOATING_CIDR",
        "allocation_start": "$FLOATING_START",
        "allocation_end": "$FLOATING_END",
        "gateway": "$BM_NETWORK_GATEWAY"
    }
}
EOF
    setup-neutron -n $NETWORK_JSON
    rm $NETWORK_JSON

## #. If you want a demo user in your overcloud (probably a good idea).
##    ::

    os-adduser -p $OVERCLOUD_DEMO_PASSWORD demo demo@example.com

## #. Workaround https://bugs.launchpad.net/diskimage-builder/+bug/1211165.
##    ::

    nova flavor-delete m1.tiny
    nova flavor-create m1.tiny 1 512 2 1

## #. Register the end user image with glance.
##    ::

    glance image-create --name user --is-public True --disk-format qcow2 \
        --container-format bare --file $TRIPLEO_ROOT/$USER_IMG_NAME

fi #nodocs

## #. _`Wait for Nova Compute`
##    ::

wait_for -w 300 --delay 10 -- nova service-list --binary nova-compute 2\>/dev/null \| grep 'enabled.*\ up\ '

## #. Wait for L2 Agent On Nova Compute
##    ::

wait_for -w 300 --delay 10 -- neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*-novacompute\"" #nodocs
##         wait_for 30 10 neutron agent-list -f csv -c alive -c agent_type -c host \| grep "\":-).*Open vSwitch agent.*-novacompute\""

## #. Log in as a user.
##    ::

source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc-user

## #. If you just created the cloud you need to add your keypair to your user.
##    ::

if [ "stack-create" = "$HEAT_OP" ] ; then #nodocs
    user-config

## #. So that you can deploy a VM.
##    ::

    IMAGE_ID=$(glance image-show user | awk '/ id / {print $4}')
    nova boot --key-name default --flavor m1.tiny --block-device source=image,id=$IMAGE_ID,dest=volume,size=3,shutdown=preserve,bootindex=0 demo

## #. Add an external IP for it.
##    ::

    wait_for -w 50 --delay 5 -- neutron port-list -f csv -c id --quote none \| grep id
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

wait_for -w 300 --delay 10 -- ping -c 1 $FLOATINGIP

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
