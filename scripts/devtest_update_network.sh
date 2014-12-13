#!/bin/bash

set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME --bm-networks NETFILE {JSON-filename}"
    echo
    echo "Reads the baremetal-network description in NETFILE and writes it into JSON-filename"
    echo
    echo "For instance, to read the file named bm-networks.json and update testenv.json:"
    echo "      ${SCRIPT_NAME} --bm-networks bm-networks.json testenv.json "
    echo
    echo "Options:"
    echo "    -h                     -- This help."
    echo "    --bm-networks NETFILE  -- You are supplying your own network layout."
    echo "                              The schema for baremetal-network can be found in"
    echo "                              the devtest_setup documentation."
    echo "                              For backwards compatibility, this argument is optional;"
    echo "                              but if it's not provided this script does nothing."
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

### --include
## devtest_update_network
## ======================

## This script updates the baremetal networks definition in the
## ``$TE_DATAFILE``.
### --end

JSONFILE=${1:-''}
EXTRA_ARGS=${2:-''}

if [ -z "$JSONFILE" -o -n "$EXTRA_ARGS" ]; then
    show_options 1
fi

if [ -n "$NETS_PATH" ]; then
  JSON=$(jq -s '.[0]["baremetal-network"]=.[1] | .[0]' $JSONFILE $NETS_PATH)
  echo "${JSON}" > $JSONFILE
fi
