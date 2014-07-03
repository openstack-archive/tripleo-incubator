#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options] {JSON-filename}"
    echo
    echo "Updates the BM network description for a TripleO devtest environment."
    echo
    echo "Options:"
    echo "    -h                     -- This help."
    echo "    --bm-networks NETFILE  -- You are supplying your own network layout."
    echo "                              The schema for baremetal-network can be found in"
    echo "                              the devtest_setup documentation."
    echo
    echo "JSON-filename -- the path to write the environment description to."
    echo
    exit $1
}

NETS_PATH=

TEMP=$(getopt -o h -l bm-networks: -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --bm-networks) NETS_PATH="$2"; shift 2;;
        -h) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

JSONFILE=${1:-''}
EXTRA_ARGS=${2:-''}

if [ -z "$JSONFILE" -o -n "$EXTRA_ARGS" ]; then
    show_options 1
fi

### --include
## #. If you have an existing bare metal cloud network to use, use it. See
##    `baremetal-network` section in :ref:`devtest-environment-configuration`
##    for more details
##    ::

if [ -n "$NETS_PATH" ]; then
  JSON=$(jq -s '.[0]["baremetal-network"]=.[1] | .[0]' $JSONFILE $NETS_PATH)
  echo "${JSON}" > $JSONFILE
fi

### --end
