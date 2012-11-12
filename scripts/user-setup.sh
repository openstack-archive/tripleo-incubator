#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

# upload a keypair into devstack for convenience
LOCAL_KEYFP=`ssh-keygen -lf ~/.ssh/authorized_keys | awk '{print $2}'`
NOVA_KEYFP=`nova keypair-list | awk '/default/ {print $4}'`
if [ -z "$NOVA_KEYFP" ]; then
    $NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default
elif [ "$NOVA_KEYFP" != "$LOCAL_KEYFP" ]; then
    nova keypair-delete default
    $NOVA keypair-add --pub_key ~/.ssh/authorized_keys  default
fi
