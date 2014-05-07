#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Save your devtest instances to disk::

### --end

baremetals=( $(sudo virsh list --name --state-running | grep "^baremetal" ) )
readarray -t reverse_baremetals < <(for a in "${baremetals[@]}"; do echo "$a"; done | sort -r)
seeds=( $(sudo virsh list --name --state-running| grep "^seed" ) )
readarray -t reverse_seeds < <(for a in "${seeds[@]}"; do echo "$a"; done | sort -r)


# First pause the VMs in reverse order. This stage is needs to be done in a tight loop to
# avoid clock skews or the state becoming inconsistent
for v in ${reverse_baremetals[@]} ${reverse_seeds[@]}; do
    echo "Pausing " $v
    sudo virsh suspend $v
done

# Sleep for 2 seconds. No logical justification just being paranoid
sleep 2

# Now save the VMs to disk. VM order doesn't matter now 
# though we still do it in a reverse order.
for v in ${reverse_baremetals[@]} ${reverse_seeds[@]}; do
    echo "Saving " $v
    sudo virsh managedsave $v
done

echo "Saving devtest instances completed."
echo ""

### --include
## #. You can reboot your workstation now. To resume devtest
##    run devtest_resume.sh
##    ::

##      source $TRIPLEO_ROOT/tripleorc


## The End!
## 
### --end
