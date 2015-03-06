#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Build a baremetal deployment ramdisk."
    echo
    echo "Options:"
    echo "      -h             -- this help"
    echo
    exit $1
}

TEMP=$(getopt -o h -l help -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2;
    exit 1;
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
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


## #. Create a deployment ramdisk + kernel. These are used by the seed cloud and
##    the undercloud for deployment to bare metal.
##    ::

### --end
NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch)
if [ ! -e $TRIPLEO_ROOT/$DEPLOY_NAME.kernel -o \
    ! -e $TRIPLEO_ROOT/$DEPLOY_NAME.initramfs -o \
    "$USE_CACHE" == "0" ] ; then
### --include
    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -a $NODE_ARCH \
        $NODE_DIST $DEPLOY_IMAGE_ELEMENT -o $TRIPLEO_ROOT/$DEPLOY_NAME \
        $DIB_COMMON_ELEMENTS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-deploy.log
### --end
fi
