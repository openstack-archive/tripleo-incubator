#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_save
## ============

## #. Save your devtest instances to disk

## This script allows one to save all the devtest instances to disk and ready to
## resumed at a later time. It is required that the instance be mangedsave by
## libvirt/qemu. One of the known issue is that an instance connected to a sata
## virtual bus cannot be persisted to disk. Therefore, please make sure
## DISK_BUS_TYPE is set to 'scsi' in the environment.

## #. Get the list of devtest VMs from libvirt

##    ::

baremetals=( $(sudo virsh list --name --state-running | grep "^baremetal" ) )
readarray -t reverse_baremetals < <(for a in "${baremetals[@]}"; do echo "$a"; done | sort -r)
seeds=( $(sudo virsh list --name --state-running| grep "^seed" ) )
readarray -t reverse_seeds < <(for a in "${seeds[@]}"; do echo "$a"; done | sort -r)


## #. First pause the VMs in reverse order. This stage is needs to be done in a
##    tight loop to avoid any clock skews or the state inconsistencies.

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

## #. You can reboot your workstation now. To resume devtest
##    run devtest_resume.sh

##    ::


## The End!
##
### --end
