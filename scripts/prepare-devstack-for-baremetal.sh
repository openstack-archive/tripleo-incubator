#/bin/bash

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

BM_IMAGE=${BM_IMAGE:-bm-node-image.3.2.0-27.img}
BM_KERNEL=${BM_KERNEL:-vmlinuz-3.2.0-27-generic}
BM_RAMDISK=${BM_RAMDISK:-bm-deploy-ramdisk.3.2.0-27.img}

BM_RUN_KERNEL=${BM_RUN_KERNEL:-$BM_KERNEL}
BM_RUN_RAMDISK=${BM_RUN_RAMDISK:-$BM_RAMDISK}

DNSMASQ_IFACE=${DNSMASQ_IFACE:-eth0}
DNSMASQ_RANGE=${DNSMASQ_RANGE:-10.10.1.200,10.10.1.250}

BM_SCRIPT_PATH=${BM_SCRIPT_PATH:-/opt/stack/nova/bin}
BM_SCRIPT=${BM_SCRIPT:-nova-baremetal-manage}
BM_HELPER=${BM_HELPER:-nova-baremetal-deploy-helper}

if [ ! -e $BM_SCRIPT_PATH/$BM_SCRIPT ]; then
   echo "Failed to find bare metal management script"
   exit 1
fi

BM_SERVICE_HOST_NAME=${BM_SERVICE_HOST_NAME:-devstack}
BM_TARGET_MAC=${BM_TARGET_MAC:-01:23:45:67:89:01}
BM_FAKE_MAC=${BM_FAKE_MAC:-01:23:45:67:89:02}

PM_ADDR=${PM_ADDR:-1.2.3.4}
PM_USER=${PM_USER:-root}
PM_PASS=${PM_PASS:-secret}
set -o xtrace

#####
# fix mysql issues created by the NTT patch
# TODO: remove after upstream issues are fixed
#       or convert these to sqlalchemy migrations
sql=<<EOL
GRANT ALL PRIVILEGES ON nova_bm.* TO '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';
EOL

MYSQL=$(which mysql)
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$sql"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -v -v -f nova_bm < init_nova_bm_db.sql

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

# restart dnsmask
sudo pkill dnsmasq
sudo dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --interface=$DNSMASQ_IFACE --dhcp-range=$DNSMASQ_RANGE

# sync nova_bm database
$BM_SCRIPT_PATH/$BM_SCRIPT db sync

# make sure deploy server is running
[ $(pgrep -f "python $BM_HELPER") ] || $BM_SCRIPT_PATH/$BM_HELPER &

# make bare-metal DB aware of our HW node and its network interfaces
$BM_SCRIPT_PATH/$BM_SCRIPT node create --host=$BM_SERVICE_HOST_NAME --cpus=1 --memory_mb=512 --local_gb=0 --pm_address=$PM_ADDR --pm_user=$PM_USER --pm_password=$PM_PASS --prov_mac=$BM_TARGET_MAC --terminal_port=0
$BM_SCRIPT_PATH/$BM_SCRIPT interface create --node_id=1 --mac_address=$BM_FAKE_MAC --datapath_id=0 --port_no=0

# add keypair... optional step
$NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default

echo "Preparation complete. Exiting now."
