#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_save
## ============

## #. Save your devtest instances to disk

## This script allows one to save all the devtest instances to disk and ready to
## be resumed at a later time. It is required that the instance be managedsaved
## by libvirt/qemu. One of the known issues is that an instance connected to a
## SATA virtual bus cannot be persisted to disk. Therefore, the DISK_BUS_TYPE
## should be changed to a migration supported virtual bus.
## For example: 'export DISK_BUS_TYPE='scsi'

## #. Get the list of devtest VMs from libvirt

##    ::

baremetals=( $(sudo virsh list --name --state-running | grep "^baremetal" ) )
readarray -t reverse_baremetals < <(for a in "${baremetals[@]}"; do echo "$a"; done | sort -r)
seeds=( $(sudo virsh list --name --state-running| grep "^seed" ) )
readarray -t reverse_seeds < <(for a in "${seeds[@]}"; do echo "$a"; done | sort -r)


## #. First pause all the nodes in the devtest cluster. This stage needs to be
## done in a tight loop to preserve the state of cluster. As an additional
## precaution we also pause the nodes in the reverse order they were brought up.
## This prevents a situation where the underlying layer is paused while the
## layer above continues to run. This can result in services such as dhcp denied
## to the running layer.

##    ::
for v in ${reverse_baremetals[@]} ${reverse_seeds[@]}; do
    echo "Pausing " $v
    sudo virsh suspend $v
done

## #. Sleep for 2 seconds. No logical justification, simply being paranoid.
##    ::
sleep 2

## #. Now save the VMs to disk. VM order doesn't matter now
##    though we still do it in a reverse order.
##    ::
for v in ${reverse_baremetals[@]} ${reverse_seeds[@]}; do
    echo "Saving " $v
    sudo virsh managedsave $v
done

echo "Saving devtest instances completed."
echo ""

## The End!
##
### --end
