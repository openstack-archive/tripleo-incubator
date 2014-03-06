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
CPU_MIN=1
CPU=0
DISK_MIN=20
DISK=0
MEM_MIN=2048
MEM=0

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo
    echo "Check if baremetal nodes are ready, based on a set of"
    echo "minimum requirements".
    echo
    echo "Options:"
    echo "      -h                   -- Show this help."
    echo "      --disk               -- Minimum available disk space required (GB)."
    echo "      --cpu                -- Minimum number of CPUs required."
    echo "      --mem                -- Minimum memory required (MB)."
    echo
    exit $1
}

TEMP=$(getopt -o h -l cpu:,disk:,mem: -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h) show_options 0;;
        --cpu) CPU_MIN=$2; shift 2 ;;
        --disk) DISK_MIN=$2; shift 2 ;;
        --mem) MEM_MIN=$2; shift 2 ;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; show_options 1 ;;
    esac
done

while read -r line
do
    case "$line" in
      *count*)
          line_arr=($line)
          CPU=${line_arr[3]} ;;
      *local_gb*)
          line_arr=($line)
          DISK=${line_arr[3]} ;;
      *memory_mb*)
          line_arr=($line)
          MEM=${line_arr[3]} ;;
    esac
done < <(nova hypervisor-stats)

if [ $CPU -lt $CPU_MIN ]; then
    exit 1
fi

if [ $DISK -lt $DISK_MIN ]; then
    exit 1
fi

if [ $MEM -lt $MEM_MIN ]; then
    exit 1
fi
