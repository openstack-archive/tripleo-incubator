#!/bin/bash
#
# Demo script for Tripleo - the dev/test story.
# This can be run for CI purposes, by passing --trash-my-machine to it.
# Without that parameter, the script is a no-op.

# Set PS4 as early as possible if it is still at the default, so that
# we have a useful trace output for everything when running devtest.sh
# with bash -x ./devtest.sh
if [ "$PS4" = "+ " ]; then
    export PS4='$(basename ${BASH_SOURCE})@${LINENO}: '
fi
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
    echo "    --bm-networks NETFILE  -- You are supplying your own network layout."
    echo "                              The schema for baremetal-network can be found in"
    echo "                              the devtest_setup documentation."
    echo
    echo "    --nodes NODEFILE       -- You are supplying your own list of hardware."
    echo "                              The schema for nodes can be found in the devtest_setup"
    echo "                              documentation."
    echo "    --no-undercloud        -- Use the seed as the baremetal cloud to deploy the"
    echo "                              overcloud from."
    echo "    --build-only           -- Builds images but doesn't attempt to run them."
    echo "    --no-mergepy           -- Use the standalone Heat templates."
    echo "    --debug-logging        -- Enable debug logging in the undercloud and overcloud."
    echo "    --heat-env-undercloud ENVFILE"
    echo "                           -- heat environment file for the undercloud."
    echo "    --heat-env-overcloud  ENVFILE"
    echo "                           -- heat environment file for the overcloud."
    echo
    echo "Note that this script just chains devtest_variables, devtest_setup,"
    echo "devtest_testenv, devtest_ramdisk, devtest_seed, devtest_undercloud,"
    echo "devtest_overcloud, devtest_end. If you want to run less than all of them just"
    echo "run the steps you want in order after sourcing ~/.devtestrc and"
    echo "devtest_variables.sh"
    echo
    exit $1
}

BUILD_ONLY=
NO_MERGEPY=--no-mergepy
DEBUG_LOGGING=
NODES_ARG=
NO_UNDERCLOUD=
NETS_ARG=
CONTINUE=
HEAT_ENV_UNDERCLOUD=
HEAT_ENV_OVERCLOUD=
USE_CACHE=0
export TRIPLEO_CLEANUP=1
DEVTEST_START=$(date +%s) #nodocs

TEMP=$(getopt -o h,c -l build-only,no-mergepy,debug-logging,existing-environment,help,trash-my-machine,nodes:,bm-networks:,no-undercloud,heat-env-overcloud:,heat-env-undercloud: -n $SCRIPT_NAME -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --build-only) BUILD_ONLY=--build-only; shift 1;;
        --no-mergepy) NO_MERGEPY=--no-mergepy; shift 1;;
        --debug-logging) DEBUG_LOGGING=--debug-logging; shift 1;;
        --trash-my-machine) CONTINUE=--trash-my-machine; shift 1;;
        --existing-environment) TRIPLEO_CLEANUP=0; shift 1;;
        --nodes) NODES_ARG="--nodes $2"; shift 2;;
        --bm-networks) NETS_ARG="--bm-networks $2"; shift 2;;
        --no-undercloud) NO_UNDERCLOUD="true"; shift 1;;
        --heat-env-undercloud) HEAT_ENV_UNDERCLOUD="--heat-env $2"; shift 2;;
        --heat-env-overcloud) HEAT_ENV_OVERCLOUD="--heat-env $2"; shift 2;;
        -c) USE_CACHE=1; shift 1;;
        -h|--help) show_options 0;;
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

## More details about the TripleO project and its goals can be found in the
## :doc:`README <README>`

## .. tip::

##    https://wiki.openstack.org/wiki/TripleO#Notes_for_new_developers contains
##    notes on setting up a development environment. It's primarily aimed at
##    people who intend to become contributors for tripleo, but many of its
##    notes (such as those relating to setting up local mirrors for apt and
##    pypi) will probably be helpful for everyone.

## .. note::

##    See :ref:`tested_platforms` for an overview of which releases of which
##    distros are tested in our CI system.  We suggest you read that section
##    before proceeding, to make sure you're running on a platform that we have
##    extensively tested.

## Permissions
## -----------

