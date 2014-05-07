#!/bin/bash
#
# This script sets up network route to a devtest cluster if the host had
# been rebooted.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/scripts/devtest_variables.sh
BM_NETWORK_CIDR=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key baremetal-network.cidr --type raw --key-default '192.0.2.0/24')
ROUTE_DEV=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-route-dev --type netdevice --key-default virbr0)
SEED_IP=$(OS_CONFIG_FILES=$TE_DATAFILE os-apply-config --key seed-ip --type netaddress)

sudo ip route replace $BM_NETWORK_CIDR dev $ROUTE_DEV via $SEED_IP

