#!/bin/bash

set -eux
set -o pipefail

USE_CACHE=${USE_CACHE:-0}
DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-'stackuser'}

### --include
## devtest_ramdisk
## ===============

## Deploy Ramdisk creation
## -----------------------

## #. Choose the deploy image element to be used. `deploy-kexec` will relieve you of
##    the need to wait for long hardware POST times, however it has known stability
##    issues (please see https://bugs.launchpad.net/diskimage-builder/+bug/1240933).
##    If stability is preferred over speed, use `deploy` image element (default).
##    ::

if [ $USE_IRONIC -eq 0 ]; then
    # nova baremetal
    DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy}
else
    # Ironic
    DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy-ironic}
fi

## #. Create a deployment ramdisk + kernel. These are used by the seed cloud and
##    the undercloud for deployment to bare metal.
##    ::

### --end
NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch)
if [ ! -e $TRIPLEO_ROOT/deploy-ramdisk.kernel -o \
     ! -e $TRIPLEO_ROOT/deploy-ramdisk.initramfs -o \
     "$USE_CACHE" == "0" ] ; then
### --include
    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -a $NODE_ARCH \
        $NODE_DIST $DEPLOY_IMAGE_ELEMENT -o $TRIPLEO_ROOT/deploy-ramdisk \
        $DIB_COMMON_ELEMENTS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-deploy.log
### --end
fi
