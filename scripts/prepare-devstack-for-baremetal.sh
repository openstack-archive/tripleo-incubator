#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
# IMG_PATH and BM details need to be reintegrated now that the image building
# toolchain is separate: Things will fail until that is done.
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

# build deployment ramdisk if needed
if [ ! -e $IMG_PATH/$BM_DEPLOY_RAMDISK ]; then
    pushd ~stack/baremetal-initrd-builder
    ./baremetal-mkinitrd.sh $IMG_PATH/$BM_DEPLOY_RAMDISK $KERNEL_VER
    sudo cp /boot/vmlinuz-$KERNEL_VER $IMG_PATH/$BM_DEPLOY_KERNEL
    sudo chmod a+r $IMG_PATH/$BM_DEPLOY_KERNEL
    popd
fi

# load run-time ramdisk if needed
#if [ ! -e $IMG_PATH/$BM_RUN_RAMDISK ]; then
#    sudo cp /boot/initrd.img-$KERNEL_VER $IMG_PATH/$BM_RUN_RAMDISK
#    sudo chmod a+r $IMG_PATH/$BM_RUN_RAMDISK
#fi

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
LOCAL_KEYFP=`ssh-keygen -lf ~/.ssh/authorized_keys | awk '{print $2}'`
NOVA_KEYFP=`nova keypair-list | awk '/default/ {print $4}'`
if [ -z "$NOVA_KEYFP" ]; then
    $NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default
elif [ "$NOVA_KEYFP" != "$LOCAL_KEYFP" ]; then
    nova keypair-delete default
    $NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default
fi

function populate_glance() {
    # load images into glance
    ami=$(load_image "ami" $BM_NODE_NAME $IMG_PATH/$BM_IMAGE)
    aki=$(load_image "aki" "aki-01" $IMG_PATH/$BM_DEPLOY_KERNEL)
    ari=$(load_image "ari" "ari-01" $IMG_PATH/$BM_DEPLOY_RAMDISK)

    # associate deploy aki and ari to main AMI
    $GLANCE image-update --property "deploy_kernel_id=$aki" $ami
    $GLANCE image-update --property "deploy_ramdisk_id=$ari" $ami

    # pull run-time ramdisk and kernel out of AMI
    TMP_KERNEL=$(mktemp)
    TMP_RAMDISK=$(mktemp)
    TMP_MNT=$(mktemp_mount $IMG_PATH/$BM_IMAGE)
    trap 'rm -f $TMP_KERNEL $TMP_RAMDISK && sudo umount -f $TMP_MNT' ERR

    BM_RUN_KERNEL=$(basename `ls -1 $TMP_MNT/boot/vmlinuz*generic | sort -n | tail -1`)
    BM_RUN_RAMDISK=$(basename `ls -1 $TMP_MNT/boot/initrd*generic | sort -n | tail -1`)
    sudo cp $TMP_MNT/boot/$BM_RUN_KERNEL $TMP_KERNEL
    sudo cp $TMP_MNT/boot/$BM_RUN_RAMDISK $TMP_RAMDISK
    sudo chmod a+r $TMP_KERNEL

    # load run-time kernel and ramdisk
    aki=$(load_image "aki" "aki-02" $TMP_KERNEL)
    ari=$(load_image "ari" "ari-02" $TMP_RAMDISK)

    # clean up temp mounts and files
    sudo umount -f $TMP_MNT || true
    sudo rm -f $TMP_KERNEL $TMP_RAMDISK
    trap ERR

    # associate run-time aki and ari to main AMI
    $GLANCE image-update --property "kernel_id=$aki" $ami
    $GLANCE image-update --property "ramdisk_id=$ari" $ami

    # create instance type (aka flavor)
    # - a 32 bit instance
    $NOVA_MANAGE instance_type create --name=x86_bm --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=6 --swap=0 --rxtx_factor=1
    $NOVA_MANAGE instance_type set_key --name=x86_bm --key cpu_arch --value x86
    # - a 64 bit instance
    $NOVA_MANAGE instance_type create --name=x86_64_bm --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=7 --swap=0 --rxtx_factor=1
    $NOVA_MANAGE instance_type set_key --name=x86_64_bm --key cpu_arch --value x86_64
}

GLANCE_BMIMG_SIZE=`glance image-list | awk "/$BM_NODE_NAME/"'{print $10}'`
LOCAL_BMIMG_SIZE=`stat -c%s $IMG_PATH/$BM_IMAGE`

if [ -z "$GLANCE_BMIMG_SIZE" ]; then
    populate_glance
elif [ "$GLANCE_BMIMG_SIZE" != "$LOCAL_BMIMG_SIZE" ]; then
    delete_image $BM_NODE_NAME
    delete_image aki-01
    delete_image ari-01
    delete_image ari-02
    delete_image aki-02
    populate_glance
fi

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
