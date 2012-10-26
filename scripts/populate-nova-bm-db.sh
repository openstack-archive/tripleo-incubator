#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
source $(dirname $0)/defaults

# set some defaults
RAM=512
DISK=0
CPU=1
HOST=$(hostname -f)

# we need two unique MAC addresses
# PXE_MAC must match the VM
# however, IFACE_MAC can be totally fake for VMs
# XXX how will this work on the rack?
PXE_MAC=
IFACE_MAC=

USAGE="
Helper script to manage entries in bare-metal db.

Usage:
   Clear all entries...
      $(basename $0) clear

   Add new entry...
      $(basename $0)  -i <MAC> -j <MAC> [-h <hostname>] [-M <RAM>] [-D <DISK>] [-C <CPU>] add
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
   list=$(  $BM_SCRIPT_PATH/$BM_SCRIPT node list | tail -n +2 | awk '{print $1}' )
   for node in $list
   do
      $BM_SCRIPT_PATH/$BM_SCRIPT node delete $node
   done
   list=$(  $BM_SCRIPT_PATH/$BM_SCRIPT interface list | tail -n +2 | awk '{print $1}' )
   for iface in $list
   do
      $BM_SCRIPT_PATH/$BM_SCRIPT interface delete $iface
   done
}

function add {
   id=$(  $BM_SCRIPT_PATH/$BM_SCRIPT node create \
      --host=$HOST --cpus=$CPU --memory_mb=$RAM --local_gb=$DISK \
      --pm_address=$PM_ADDR --pm_user=$PM_USER --pm_password=$PM_PASS \
      --terminal_port=0 --prov_mac=$PXE_MAC \
      )
   [ $? -eq 0 ] || [ "$id" ] || die "Error adding node"
   id2=$(  $BM_SCRIPT_PATH/$BM_SCRIPT interface create \
      --node_id=$id --mac_address=$IFACE_MAC --datapath_id=0 --port_no=0 \
      )
   [ $? -eq 0 ] || [ "$id2" ] || die "Error adding interface"
}

shift $(($OPTIND - 1))
case $1 in
   clear )  clear ;;
   add   )  add ;;
   * )      die "$USAGE" ;;
esac

