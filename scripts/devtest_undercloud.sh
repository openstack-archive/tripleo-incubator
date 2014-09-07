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
    echo "Deploys a baremetal cloud via heat."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo "      --build-only   -- build the needed images but don't deploy them."
    echo "      --heat-env     -- path to a JSON heat environment file."
    echo "                        Defaults to \$TRIPLEO_ROOT/undercloud-env.json."
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
USE_CACHE=${USE_CACHE:-0}
TE_DATAFILE=${1:?"A test environment description is required as \$1."}
UNDERCLOUD_DIB_EXTRA_ARGS=${UNDERCLOUD_DIB_EXTRA_ARGS:-'rabbitmq-server'}

if [ "${USE_MARIADB:-}" = 1 ] ; then
    UNDERCLOUD_DIB_EXTRA_ARGS="$UNDERCLOUD_DIB_EXTRA_ARGS mariadb-rpm"
fi

### --include
## devtest_undercloud
## ==================

## #. Specify whether to use the nova-baremetal or nova-ironic drivers
##    for provisioning within the undercloud.
##    ::

if [ "$USE_IRONIC" -eq 0 ] ; then
    UNDERCLOUD_DIB_EXTRA_ARGS="$UNDERCLOUD_DIB_EXTRA_ARGS nova-baremetal"
else
    UNDERCLOUD_DIB_EXTRA_ARGS="$UNDERCLOUD_DIB_EXTRA_ARGS nova-ironic"
fi

## #. Add extra elements for Undercloud UI
##    ::

if [ "$USE_UNDERCLOUD_UI" -ne 0 ] ; then
    UNDERCLOUD_DIB_EXTRA_ARGS="$UNDERCLOUD_DIB_EXTRA_ARGS ceilometer-collector \
        ceilometer-api ceilometer-agent-central ceilometer-agent-notification \
        ceilometer-undercloud-config horizon"
fi

## #. Specifiy a client-side timeout in minutes for creating or updating the
##    undercloud Heat stack.
##    ::

UNDERCLOUD_STACK_TIMEOUT=${UNDERCLOUD_STACK_TIMEOUT:-60}

## #. Create your undercloud image. This is the image that the seed nova
##    will deploy to become the baremetal undercloud. $UNDERCLOUD_DIB_EXTRA_ARGS is
##    meant to be used to pass additional arguments to disk-image-create.
##    ::

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)
if [ ! -e $TRIPLEO_ROOT/undercloud.qcow2 -o "$USE_CACHE" == "0" ] ; then #nodocs
$TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create $NODE_DIST \
    -a $NODE_ARCH -o $TRIPLEO_ROOT/undercloud \
    ntp baremetal boot-stack os-collect-config dhcp-all-interfaces \
    neutron-dhcp-agent $DIB_COMMON_ELEMENTS $UNDERCLOUD_DIB_EXTRA_ARGS 2>&1 | \
    tee $TRIPLEO_ROOT/dib-undercloud.log
### --end
fi
if [ -n "$BUILD_ONLY" ]; then
  exit 0
fi
### --include

## #. If you wanted to build the image and run it elsewhere, you can stop at
##    this point and head onto the overcloud image building.

## #. Load the undercloud image into Glance:
##    ::

UNDERCLOUD_ID=$(load-image -d $TRIPLEO_ROOT/undercloud.qcow2)


## #. Set the public interface of the undercloud network node:
##    ::

NeutronPublicInterface=${NeutronPublicInterface:-'eth0'}

## #. Set the NTP server for the undercloud::
##    ::

UNDERCLOUD_NTP_SERVER=${UNDERCLOUD_NTP_SERVER:-''}

## #. Create secrets for the cloud. The secrets will be written to a file
##    ($TRIPLEO_ROOT/tripleo-undercloud-passwords by default)
##    that you need to source into your shell environment.
##    
##    .. note::
##      
##      You can also make or change these later and
##      update the heat stack definition to inject them - as long as you also
##      update the keystone recorded password.
##      
##    .. note::
##      
##      There will be a window between updating keystone and
##      instances where they will disagree and service will be down. Instead
##      consider adding a new service account and changing everything across
##      to it, then deleting the old account after the cluster is updated.
##      
##    ::

### --end
if [ -e tripleo-undercloud-passwords ]; then
  echo "Re-using existing passwords in $PWD/tripleo-undercloud-passwords"
  # Add any new passwords since the file was generated
  setup-undercloud-passwords tripleo-undercloud-passwords
  source tripleo-undercloud-passwords
