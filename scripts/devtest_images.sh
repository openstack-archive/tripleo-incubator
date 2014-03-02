#!/bin/bash
# Copyright 2014 Hewlett-Packard Development Company, L.P.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

set -eu
set -o pipefail

SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $(readlink -e ${0}))
PATH=/usr/sbin:/sbin:$PATH

# Some defaults
IMAGE_CACHE_USE=
DATAFILE=
BUILD_IMAGES_SELECTED=
NODE_ARCH=i386

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo
    echo "Build images required for a Tripleo deployment:"
    echo "Seed, Undercloud, Overcloud-Control, Overcloud-Compute"
    echo "and sample user image. All images are built if none are"
    echo "specified in the command-line options."
    echo
    echo "source devtest_variables.sh before running"
    echo
    echo "Options:"
    echo "      -c                   -- Do not build image if it already exists."
    echo "      -h                   -- Show this message."
    echo "      -d                   -- Data file that describes the 'hardware' in the devtest env."
    echo "      --seed               -- Build the seed image."
    echo "      --undercloud         -- Build the undercloud image."
    echo "      --overcloud-control  -- Build the overcloud-control image."
    echo "      --overcloud-compute  -- Build the overcloud-compute image."
    echo "      --user               -- Build the sample image for use in the overcloud."
    echo
    exit $1
}

TEMP=$(getopt -o hcd: -l seed,undercloud,overcloud-control,overcloud-compute -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h) show_options 0;;
        -c) export IMAGE_CACHE_USE=1; shift ;;
        -d) DATAFILE=$2; shift 2 ;;
        --seed|--undercloud|--overcloud-control|--overcloud-compute|--user)
            BUILD_IMAGES_SELECTED="$BUILD_IMAGES_SELECTED $(echo ${1/--/} | tr '[:lower:]-' '[:upper:]_')"; shift ;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; show_options 1 ;;
    esac
done

if [ -z "$DATAFILE" ]; then
    echo "Error: Data file not set"
    show_options 1
fi

# Default behaviour is to build all images, unless at least one has been
# specified in the command-line options.
if [ -z "$BUILD_IMAGES_SELECTED" ]; then
    BUILD_IMAGES="SEED UNDERCLOUD OVERCLOUD_CONTROL OVERCLOUD_COMPUTE USER"
else
    BUILD_IMAGES=$BUILD_IMAGES_SELECTED
fi

NODE_ARCH=$(os-apply-config -m $DATAFILE --key arch --type raw)
case $NODE_ARCH in
    i386|amd64) echo "Using arch=$NODE_ARCH" ;;
    *) echo "Error: Unsupported arch $NODE_ARCH!" ; exit 1 ;;
esac

if [ -z "$NODE_DIST" ]; then
    echo "Error: NODE_DIST not set."
    exit 1
fi

# Variables required for disk image builder.
: ${ELEMENTS_PATH:=$SCRIPT_HOME/../../tripleo-image-elements/elements}
export ELEMENTS_PATH
: ${DIB_PATH:=$SCRIPT_HOME/../../diskimage-builder}
DIB_CREATE=$(which disk-image-create || echo $DIB_PATH/bin/disk-image-create)

function build_or_use_cached_image() {
    local image_name=$1 image_elements image_cache_file
    shift
    image_elements=$@
    # Check for --offline option in image elements.
    if [[ $image_elements == *--offline* ]]; then
        export DIB_OFFLINE=1
        image_elements=${image_elements/"--offline "/}
    else
        unset DIB_OFFLINE
    fi
    image_cache_file=$TRIPLEO_ROOT/$image_name
    image_path=$TRIPLEO_ROOT/$image_name
    if [ ! -e "$image_cache_file.qcow2" -o -z "$IMAGE_CACHE_USE" ] ; then
        echo "Building $image_name image"
        $DIB_CREATE -a $NODE_ARCH -o $image_path $image_elements 2>&1 | tee $image_path.log
        echo "Finished building $image_name image"
    else
        echo "Skipping building of $image_name, existing cached image available for use: $image_cache_file.qcow2"
    fi
}

# Seed Image
SEED_DIB_BASE="vm cloud-init-nocloud local-config boot-stack nova-baremetal seed-stack-config remove-serial-console neutron-dhcp-agent"
SEED_ELEMENTS="$DIB_COMMON_ELEMENTS $SEED_DIB_BASE $SEED_DIB_EXTRA_ARGS"

# Undercloud Image
: ${UNDERCLOUD_DIB_EXTRA_ARGS:=rabbitmq-server}
UNDERCLOUD_DIB_BASE="boot-stack nova-baremetal os-collect-config dhcp-all-interfaces neutron-dhcp-agent"
UNDERCLOUD_ELEMENTS="$DIB_COMMON_ELEMENTS $UNDERCLOUD_DIB_BASE $UNDERCLOUD_DIB_EXTRA_ARGS"

# Overcloud Control Image
: ${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:=rabbitmq-mserver}
OVERCLOUD_CONTROL_DIB_BASE="hosts boot-stack cinder-api cinder-volume os-collect-config neutron-network-node dhcp-all-interfaces swift-proxy swift-storage"
OVERCLOUD_CONTROL_ELEMENTS="$DIB_COMMON_ELEMENTS $OVERCLOUD_CONTROL_DIB_BASE $OVERCLOUD_CONTROL_DIB_EXTRA_ARGS"

# Overcloud Compute Image
: ${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:=rabbitmq-server}
OVERCLOUD_COMPUTE_DIB_BASE="hosts nova-compute nova-kvm neutron-openvswitch-agent os-collect-config dhcp-all-interfaces"
OVERCLOUD_COMPUTE_ELEMENTS="$DIB_COMMON_ELEMENTS $OVERCLOUD_COMPUTE_DIB_BASE $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS"

# Sample User Image
USER_ELEMENTS="vm"

# Build each image
for i in $BUILD_IMAGES
do
    IMAGE_ELEMENTS_VAR=${i}_ELEMENTS
    IMAGE_NAME=$(echo $i | tr '[:upper:]_' '[:lower:]-')
    IMAGE_ELEMENTS=${!IMAGE_ELEMENTS_VAR}
    if [ "$i" == "SEED" ]; then
       # For seed only, set DIB_IMAGE_SIZE env variable and pass in uncompress option.
       export DIB_IMAGE_SIZE=30
       IMAGE_ELEMENTS="-u $IMAGE_ELEMENTS"
    else
       unset DIB_IMAGE_SIZE
    fi
    build_or_use_cached_image $IMAGE_NAME $NODE_DIST $IMAGE_ELEMENTS
done
