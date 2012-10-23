#/bin/bash

# If something goes wrong bail, don't continue to the end
set -e

DEVSTACK_PATH=${DEVSTACK_PATH:-/home/stack/devstack}
[ -e $DEVSTACK_PATH/openrc ] && \
   source $DEVSTACK_PATH/openrc

MYSQL_USER=${MYSQL_USER:-root}
MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-secrete}

GLANCE=${GLANCE:-/usr/local/bin/glance}
NOVA=${NOVA:-/usr/local/bin/nova}
NOVA_MANAGE=${NOVA_MANAGE:-/usr/local/bin/nova-manage}

IMG_PATH=${IMG_PATH:-/home/stack/devstack/files}
BM_NODE_NAME=${BM_NODE_NAME:-bare_metal}

KERNEL_VER=${KERNEL_VER:-`uname -r`}

# The deployment bits - I think (robertc)
BM_IMAGE=${BM_IMAGE:-bm-node-image.$KERNEL_VER.img}
BM_KERNEL=${BM_KERNEL:-vmlinuz-$KERNEL_VER}
BM_RAMDISK=${BM_RAMDISK:-bm-deploy-ramdisk.$KERNEL_VER.img}

# The end user runtime bits - I think (robertc) 
BM_RUN_KERNEL=${BM_RUN_KERNEL:-$BM_KERNEL}
BM_RUN_RAMDISK=${BM_RUN_RAMDISK:-$BM_RAMDISK}

# TODO: get these from localrc
DNSMASQ_IFACE=${DNSMASQ_IFACE:-eth0}
DNSMASQ_RANGE=${DNSMASQ_RANGE:-192.168.2.33,192.168.2.63}

BM_SCRIPT_PATH=${BM_SCRIPT_PATH:-/opt/stack/nova/bin}
BM_SCRIPT=${BM_SCRIPT:-nova-baremetal-manage}
BM_HELPER=${BM_HELPER:-nova-baremetal-deploy-helper}

if [ ! -e $BM_SCRIPT_PATH/$BM_SCRIPT ]; then
   echo "Failed to find bare metal management script"
   exit 1
fi

BM_SERVICE_HOST_NAME=${BM_SERVICE_HOST_NAME:-`hostname`}
BM_TARGET_MAC=${BM_TARGET_MAC:-01:23:45:67:89:01}

PM_ADDR=${PM_ADDR:-1.2.3.4}
PM_USER=${PM_USER:-root}
PM_PASS=${PM_PASS:-secret}
set -o xtrace

# build deployment ramdisk if needed 
if [ ! -e $IMG_PATH/$BM_RAMDISK ]; then
    pushd ~stack/baremetal-initrd-builder
    ./baremetal-mkinitrd.sh $IMG_PATH/$BM_RAMDISK $KERNEL_VER
    sudo cp /boot/$BM_KERNEL $IMG_PATH/$BM_KERNEL
    popd
fi

#####
# fix mysql issues created by the NTT patch
# TODO: remove after upstream issues are fixed
#       or convert these to sqlalchemy migrations
sql=<<EOL
GRANT ALL PRIVILEGES ON nova_bm.* TO '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';
EOL

MYSQL=$(which mysql)
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "CREATE DATABASE IF NOT EXISTS nova_bm CHARACTER SET utf8;"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$sql"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -v -v -f nova_bm < $(dirname $0)/init_nova_bm_db.sql

# load main AMI
[ -e $IMG_PATH/$BM_IMAGE ] && \
   ami=$($GLANCE --verbose add is_public=true container_format=ami disk_format=ami name=$BM_NODE_NAME < $IMG_PATH/$BM_IMAGE) && \
   ami=$(echo "$ami" | head -1 | awk '{print $6}')

# load deploy kernel & ramdisk
[ -e $IMG_PATH/$BM_KERNEL ] && \
   aki=$($GLANCE --verbose add is_public=true container_format=aki disk_format=aki name='aki-01' < $IMG_PATH/$BM_KERNEL) && \
   aki=$(echo "$aki" | head -1 | awk '{print $6}')

[ -e $IMG_PATH/$BM_RAMDISK ] && \
   ari=$($GLANCE --verbose add is_public=true container_format=ari disk_format=ari name='ari-01' < $IMG_PATH/$BM_RAMDISK) && \
   ari=$(echo "$ari" | head -1 | awk '{print $6}')

#XXXXXXXXXXXx------------------ things work up to here -----------------
# associate deploy aki and ari to main AMI
$GLANCE image-update --property "deploy_kernel_id=$aki" $ami
$GLANCE image-update --property "deploy_ramdisk_id=$ari" $ami

# load run-time aki and ari, if specified
[ -e $IMG_PATH/$BM_RUN_KERNEL ] && [ $BM_RUN_KERNEL != $BM_KERNEL ] && \
   aki=$($GLANCE --verbose add is_public=true container_format=aki disk_format=aki name='aki-02' < $IMG_PATH/$BM_RUN_KERNEL) && \
   aki=$(echo "$aki" | head -1 | awk '{print $6}')

[ -e $IMG_PATH/$BM_RUN_RAMDISK ] && [ $BM_RUN_RAMDISK != $BM_RAMDISK ] && \
   ari=$($GLANCE --verbose add is_public=true container_format=ari disk_format=ari name='ari-02' < $IMG_PATH/$BM_RUN_RAMDISK) && \
   ari=$(echo "$ari" | head -1 | awk '{print $6}')

# associate run-time aki and ari to main AMI
$GLANCE image-update --property "kernel_id=$aki" $ami
$GLANCE image-update --property "ramdisk_id=$ari" $ami

# create instance type (aka flavor)
$NOVA_MANAGE instance_type create --name=$BM_NODE_NAME --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=99 --swap=0 --rxtx_factor=1
$NOVA_MANAGE instance_type set_key --name=$BM_NODE_NAME --key cpu_arch --value "x86_64"

# restart dnsmasq
sudo pkill dnsmasq
sudo dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --interface=$DNSMASQ_IFACE --dhcp-range=$DNSMASQ_RANGE

# sync nova_bm database
$BM_SCRIPT_PATH/$BM_SCRIPT db sync

# make sure deploy server is running
[ $(pgrep -f "$BM_HELPER") ] || $BM_SCRIPT_PATH/$BM_HELPER &

# make bare-metal DB aware of our HW node and any additional network interfaces
$BM_SCRIPT_PATH/$BM_SCRIPT node create --host=$BM_SERVICE_HOST_NAME --cpus=1 --memory_mb=512 --local_gb=0 --pm_address=$PM_ADDR --pm_user=$PM_USER --pm_password=$PM_PASS --prov_mac=$BM_TARGET_MAC --terminal_port=0

# add keypair... optional step
$NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default

echo "Preparation complete. Exiting now."
