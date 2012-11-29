#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

# Create a demo cloud image - the bare metal image that gets deployed to each
# node.
~/diskimage-builder/bin/disk-image-create -o $DEVSTACK_PATH/files/demo base salt-minion
