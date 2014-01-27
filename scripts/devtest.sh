#!/bin/bash
#
# Demo script for Tripleo - the dev/test story.
# This can be run for CI purposes, by passing --trash-my-machine to it.
# Without that parameter, the script is a no-op.
set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Test the core TripleO story."
    echo
    echo "Options:"
    echo "    --trash-my-machine     -- make nontrivial destructive changes to the machine."
    echo "                              For details read the source."
    echo "    -c                     -- re-use existing source/images if they exist."
    echo "    --existing-environment -- use an existing test environment. The JSON file"
    echo "                              for it may be overridden via the TE_DATAFILE"
    echo "                              environment variable."
    echo
    echo "Note that this script just chains devtest_variables, devtest_setup,"
    echo "devtest_testenv, devtest_ramdisk, devtest_seed, devtest_undercloud,"
    echo "devtest_overcloud, devtest_end. If you want to run less than all of them just"
    echo "run the steps you want in order after sourcing ~/.devtestrc and"
    echo "devtest_variables.sh"
    echo
    exit $1
}

CONTINUE=
USE_CACHE=0
TRIPLEO_CLEANUP=1

TEMP=`getopt -o h,c -l existing-environment,trash-my-machine -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --trash-my-machine) CONTINUE=--trash-my-machine; shift 1;;
        --existing-environment) TRIPLEO_CLEANUP=0; shift 1;;
        -c) USE_CACHE=1; shift 1;;
        -h) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

if [ -z "$CONTINUE" ]; then
    echo "Not running - this script is destructive and requires --trash-my-machine to run." >&2
    exit 1
fi

export USE_CACHE

# Source environment variables from .devtestrc, allowing defaults to be setup
# specific to users environments
if [ -e ~/.devtestrc ] ; then
    echo "sourcing ~/.devtestrc"
    source ~/.devtestrc
fi

### --include
## devtest
## =======

## (There are detailed instructions available below, the overview and
## configuration sections provide background information).

## Overview:
##  * Define a VM that is your seed node
##  * Define N VMs to pretend to be your cluster
##  * Create a seed VM
##  * Create an undercloud
##  * Create an overcloud
##  * Deploy a sample workload in the overcloud
##  * Add environment variables to be included to ~/.devtestrc, e.g. http_proxy
##  * Go to town testing deployments on them.
##  * For troubleshooting see :doc:`troubleshooting`
##  * For generic deployment information see :doc:`deploying`

## This document is extracted from devtest.sh, our automated bring-up story for
## CI/experimentation.

## Next Steps:
## -----------
## 
## #. :doc:`devtest_variables`
## 
## #. :doc:`devtest_setup`
## 
## #. :doc:`devtest_testenv`
## 
## #. :doc:`devtest_ramdisk`
## 
## #. :doc:`devtest_seed`
## 
## #. :doc:`devtest_undercloud`
## 
## #. :doc:`devtest_overcloud`
## 
## #. :doc:`devtest_end`

### --end

#FIXME: This is a little weird. Perhaps we should identify whatever state we're
#      accumulating and store it in files or something, rather than using
#      source?
source $(dirname $0)/devtest_variables.sh
$(dirname $0)/devtest_setup.sh $CONTINUE
if [ "$TRIPLEO_CLEANUP" = "1" ]; then #nodocs
devtest_testenv.sh $TE_DATAFILE
fi #nodocs
devtest_ramdisk.sh
devtest_seed.sh
export no_proxy=$no_proxy,192.0.2.1
source $TRIPLEO_ROOT/tripleo-incubator/seedrc
source devtest_undercloud.sh
source devtest_overcloud.sh
source devtest_end.sh
