#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

BUILD_ONLY=
PARALLEL_BUILD=

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Build a baremetal deployment ramdisk."
    echo
    echo "Options:"
    echo "      -h                -- this help"
    echo "      --build-only      -- build the needed images but don't deploy them."
    echo "      --parallel-build  -- Perform the builds in parallel"
    echo "                           This just sets a unique ccache dir, assuming that"
    echo "                           devtest.sh has backgrounded this script"
    echo
    exit $1
}

TEMP=$(getopt -o h -l help,build-only,parallel-build -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h | --help) show_options 0;;
        --build-only) BUILD_ONLY="1"; shift 1;;
        --parallel-build) PARALLEL_BUILD="1"; shift 1;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

if [ -n "$PARALLEL_BUILD" -a -z "$BUILD_ONLY" ]; then
    echo "Error: --parallel-build used without --build-only"
    show_options 1
fi

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
    DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy-baremetal}
    DEPLOY_NAME=deploy-ramdisk
else
    # Ironic
    DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy-ironic}
    DEPLOY_NAME=deploy-ramdisk-ironic
fi

## #. Create a deployment ramdisk + kernel. These are used by the seed cloud and
##    the undercloud for deployment to bare metal.
##    ::

### --end
NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch)
if [ ! -e $TRIPLEO_ROOT/$DEPLOY_NAME.kernel -o \
     ! -e $TRIPLEO_ROOT/$DEPLOY_NAME.initramfs -o \
     "$USE_CACHE" == "0" ] ; then
    if [ -n "$PARALLEL_BUILD" ]; then
        export DIB_CCACHE_DIR="$HOME/.cache/image-create/ccache-$DEPLOY_NAME/"
        export DIB_APT_LOCAL_CACHE=$DEPLOY_NAME
    fi
### --include
    $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -a $NODE_ARCH \
        $NODE_DIST $DEPLOY_IMAGE_ELEMENT -o $TRIPLEO_ROOT/$DEPLOY_NAME \
        $DIB_COMMON_ELEMENTS 2>&1 | \
        tee $TRIPLEO_ROOT/dib-deploy.log
### --end
fi
