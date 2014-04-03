#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Build a baremetal deployment ramdisk."
    echo
    echo "Options:"
    echo "      -h                    -- this help"
    echo "      --download-images URL -- attempt to download images from this URL."
    echo
    exit $1
}

DOWNLOAD_OPT=

TEMP=$(getopt -o h -l download-images:,help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --download-images) DOWNLOAD_OPT="--download $2"; shift 2;;
        -h | --help) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

set -x
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

## #. Create or download deployment ramdisk + kernel. These are used by the
##    seed cloud and the undercloud for deployment to bare metal. To use a
##    cache pass -c to acquire-image. To download the files pass --download BASE_URL.
##    ::

NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch)
##    acquire-image $TRIPLEO_ROOT/deploy-ramdisk \
##    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -- \
##    -a $NODE_ARCH $NODE_DIST $DEPLOY_IMAGE_ELEMENT \
##    $DIB_COMMON_ELEMENTS

### --end

if [ "$USE_CACHE" = "1" ]; then
    CACHE_OPT=-c
else
    CACHE_OPT=
fi
acquire-image $CACHE_OPT $DOWNLOAD_OPT $TRIPLEO_ROOT/deploy-ramdisk \
    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -- \
    -a $NODE_ARCH $NODE_DIST $DEPLOY_IMAGE_ELEMENT \
    $DIB_COMMON_ELEMENTS 2>&1 | \
    tee $TRIPLEO_ROOT/dib-deploy.log
