#!/bin/bash
#
# Variable definition for devtest.

### --include
## devtest_variables
## =================

## #. The devtest scripts require access to the libvirt system URI.
##    If running against a different libvirt URI you may encounter errors.
##    Export LIBVIRT_DEFAULT_URI to prevent devtest using qemu:///system
##    Check that the default libvirt connection for your user is qemu:///system.
##    If it is not, set an environment variable to configure the connection.
##    This configuration is necessary for consistency, as later steps assume
##    qemu:///system is being used.
##    ::

export LIBVIRT_DEFAULT_URI=${LIBVIRT_DEFAULT_URI:-"qemu:///system"}

## #. The vm's created by devtest will use a virtio network device by
##    default. This can be overridden to use a different network driver for
##    interfaces instead, such as e1000 if required.
##    ::

export LIBVIRT_NIC_DRIVER=${LIBVIRT_NIC_DRIVER:-"virtio"}

## #. Choose a base location to put all of the source code.
##    ::
## 
##         # exports are ephemeral - new shell sessions, or reboots, and you need
##         # to redo them, or use $TRIPLEO_ROOT/tripleo-incubator/scripts/write-tripleorc
##         # and then source the generated tripleorc file.
##         export TRIPLEO_ROOT=~/tripleo
export TRIPLEO_ROOT=${TRIPLEO_ROOT:-~/.cache/tripleo} #nodocs

## 
## #. Nova tools will get installed in $TRIPLEO_ROOT/tripleo-incubator/scripts
##    - you need to add that to the PATH.
##    ::

### --end
# If devtest_setup.sh has never been run in this environment,
# $TRIPLEO_ROOT/tripleo-incubator/scripts probably won't exist, so we can't
# rely on being able to run devtest_setup.sh from there

if [ ! -e $TRIPLEO_ROOT ]; then
  export PATH=$(readlink -e $(dirname ${BASH_SOURCE[0]})):$PATH
fi
### --include
export PATH=$TRIPLEO_ROOT/tripleo-incubator/scripts:$PATH

## #. We now support Ironic as the baremetal deployment layer. To use it just
##    set USE_IRONIC=1. The default is still Nova Baremetal until we've had some
##    time to identify any kinks in the process.
##    ::

export USE_IRONIC=${USE_IRONIC:-0}

## #. Set a list of image elements that should be included in all image builds.
##    Note that stackuser is only for debugging support - it is not suitable for
##    a production network. This is also the place to include elements such as
##    pip-cache or pypi-openstack if you intend to use them.
##    ::

export DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-"stackuser"}

## #. If you have a specific Ubuntu mirror you want to use when building
##    images.
##    ::

# export DIB_COMMON_ELEMENTS="${DIB_COMMON_ELEMENTS} apt-sources"
# export DIB_APT_SOURCES=/path/to/a/sources.list to use.

## #. These elements are required for tripleo in all images we build.
##    ::

export DIB_COMMON_ELEMENTS="${DIB_COMMON_ELEMENTS} use-ephemeral"

## #. A messaging backend is required for the seed, undercloud, and overcloud
##    control node. It is not required for overcloud computes. The backend is
##    set through the ``*EXTRA_ARGS``.
##    rabbitmq-server is the default backend. Another option is qpidd.
##    ::

export SEED_DIB_EXTRA_ARGS=${SEED_DIB_EXTRA_ARGS:-"rabbitmq-server"}
export UNDERCLOUD_DIB_EXTRA_ARGS=${UNDERCLOUD_DIB_EXTRA_ARGS:-"rabbitmq-server"}
export OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server'}

## #. Set distribution used for VMs (fedora, opensuse, ubuntu).
## 
##    For Fedora, set SELinux permissive mode(currently the default when using Fedora)::
## 
##         export NODE_DIST="fedora selinux-permissive"

##    For openSUSE, use::
## 
##         export NODE_DIST="opensuse"

##    For Ubuntu, use::
## 
##         export NODE_DIST="ubuntu"

### --end
source $(dirname ${BASH_SOURCE[0]:-$0})/set-os-type
if [ -z "${NODE_DIST:-}" ]; then
    if [ "$TRIPLEO_OS_DISTRO" = "fedora" ]; then
        export NODE_DIST="fedora selinux-permissive"
    else
        export NODE_DIST=$TRIPLEO_OS_DISTRO
    fi
fi
### --include

## #. Set size of root partition on our disk (GB). The remaining disk space
##    will be used for the persistent ephemeral disk to store node state.
##    ::

export ROOT_DISK=${ROOT_DISK:-10}

## #. Set number of compute nodes for the overcloud
##    ::

export OVERCLOUD_COMPUTESCALE=${OVERCLOUD_COMPUTESCALE:-2}

## #. You need to make the tripleo image elements accessible to diskimage-builder:
##    ::

export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-image-elements/elements

## #. Set the datafile to use to describe the 'hardware' in the devtest
##    environment. If this file already exists, you should skip running
##    devtest_testenv.sh as it writes to the file
##    ::

export TE_DATAFILE=${TE_DATAFILE:-"$TRIPLEO_ROOT/testenv.json"}

### --end
