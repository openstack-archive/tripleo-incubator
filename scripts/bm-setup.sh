#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

IMG_PATH=$DEVSTACK_PATH/files
BM_IMAGE=demo.qcow2

# load images into glance
function populate_glance() {
    # ensure there is a deployment ramdisk.
    if [ ! -e $IMG_PATH/$BM_DEPLOY_RAMDISK ]; then
        ~stack/baremetal-initrd-builder/bin/ramdisk-image-create deploy -o $IMG_PATH/$BM_DEPLOY_RAMDISK -k $KERNEL_VER
        sudo cp /boot/vmlinuz-$KERNEL_VER $IMG_PATH/$BM_DEPLOY_KERNEL
        sudo chmod a+r $IMG_PATH/$BM_DEPLOY_KERNEL
    fi
    aki=$(load_image "aki" "aki-01" $IMG_PATH/$BM_DEPLOY_KERNEL)
    ari=$(load_image "ari" "ari-01" $IMG_PATH/$BM_DEPLOY_RAMDISK)

    # Load a simple single image for now.
    echo "loading demo image to glance"
    ami=$(load_image "ami" demo $IMG_PATH/$BM_IMAGE | head -n1)
    # associate deploy aki and ari to main AMI 
    # XXX: Going when this is moved to flavour.
    $GLANCE image-update --property "deploy_kernel_id=$aki" $ami
    $GLANCE image-update --property "deploy_ramdisk_id=$ari" $ami

    # XXX: Crashes if the image is changed (flavour already exists)
    # create instance type (aka flavor)
    # - a 32 bit instance
    $NOVA_MANAGE instance_type create --name=x86_bm --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=6 --swap=0 --rxtx_factor=1
    $NOVA_MANAGE instance_type set_key --name=x86_bm --key cpu_arch --value x86
    # - a 64 bit instance
    $NOVA_MANAGE instance_type create --name=x86_64_bm --cpu=1 --memory=512 --root_gb=0 --ephemeral_gb=0 --flavor=7 --swap=0 --rxtx_factor=1
    $NOVA_MANAGE instance_type set_key --name=x86_64_bm --key cpu_arch --value x86_64
}

GLANCE_BMIMG_SIZE=`glance image-list | awk "/demo/"'{print $10}'`
LOCAL_BMIMG_SIZE=`stat -c%s $IMG_PATH/$BM_IMAGE`

if [ -z "$GLANCE_BMIMG_SIZE" ]; then
    populate_glance
elif [ "$GLANCE_BMIMG_SIZE" != "$LOCAL_BMIMG_SIZE" ]; then
    delete_image demo
    delete_image aki-01
    delete_image ari-01
    delete_image ari-02
    delete_image aki-02
    populate_glance
fi
