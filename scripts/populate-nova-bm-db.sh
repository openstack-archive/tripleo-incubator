#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

# set some defaults
RAM=512
DISK=0
CPU=1
HOST=$(hostname -f)

# we need a unique MAC addresses, and PXE_MAC must match the VM
# If there is a second NIC, we can set IFACE_MAC, but it is only optional now
PXE_MAC=
IFACE_MAC=

USAGE="
Helper script to manage entries in bare-metal db.

Usage:
   Clear all entries...
      $(basename $0) clear

   Add new entry...
      $(basename $0)  -i <MAC> [-j <MAC>] [-h <hostname>] [-M <RAM>] [-D <DISK>] [-C <CPU>] add
"

[ $# -eq 0 ] && echo "$USAGE" && die

while getopts "i:j:h:M:D:C:" Option
do
   case $Option in
      i )            PXE_MAC=$OPTARG;;
      j )            IFACE_MAC=$OPTARG;;
      h )            HOST=$OPTARG;;
      M )            RAM=$OPTARG;;
      D )            DISK=$OPTARG;;
      C )            CPU=$OPTARG;;
      * )            echo "$USAGE" && die;;
   esac
done

function clear {
   _u=$OS_USERNAME
   _t=$OS_TENANT_NAME
   export OS_USERNAME=admin
   export OS_TENANT_NAME=demo
   nodes=$( nova baremetal-node-list | tail -n +4 | head -n -1 | awk '{print $2}' )
   for node in $nodes
   do
      nova baremetal-node-delete $node
   done
   export OS_USERNAME=$_u
   export OS_TENANT_NAME=$_t
}

function add {
   PM_OPTS=
   if [ -n "$BM_PM_ADDR" ]; then
      if [ -n "$BM_PM_USER" -a -n "$BM_PM_PASS" ]; then
         PM_OPTS="--pm_address=$BM_PM_ADDR --pm_user=$BM_PM_USER --pm_password=$BM_PM_PASS"
      fi
   fi
   _u=$OS_USERNAME
   _t=$OS_TENANT_NAME
   export OS_USERNAME=admin
   export OS_TENANT_NAME=demo
   id=$( nova baremetal-node-create $PM_OPTS $HOST $CPU $RAM $DISK $PXE_MAC \
         | awk '/\| id / {print $4}' )
   [ $? -eq 0 ] || [ "$id" ] || die "Error adding node"
  
   id2=$( nova baremetal-interface-add $id $PXE_MAC )
   [ $? -eq 0 ] || [ "$id2" ] || die "Error adding interface"
   if [ -n "$IFACE_MAC" ]; then
      id2=$( nova baremetal-interface-add $id $IFACE_MAC )
      [ $? -eq 0 ] || [ "$id2" ] || die "Error adding interface"
   fi
   export OS_USERNAME=$_u
   export OS_TENANT_NAME=$_t
}

shift $(($OPTIND - 1))
case $1 in
   clear )  clear ;;
   add   )  add ;;
   * )      die "$USAGE" ;;
esac

