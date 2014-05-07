#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Resume your devtest instances from disk::

### --end

baremetals=( $(sudo virsh list --name --all --with-managed-save | grep "^baremetal" ) )
seeds=( $(sudo virsh list --name --all --with-managed-save | grep "^seed" ) )


# First bring up the VMs to paused state.
for v in ${seeds[@]} ${baremetals[@]}; do
    echo "Unsaving " $v
    sudo virsh start $v
done

# Sleep for 2 seconds. No logical justification just being paranoid
sleep 2

# Now resume the VMs in the forward order and hope for the best
for v in ${seeds[@]} ${baremetals[@]}; do
    echo "Resuming " $v
    sudo virsh resume $v
done

echo "Resuming devtest instances completed."
echo ""

### --include
## #. You can reboot your workstation now. To resume devtest
##    run devtest_resume.sh
##    ::

##      source $TRIPLEO_ROOT/tripleorc


## The End!
## 
### --end