else
### --include
  setup-undercloud-passwords $TRIPLEO_ROOT/tripleo-undercloud-passwords
  source $TRIPLEO_ROOT/tripleo-undercloud-passwords
fi #nodocs

## #. Export UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD to your environment
##    so it can be applied to the SNMPd of all Overcloud nodes.

NEW_JSON=$(jq '.undercloud.ceilometer_snmpd_password="'${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}'"' $TE_DATAFILE)
echo $NEW_JSON > $TE_DATAFILE

## #. Pull out needed variables from the test environment definition.
##    ::

POWER_MANAGER=$(os-apply-config -m $TE_DATAFILE --key power_manager --type raw)
POWER_KEY=$(os-apply-config -m $TE_DATAFILE --key ssh-key --type raw)
POWER_HOST=$(os-apply-config -m $TE_DATAFILE --key host-ip --type raw)
POWER_USER=$(os-apply-config -m $TE_DATAFILE --key ssh-user --type raw)

## #. Wait for the BM cloud to register BM nodes with the scheduler::

wait_for 60 1 wait_for_hypervisor_stats


## #. We need an environment file to store the parameters we're gonig to give
##    heat.::

HEAT_ENV=${HEAT_ENV:-"${TRIPLEO_ROOT}/undercloud-env.json"}

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

## #. Nova-baremetal and Ironic require different Heat templates
##    and different options.
##    ::