## These scripts are designed to be run under your normal user account. The
## scripts make use of sudo when elevated privileges are needed. You will
## either need to run this attended, entering your password when sudo needs
## it, or enable passwordless sudo for your user. Another option is to extend
## the timeout of sudo sessions so that passwordless sudo will be allowed
## enough time on the controlling terminal to complete the devtest run. If
## there are any circumstances where running as a normal user, and not root,
## fails, this is considered a critical bug.

## Sudo
## ~~~~

## In order to set the sudo session timeout higher, add this to /etc/sudoers::
## 
##     Defaults    timestamp_timeout=240 # 4 hours
## 
## This will result in 4 hour timeouts for sudo session credentials. To
## reset the timeout run::
## 
##     sudo -k; sudo -v
## 

## In order to set a user to full passwordless operation add this (typically
## near the end of /etc/sudoers)::
## 
##     username    ALL = NOPASSWD: ALL
## 

## Initial Checkout
## ----------------

## #. Choose a base location to put all of the source code.

##    .. note::

##      exports are ephemeral - they will not survive across new shell sessions
##      or reboots. If you put these export commands in ``~/.devtestrc``, you
##      can simply ``source ~/.devtestrc`` to reload them. Alternatively, you
##      can ``$TRIPLEO_ROOT/tripleo-incubator/scripts/write-tripleorc`` and then
##      source the generated tripleorc file.

##    ::

##      export TRIPLEO_ROOT=~/tripleo

##    .. note::

##      This will be used by devtest.sh and other scripts to store the
##      additional tools, images, packages, tarballs and everything else
##      needed by the deployment process. The tripleo-incubator tools must
##      be cloned within your ``$TRIPLEO_ROOT``.

## #. Create the directory and clone tripleo-incubator within ``$TRIPLEO_ROOT``

##    ::

##      mkdir -p $TRIPLEO_ROOT
##      cd $TRIPLEO_ROOT
##      git clone https://git.openstack.org/openstack/tripleo-incubator
##      cd tripleo-incubator

## Optional: stable branch
## -----------------------

## Note that every effort is made to keep the published set of these instructions
## updated for use with only the master branches of the TripleO projects. There is
## **NO** guaranteed stability in master. There is also no guaranteed stable
## upgrade path from release to release or from one stable branch to a later
## stable branch. The stable branches are a point in time and make no
## guarantee about deploying older or newer branches of OpenStack projects
## correctly.

## If you wish to use the stable branches, you should instead checkout and clone
## the stable branch of tripleo-incubator you want, and then build the
## instructions yourself. For instance, to create a local branch named
## ``foo`` based on the upstream branch ``stable/foo``::

##      git checkout -b foo origin/stable/foo
##      tox -edocs
##      # View doc/build/html/devtest.html in your browser and proceed from there

## Next Steps:
## -----------

## When run as a standalone script, devtest.sh runs the following commands
## to configure the devtest environment, bootstrap a seed, deploy under and
## overclouds. Many of these commands are also part of our documentation.
## Readers may choose to either run the commands given here, or instead follow
## the documentation for each command and walk through it step by step to see
## what is going on. This choice can be made on a case by case basis - for
## instance, if bootstrapping is not interesting, run that as devtest does,
## then step into the undercloud setup for granular details of bringing up a
## baremetal cloud.

### --end

#FIXME: This is a little weird. Perhaps we should identify whatever state we're
#      accumulating and store it in files or something, rather than using
#      source?

### --include

## #. See :doc:`devtest_variables` for documentation. Assuming you're still at
##    the root of your checkout::

##        source scripts/devtest_variables.sh
source $SCRIPT_HOME/devtest_variables.sh  #nodocs

## #. See :doc:`devtest_setup` for documentation.
##    $CONTINUE should be set to '--trash-my-machine' to have it execute
##    unattended.
##    ::

devtest_setup.sh $CONTINUE

## #. See :doc:`devtest_testenv` for documentation. This step creates the
##    seed VM, as well as "baremetal" VMs for the under/overclouds. Details
##    of the created VMs are written to ``$TE_DATAFILE``.

##    .. warning::

##       You should only run this step once, the first time the environment
##       is being set up. Unless you remove the VMs and need to recreate
##       them, you should skip this step on subsequent runs. Running this
##       script with existing VMs will result in information about the existing
##       nodes being removed from ``$TE_DATAFILE``

##    ::

if [ "$TRIPLEO_CLEANUP" = "1" ]; then #nodocs
#XXX: When updating, also update the header in devtest_testenv.sh #nodocs
devtest_testenv.sh $TE_DATAFILE $NODES_ARG $NETS_ARG
fi #nodocs

