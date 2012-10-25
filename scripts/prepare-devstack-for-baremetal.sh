#/bin/bash

# If something goes wrong bail, don't continue to the end
set -e

# The following variables allow the behaviour of the script to be customised:
# just export them in advance. For instance, to use a different kernel, export
# KERNEL_VER.

DEVSTACK_PATH=${DEVSTACK_PATH:-/home/stack/devstack}
source $DEVSTACK_PATH/openrc
source $DEVSTACK_PATH/localrc

MYSQL_USER=${MYSQL_USER:-root}
MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-secrete}

GLANCE=${GLANCE:-/usr/local/bin/glance}
NOVA=${NOVA:-/usr/local/bin/nova}
NOVA_MANAGE=${NOVA_MANAGE:-/usr/local/bin/nova-manage}

IMG_PATH=${IMG_PATH:-/home/stack/devstack/files}
BM_NODE_NAME=${BM_NODE_NAME:-bare_metal}

KERNEL_VER=${KERNEL_VER:-`uname -r`}

# The deployment bits
BM_DEPLOY_KERNEL=${BM_DEPLOY_KERNEL:-vmlinuz-$KERNEL_VER}
BM_DEPLOY_RAMDISK=${BM_DEPLOY_RAMDISK:-bm-deploy-ramdisk.$KERNEL_VER.img}

# The end user runtime bits
BM_IMAGE=${BM_IMAGE:-bm-node-image.$KERNEL_VER.img}
BM_RUN_KERNEL=${BM_RUN_KERNEL:-$BM_DEPLOY_KERNEL}
BM_RUN_RAMDISK=${BM_RUN_RAMDISK:-$BM_DEPLOY_RAMDISK}

DNSMASQ_IFACE=${DNSMASQ_IFACE:-$PUBLIC_INTERFACE}
DNSMASQ_IFACE=${DNSMASQ_IFACE:-eth0}

# can we get this from localrc? it looks like FIXED_RANGE, but format is different
DNSMASQ_RANGE=${DNSMASQ_RANGE:-192.168.2.33,192.168.2.63}

BM_SCRIPT_PATH=${BM_SCRIPT_PATH:-/opt/stack/nova/bin}
BM_SCRIPT=${BM_SCRIPT:-nova-baremetal-manage}
BM_HELPER=${BM_HELPER:-nova-baremetal-deploy-helper}

BM_SERVICE_HOST_NAME=${BM_SERVICE_HOST_NAME:-`hostname`}
BM_TARGET_MAC=${BM_TARGET_MAC:-01:23:45:67:89:01}
BM_TARGET_CPU=${BM_TARGET_CPU:-x86_64}

PM_ADDR=${PM_ADDR:-1.2.3.4}
PM_USER=${PM_USER:-root}
PM_PASS=${PM_PASS:-secret}


function load_image {
   [ -r $IMG_PATH/$3 ] || die "Can not read image $IMG_PATH/$3"
   out=$($GLANCE --verbose add is_public=true container_format=$1 disk_format=$1 name=$2 < $IMG_PATH/$3)
   [ "$out" ] || die "Failed to load image $3 into glance"
   uuid=$(echo "$out" | head -1 | awk '{print $6}')
   echo $uuid
}

set -o xtrace

# build deployment ramdisk if needed
if [ ! -e $IMG_PATH/$BM_DEPLOY_RAMDISK ]; then
    pushd ~stack/baremetal-initrd-builder
    ./baremetal-mkinitrd.sh $IMG_PATH/$BM_DEPLOY_RAMDISK $KERNEL_VER
    sudo cp /boot/vmlinuz-$KERNEL_VER $IMG_PATH/$BM_DEPLOY_KERNEL
    sudo chmod a+r $IMG_PATH/$BM_DEPLOY_KERNEL
    popd
fi

# fix mysql issues
# TODO: remove after NTT patch lands upstream
# TODO: skip this block if it's already done
sql=<<EOL
GRANT ALL PRIVILEGES ON nova_bm.* TO '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';
EOL

MYSQL=$(which mysql)
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "CREATE DATABASE IF NOT EXISTS nova_bm CHARACTER SET utf8;"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$sql"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -v -v -f nova_bm < $(dirname $0)/init_nova_bm_db.sql

# add keypair... optional step
$NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default

# load images into glance
ami=$(load_image "ami" $BM_NODE_NAME $BM_IMAGE)
aki=$(load_image "aki" "aki-01" $BM_DEPLOY_KERNEL)
ari=$(load_image "ari" "ari-01" $BM_DEPLOY_RAMDISK)

# associate deploy aki and ari to main AMI
$GLANCE image-update --property "deploy_kernel_id=$aki" $ami
$GLANCE image-update --property "deploy_ramdisk_id=$ari" $ami

# load run-time aki and ari, if specified
if [ $BM_RUN_KERNEL != $BM_DEPLOY_KERNEL ]; then
   aki=$(load_image "aki" "aki-02" $BM_RUN_KERNEL)
fi

if [ $BM_RUN_RAMDISK != $BM_DEPLOY_RAMDISK ]; then
   ari=$(load_image "ari" "ari-02" $BM_RUN_RAMDISK)
fi

# associate run-time aki and ari to main AMI
$GLANCE image-update --property "kernel_id=$aki" $ami
$GLANCE image-update --property "ramdisk_id=$ari" $ami

# create instance type (aka flavor)
$NOVA_MANAGE instance_type create --name=$BM_NODE_NAME --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=99 --swap=0 --rxtx_factor=1
$NOVA_MANAGE instance_type set_key --name=$BM_NODE_NAME --key cpu_arch --value "$BM_TARGET_CPU"

# restart dnsmasq
sudo pkill dnsmasq || true
sudo dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --interface=$DNSMASQ_IFACE --dhcp-range=$DNSMASQ_RANGE

# make sure deploy server is running
[ $(pgrep -f "$BM_HELPER") ] || $BM_SCRIPT_PATH/$BM_HELPER &


# last step!
# make bare-metal DB aware of our HW node and any additional network interfaces
# TODO: make this step separate and repeatable for multi-node deploy
$BM_SCRIPT_PATH/$BM_SCRIPT node create --host=$BM_SERVICE_HOST_NAME --cpus=1 --memory_mb=512 --local_gb=0 --pm_address=$PM_ADDR --pm_user=$PM_USER --pm_password=$PM_PASS --prov_mac=$BM_TARGET_MAC --terminal_port=0
$BM_SCRIPT_PATH/$BM_SCRIPT interface create --node_id=1 --mac_address=$BM_FAKE_MAC --datapath_id=0 --port_no=0

echo "Preparation complete. Exiting now."
