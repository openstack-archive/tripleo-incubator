#!/bin/bash

set -eux
set -o pipefail

USE_CACHE=${USE_CACHE:-0}

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

DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy}

## #. Create a deployment ramdisk + kernel. These are used by the seed cloud and
##    the undercloud for deployment to bare metal.
##    ::

### --end
if [ ! -e $TRIPLEO_ROOT/deploy-ramdisk.kernel -o \
     ! -e $TRIPLEO_ROOT/deploy-ramdisk.initramfs -o \
     "$USE_CACHE" == "0" ] ; then
### --include
    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -a $NODE_ARCH \
        $NODE_DIST $DEPLOY_IMAGE_ELEMENT -o $TRIPLEO_ROOT/deploy-ramdisk 2>&1 | \
        tee $TRIPLEO_ROOT/dib-deploy.log
### --end
fi
