#!/bin/bash
#
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
SCRIPT_HOME=$(dirname $0)

PATH=$PATH:/usr/sbin:/sbin

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
    echo
    exit $1
}

TEMP=`getopt -o hcia:o:r:s: -l ip: -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h) show_options 0;;
        -c) export IMAGE_CACHE_USE=1; shift ;;
        --) shift ; break ;;
        #*) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

function build_or_use_cached_image() {
    
    IMAGE_NAME=$1
    shift
    IMAGE_ELEMENTS=$@
    IMAGE_CACHE_FILE=$TRIPLEO_ROOT/$IMAGE_NAME
    if [ ! -e "$IMAGE_CACHE_FILE.qcow2" -o -z "$IMAGE_CACHE_USE" ] ; then
        build-image -a $NODE_ARCH -o $IMAGE_NAME $IMAGE_ELEMENTS
    else
        echo "Using cached $IMAGE_NAME image : $IMAGE_CACHE_FILE.qcow2"
    fi
}

# Seed Image
SEED_DIB_BASE="vm cloud-init-nocloud local-config boot-stack nova-baremetal seed-stack-config remove-serial-console neutron-dhcp-agent"
SEED_ELEMENTS="$DIB_COMMON_ELEMENTS $SEED_DIB_BASE $SEED_DIB_EXTRA_ARGS"

# Undercloud Image
UNDERCLOUD_DIB_EXTRA_ARGS=${UNDERCLOUD_DIB_EXTRA_ARGS:-'rabbitmq-server'}
UNDERCLOUD_DIB_BASE="vm boot-stack nova-baremetal os-collect-config dhcp-all-interfaces neutron-dhcp-agent"
UNDERCLOUD_ELEMENTS="$DIB_COMMON_ELEMENTS $UNDERCLOUD_DIB_BASE $UNDERCLOUD_DIB_EXTRA_ARGS"

# Overcloud Control Image
OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server'}
OVERCLOUD_CONTROL_DIB_BASE="boot-stack cinder-api cinder-volume os-collect-config neutron-network-node dhcp-all-interfaces swift-proxy swift-storage"
OVERCLOUD_CONTROL_ELEMENTS="$DIB_COMMON_ELEMENTS $OVERCLOUD_CONTROL_DIB_BASE $OVERCLOUD_CONTROL_DIB_EXTRA_ARGS"

# Overcloud Compute Image
OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS=${OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS:-'rabbitmq-server'}
OVERCLOUD_COMPUTE_DIB_BASE="nova-compute nova-kvm neutron-openvswitch-agent os-collect-config dhcp-all-interfaces"
OVERCLOUD_COMPUTE_ELEMENTS="$DIB_COMMON_ELEMENTS $OVERCLOUD_COMPUTE_DIB_BASE $OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS"

# Sample User Image
USER_ELEMENTS="vm"

# Build each image
BUILD_IMAGES="SEED UNDERCLOUD OVERCLOUD_CONTROL OVERCLOUD_COMPUTE USER"
for i in $BUILD_IMAGES
do
    IMAGE_ELEMENTS_VAR=${i}_ELEMENTS
    IMAGE_NAME=`echo $i | awk '{print tolower($0)}' | sed 's/_/-/g'`
    IMAGE_ELEMENTS=${!IMAGE_ELEMENTS_VAR}
    if [ $i == "SEED" ]; then
       IMAGE_ELEMENTS="-u $IMAGE_ELEMENTS"
    fi
    build_or_use_cached_image $IMAGE_NAME $IMAGE_ELEMENTS
done