if [ "$USE_IRONIC" -eq 0 ] ; then
    HEAT_UNDERCLOUD_TEMPLATE="undercloud-vm.yaml"
    ENV_JSON=$(jq .parameters.PowerSSHHost=\"${POWER_HOST}\" <<< $ENV_JSON)
    ENV_JSON=$(jq .parameters.PowerManager=\"${POWER_MANAGER}\" <<< $ENV_JSON)
    ENV_JSON=$(jq .parameters.PowerUserName=\"${POWER_USER}\" <<< $ENV_JSON)
    REGISTER_SERVICE_OPTS=""
else
    HEAT_UNDERCLOUD_TEMPLATE="undercloud-vm-ironic.yaml"
    ENV_JSON=$(jq .parameters.IronicPassword=\"${UNDERCLOUD_IRONIC_PASSWORD}\" <<< $ENV_JSON)
    if [ "$USE_IRONIC_NOVA_DRIVER" -eq 1 ]; then
        ENV_JSON=$(jq .parameters.NovaComputeDriver=\"nova.virt.ironic.driver.IronicDriver\" <<< $ENV_JSON)
        ENV_JSON=$(jq .parameters.NovaSchedulerHostManager=\"nova.scheduler.ironic_host_manager.IronicHostManager\" <<< $ENV_JSON)
    fi
    REGISTER_SERVICE_OPTS="--ironic-password $UNDERCLOUD_IRONIC_PASSWORD"
fi

STACKNAME_UNDERCLOUD=${STACKNAME_UNDERCLOUD:-'undercloud'}

## #. Choose whether to deploy or update. Use stack-update to update::
##    HEAT_OP=stack-create
##    ::

if heat stack-show $STACKNAME_UNDERCLOUD > /dev/null; then
    HEAT_OP=stack-update
    if (heat stack-show $STACKNAME_UNDERCLOUD | grep -q FAILED); then
        echo "Cannot update a failed stack" >&2
        exit 1
    fi
else
    HEAT_OP=stack-create
fi

## #. Set parameters we need to deploy a baremetal undercloud::

ENV_JSON=$(jq '.parameters = {
    "MysqlInnodbBufferPoolSize": 100
  } + .parameters + {
    "AdminPassword": "'"${UNDERCLOUD_ADMIN_PASSWORD}"'",
    "AdminToken": "'"${UNDERCLOUD_ADMIN_TOKEN}"'",
    "SnmpdReadonlyUserPassword": "'"${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}"'",
    "GlancePassword": "'"${UNDERCLOUD_GLANCE_PASSWORD}"'",
    "HeatPassword": "'"${UNDERCLOUD_HEAT_PASSWORD}"'",
    "NovaPassword": "'"${UNDERCLOUD_NOVA_PASSWORD}"'",
    "NeutronPassword": "'"${UNDERCLOUD_NEUTRON_PASSWORD}"'",
    "NeutronPublicInterface": "'"${NeutronPublicInterface}"'",
    "undercloudImage": "'"${UNDERCLOUD_ID}"'",
    "BaremetalArch": "'"${NODE_ARCH}"'",
    "PowerSSHPrivateKey": "'"${POWER_KEY}"'",
    "NtpServer": "'"${UNDERCLOUD_NTP_SERVER}"'"
  }' <<< $ENV_JSON)

#Add Ceilometer to env only if USE_UNDERCLOUD_UI is specified

if [ "$USE_UNDERCLOUD_UI" -ne 0 ] ; then
    ENV_JSON=$(jq '.parameters = .parameters + {
        "CeilometerPassword": "'"${UNDERCLOUD_CEILOMETER_PASSWORD}"'"
      }' <<< $ENV_JSON)
fi

## #. Save the finished environment file.::

jq . > "${HEAT_ENV}" <<< $ENV_JSON
chmod 0600 "${HEAT_ENV}"

## #. Add Keystone certs/key into the environment file.::

generate-keystone-pki --heatenv $HEAT_ENV

## #. Deploy an undercloud.
##    ::

make -C $TRIPLEO_ROOT/tripleo-heat-templates $HEAT_UNDERCLOUD_TEMPLATE

heat $HEAT_OP -e $HEAT_ENV \
    -t 360 \
    -f $TRIPLEO_ROOT/tripleo-heat-templates/$HEAT_UNDERCLOUD_TEMPLATE \
    $STACKNAME_UNDERCLOUD

##    You can watch the console via ``virsh``/``virt-manager`` to observe the PXE
##    boot/deploy process.  After the deploy is complete, it will reboot into the
##    image.
## 
## #. Get the undercloud IP from ``nova list``
##    ::

echo "Waiting for the undercloud stack to be ready" #nodocs
# Make time out 60 mins as like the Heat stack-create default timeout.
wait_for_stack_ready $(($UNDERCLOUD_STACK_TIMEOUT * 60 / 10)) 10 undercloud
UNDERCLOUD_IP=$(nova list | grep ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

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

init-keystone -o $UNDERCLOUD_IP -t $UNDERCLOUD_ADMIN_TOKEN \
    -e admin@example.com -p $UNDERCLOUD_ADMIN_PASSWORD -u heat-admin

# Creating these roles to be used by tenants using swift
keystone role-create --name=swiftoperator
keystone role-create --name=ResellerAdmin


# Create service endpoints and optionally include Ceilometer for UI support
ENDPOINT_LIST="--glance-password $UNDERCLOUD_GLANCE_PASSWORD
    --heat-password $UNDERCLOUD_HEAT_PASSWORD
    --neutron-password $UNDERCLOUD_NEUTRON_PASSWORD
    --nova-password $UNDERCLOUD_NOVA_PASSWORD
    --tuskar-password $UNDERCLOUD_TUSKAR_PASSWORD"

if [ "$USE_UNDERCLOUD_UI" -ne 0 ] ; then
    ENDPOINT_LIST="$ENDPOINT_LIST --ceilometer-password $UNDERCLOUD_CEILOMETER_PASSWORD"
fi

setup-endpoints $UNDERCLOUD_IP $ENDPOINT_LIST $REGISTER_SERVICE_OPTS
keystone role-create --name heat_stack_user

user-config

BM_NETWORK_CIDR=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.cidr --type raw --key-default '192.0.2.0/24')
BM_NETWORK_GATEWAY=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.gateway-ip --type raw --key-default '192.0.2.1')
BM_NETWORK_UNDERCLOUD_RANGE_START=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.undercloud.range-start --type raw --key-default '192.0.2.21')
BM_NETWORK_UNDERCLOUD_RANGE_END=$(os-apply-config -m $TE_DATAFILE --key baremetal-network.undercloud.range-end --type raw --key-default '192.0.2.40')
UNDERCLOUD_NAMESERVER=$(os-apply-config -m $TE_DATAFILE --key undercloud.nameserver --type netaddress --key-default '')
setup-neutron $BM_NETWORK_UNDERCLOUD_RANGE_START $BM_NETWORK_UNDERCLOUD_RANGE_END $BM_NETWORK_CIDR $BM_NETWORK_GATEWAY $UNDERCLOUD_IP ctlplane $UNDERCLOUD_NAMESERVER

## #. Nova quota runs up with the defaults quota so overide the default to
##    allow unlimited cores, instances and ram.
##    ::

nova quota-update --cores -1 --instances -1 --ram -1 $(keystone tenant-get admin | awk '$2=="id" {print $4}')

## #. Register two baremetal nodes with your undercloud.
##    ::

setup-baremetal --service-host undercloud --nodes <(jq '.nodes - [.nodes[0]]' $TE_DATAFILE)

### --end
