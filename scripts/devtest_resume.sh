#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_resume
## ==============

## #. Resume your devtest instances from disk
##    This script can be used to bring back a previously saved devtest session.

##    ::

baremetals=( $(sudo virsh list --name --all --with-managed-save | grep "^baremetal" ) )
seeds=( $(sudo virsh list --name --all --with-managed-save | grep "^seed" ) )


## #. First bring up the VMs to a paused state.
for v in ${seeds[@]} ${baremetals[@]}; do
    echo "Unsaving " $v
    sudo virsh start $v
done

## #. Sleep for 2 seconds. No logical justification, just being paranoid.
sleep 2

## #. Now resume the VMs in the forward order and hope for the best
for v in ${seeds[@]} ${baremetals[@]}; do
    echo "Resuming " $v
    sudo virsh resume $v
done

echo "Resuming devtest instances completed."
echo ""

## The End!
##
### --end
