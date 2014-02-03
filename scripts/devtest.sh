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

## Stability Warning
## -----------------

## Note that every effort is made to keep the published set of these instructions
## updated for use with only the master branches of the TripleO projects. There is
## **NO** guaranteed stability in master. There is also no guaranteed stable
## upgrade path from release to release or from one stable branch to a later
## stable branch. The stable branches are a point in time and make no
## guarantee about deploying older or newer branches of OpenStack projects
## correctly.

## If you wish to use the stable branches, you should instead checkout and clone
## the stable branch of tripleo-incubator you want, and then build the
## instructions yourself via::

##      git clone https://git.openstack.org/openstack/tripleo-incubator
##      cd tripleo-incubator
##      git checkout <stable-branch>
##      tox -evenv python setup.py build_sphinx
##      # View doc/build/html/devtest.html in your browser and proceed from there

## Next Steps:
## -----------

## When run as a single top level thing, devtest.sh runs the following commands
## to configure the devtest environment, bootstrap a seed etc. Many of these
## commands are also part of our documentation. Readers may choose to either
## run the command given here, or instead follow the documentation for each
## command and walk through it step by step to see what is going on. This
## choice can be made on a case by case basis - for instance, if bootstrapping
## is not interesting, run that as devtest does, then step into the undercloud
## setup for granular details of bringing up a baremetal cloud.

### --end

#FIXME: This is a little weird. Perhaps we should identify whatever state we're
#      accumulating and store it in files or something, rather than using
#      source?

### --include

## #. See :doc:`devtest_variables` for documentation.

source $(dirname $0)/devtest_variables.sh

## #. See :doc:`devtest_setup` for documentation.
##    $CONTINUE should be set to '--trash-my-machine' to have it execute
##    unattended.

$(dirname $0)/devtest_setup.sh $CONTINUE

## #. See :doc:`devtest_testenv` for documentation. Note that you can make
##    your test environment just once and reuse it thereafter.
##    TE_DATAFILE should specify where you want your test environment JSON
##    file created. (A default value is set in devtest_variables.sh).

if [ "$TRIPLEO_CLEANUP" = "1" ]; then #nodocs
devtest_testenv.sh $TE_DATAFILE
fi #nodocs

## #. See a:doc:`devtest_ramdisk` for documentation.

devtest_ramdisk.sh

## #. See :doc:`devtest_seed` for documentation.

devtest_seed.sh

## #. See :doc:`devtest_undercloud` for documentation.

export no_proxy=${no_proxy:-},192.0.2.1
source $TRIPLEO_ROOT/tripleo-incubator/seedrc
devtest_undercloud.sh $TE_DATAFILE

## #. See :doc:`devtest_overcloud` for documentation.

export no_proxy=$no_proxy,$(os-apply-config --type raw -m $TE_DATAFILE undercloud.endpointhost)
source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc
source devtest_overcloud.sh
## #. See :doc:`devtest_end` for documentation.

devtest_end.sh

### --end