## #. See :doc:`devtest_ramdisk` for documentation::

DEVTEST_RD_START=$(date +%s) #nodocs
devtest_ramdisk.sh
DEVTEST_RD_END=$(date +%s) #nodocs

## #. See :doc:`devtest_seed` for documentation. If you are not deploying an
##    undercloud, (see below) then you will want to add --all-nodes to your
##    invocation of devtest_seed.sh,which will register all your nodes directly
##    with the seed cloud.::

##         devtest_seed.sh
##         export no_proxy=${no_proxy:-},192.0.2.1
##         source $TRIPLEO_ROOT/tripleo-incubator/seedrc

### --end
DEVTEST_SD_START=$(date +%s)
if [ -z "$NO_UNDERCLOUD" ]; then
  ALLNODES=""
else
  ALLNODES="--all-nodes"
fi
devtest_seed.sh $BUILD_ONLY $ALLNODES $DEBUG_LOGGING
DEVTEST_SD_END=$(date +%s)
export no_proxy=${no_proxy:-},$(os-apply-config --type netaddress -m $TE_DATAFILE --key baremetal-network.seed.ip --key-default '192.0.2.1')
if [ -z "$BUILD_ONLY" ]; then
    source $TRIPLEO_ROOT/tripleo-incubator/seedrc
fi
### --include

## #. See :doc:`devtest_undercloud` for documentation. The undercloud doesn't
##    have to be built - the seed is entirely capable of deploying any
##    baremetal workload - but a production deployment would quite probably
##    want to have a heat deployed (and thus reconfigurable) deployment
##    infrastructure layer).
##    If you are only building images you won't need to update your no_proxy
##    line or source the undercloudrc file.

##    ::

##         devtest_undercloud.sh $TE_DATAFILE
##         export no_proxy=$no_proxy,$(os-apply-config --type raw -m $TE_DATAFILE --key undercloud.endpointhost)
##         source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc
### --end
DEVTEST_UC_START=$(date +%s)
if [ -z "$NO_UNDERCLOUD" ]; then
    devtest_undercloud.sh $TE_DATAFILE $BUILD_ONLY $DEBUG_LOGGING $HEAT_ENV_UNDERCLOUD
    if [ -z "$BUILD_ONLY" ]; then
        export no_proxy=$no_proxy,$(os-apply-config --type raw -m $TE_DATAFILE --key undercloud.endpointhost)
        source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc
    fi
fi
DEVTEST_UC_END=$(date +%s)
### --include

## #. See :doc:`devtest_overcloud` for documentation.
##    If you are only building images you won't need to update your no_proxy
##    line or source the overcloudrc file.

##    ::

##         devtest_overcloud.sh
### --end
DEVTEST_OC_START=$(date +%s)
devtest_overcloud.sh $BUILD_ONLY $NO_MERGEPY $DEBUG_LOGGING $HEAT_ENV_OVERCLOUD
DEVTEST_OC_END=$(date +%s)
if [ -z "$BUILD_ONLY" ]; then
### --include
export no_proxy=$no_proxy,$(os-apply-config --type raw -m $TE_DATAFILE --key overcloud.endpointhost)
source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc
fi #nodocs

## #. See :doc:`devtest_end` for documentation::

devtest_end.sh

### --end

DEVTEST_END=$(date +%s) #nodocs
DEVTEST_PERF_LOG="${TRIPLEO_ROOT}/devtest_perf.log" #nodocs
TIMESTAMP=$(date "+[%Y-%m-%d %H:%M:%S]") #nodocs
echo "${TIMESTAMP} Run comment  : ${DEVTEST_PERF_COMMENT:-"No Comment"}" >> ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP} Total runtime: $((DEVTEST_END - DEVTEST_START)) s" | tee -a ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP}   ramdisk    : $((DEVTEST_RD_END - DEVTEST_RD_START)) s" | tee -a ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP}   seed       : $((DEVTEST_SD_END - DEVTEST_SD_START)) s" | tee -a ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP}   undercloud : $((DEVTEST_UC_END - DEVTEST_UC_START)) s" | tee -a ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP}   overcloud  : $((DEVTEST_OC_END - DEVTEST_OC_START)) s" | tee -a ${DEVTEST_PERF_LOG} #nodocs
echo "${TIMESTAMP} DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS}" >> ${DEVTEST_PERF_LOG} #nodocs
