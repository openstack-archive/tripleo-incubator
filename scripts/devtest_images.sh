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

set -e
set -o pipefail

SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $(readlink -e ${0}))
PATH=/usr/sbin:/sbin:$PATH

# Some defaults
IMAGE_CACHE_USE=
NODE_ARCH=i386
if [ -z "$TE_DATAFILE" ]; then
    echo "TE_DATAFILE not set. Using default Node Arch: $NODE_ARCH"
else
    NODE_ARCH=$(os-apply-config -m $TE_DATAFILE --key arch --type raw)
fi

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo
    echo "Build all images required for a Tripleo deployment:"
    echo "Seed, Undercloud, Overcloud-Control, Overcloud-Compute"
    echo "and sample user image"
    echo
    echo "Options:"
    echo "      -c                -- use an image cache for each image."
    echo "      -h                -- show this message."
    echo
    exit $1
}

TEMP=$(getopt -o hc -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h) show_options 0;;
        -c) export IMAGE_CACHE_USE=1; shift ;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

function build_or_use_cached_image() {

    local image_name=$1 image_elements image_cache_file
    shift
    image_elements=$@
    image_cache_file=$TRIPLEO_ROOT/$image_name
    if [ ! -e "$image_cache_file.qcow2" -o -z "$IMAGE_CACHE_USE" ] ; then
        $SCRIPT_HOME/build-image -a $NODE_ARCH -o $image_name $image_elements
    else
        echo "Using cached $IMAGE_NAME image : $image_cache_file.qcow2"
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
BUILD_IMAGES="SEED UNDERCLOUD OVERCLOUD_CONTROL OVERCLOUD_COMPUTE USER"
for i in $BUILD_IMAGES
do
    IMAGE_ELEMENTS_VAR=${i}_ELEMENTS
    IMAGE_NAME=$(echo $i | tr '[:upper:]_' '[:lower:]-')
    IMAGE_ELEMENTS=${!IMAGE_ELEMENTS_VAR}
    if [ "$i" == "SEED" ]; then
       export DIB_IMAGE_SIZE=30 
       IMAGE_ELEMENTS="-u $IMAGE_ELEMENTS"
    else
       unset DIB_IMAGE_SIZE
    fi
    build_or_use_cached_image $IMAGE_NAME $IMAGE_ELEMENTS
done
