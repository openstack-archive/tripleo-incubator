#/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
source $(dirname 0)/defaults

# build deployment ramdisk if needed
if [ ! -e $IMG_PATH/$BM_DEPLOY_RAMDISK ]; then
    pushd ~stack/baremetal-initrd-builder
    ./baremetal-mkinitrd.sh $IMG_PATH/$BM_DEPLOY_RAMDISK $KERNEL_VER
    sudo cp /boot/vmlinuz-$KERNEL_VER $IMG_PATH/$BM_DEPLOY_KERNEL
    sudo chmod a+r $IMG_PATH/$BM_DEPLOY_KERNEL
    popd
fi

# fix mysql issues - adds user_quotas table - not sure what uses it.
# TODO: remove after NTT patch lands upstream
# TODO: skip this block if it's already done
sql=<<EOL
GRANT ALL PRIVILEGES ON nova_bm.* TO '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';
EOL

## XXX: In theory this is not needed anymore. It may 
MYSQL=$(which mysql)
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$sql"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -v -v -f nova_bm < $(dirname $0)/init_nova_bm_db.sql

# The baremetal migrations fail if the nova quota table doesn't already exist.
$BM_SCRIPT_PATH/$BM_SCRIPT db sync

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
$NOVA_MANAGE instance_type create --name=$BM_NODE_NAME --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=6 --swap=0 --rxtx_factor=1
$NOVA_MANAGE instance_type set_key --name=$BM_NODE_NAME --key cpu_arch --value "$BM_TARGET_CPU"

# restart dnsmasq
sudo pkill dnsmasq || true
sudo mkdir -p /tftpboot/pxelinux.cfg
sudo cp /usr/lib/syslinux/pxelinux.0 /tftpboot/
sudo chown -R stack:libvirtd /tftpboot
sudo dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --interface=$DNSMASQ_IFACE --dhcp-range=$DNSMASQ_RANGE

# make sure deploy server is running
[ $(pgrep -f "$BM_HELPER") ] || $BM_SCRIPT_PATH/$BM_HELPER &

set +o xtrace
set +e

echo "Preparation complete."
echo "Inform baremetal nova of your baremetal nodes."

