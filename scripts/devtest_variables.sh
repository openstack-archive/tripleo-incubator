#!/bin/bash
#
# Variable definition for devtest.

### --include
## devtest_variables
## =================

## #. The devtest scripts require access to the libvirt system URI.
##    If running against a different libvirt URI you may encounter errors.
##    Export ``LIBVIRT_DEFAULT_URI`` to prevent devtest using qemu:///system
##    Check that the default libvirt connection for your user is qemu:///system.
##    If it is not, set an environment variable to configure the connection.
##    This configuration is necessary for consistency, as later steps assume
##    qemu:///system is being used.
##    ::

export LIBVIRT_DEFAULT_URI=${LIBVIRT_DEFAULT_URI:-"qemu:///system"}

## #. The VMs created by devtest will use a virtio network device by
##    default. This can be overridden to use a different network driver for
##    interfaces instead, such as ``e1000`` if required.
##    ::

export LIBVIRT_NIC_DRIVER=${LIBVIRT_NIC_DRIVER:-"virtio"}

## #. By default the node volumes will be created in a volume pool named
##    'default'. This variable can be used to specify a custom volume
##    pool. This is useful in scenarios where the default volume pool cannot
##    accommodate the storage requirements of the nodes.

##    Note that this variable only changes the volume pool for the nodes.
##    Seed image will still end up in /var/lib/libvirt/images.
##    ::

export LIBVIRT_VOL_POOL=${LIBVIRT_VOL_POOL:-"default"}

## #. The tripleo-incubator tools must be available at
##    ``$TRIPLEO_ROOT/tripleo-incubator``. See the :doc:`devtest` documentation
##    which describes how to set that up correctly.
##    ::

export TRIPLEO_ROOT=${TRIPLEO_ROOT:-} #nodocs

### --end
## NOTE(gfidente): Keep backwards compatibility by setting TRIPLEO_ROOT
## to ~/.cache/tripleo if the var is found empty and the dir exists.
if [ -z "$TRIPLEO_ROOT" -a -d ~/.cache/tripleo ]; then
    echo "WARNING: Defaulting TRIPLEO_ROOT to ~/.cache/tripleo"
    echo "         Other environment variables are based on \$TRIPLEO_ROOT so"
    echo "         if you intend changing it, please source devtest_variables.sh"
    echo "         again afterwards."
    TRIPLEO_ROOT=~/.cache/tripleo
fi

## NOTE(gfidente): Exit if TRIPLEO_ROOT is still empty or misconfigured
if [ -z "$TRIPLEO_ROOT" -o ! -d $TRIPLEO_ROOT/tripleo-incubator/scripts ]; then
    echo 'ERROR: Cannot find $TRIPLEO_ROOT/tripleo-incubator/scripts'
    echo '       To use devtest you must export the TRIPLEO_ROOT variable and have cloned tripleo-incubator within that directory.'
    echo '       Check http://docs.openstack.org/developer/tripleo-incubator/devtest.html#initial-checkout for instructions.'
    return 1
fi
### --include
export PATH=$TRIPLEO_ROOT/tripleo-incubator/scripts:$TRIPLEO_ROOT/dib-utils/bin:$PATH

## #. It's possible to deploy the Undercloud without a UI and its dependent elements.
##    The dependent image elements in Undercloud are Horizon, Tuskar-UI (not included
##    yet, Tuskar UI element is not finished) and  Ceilometer. In Overcloud it is
##    SNMPd image element on every node.
##    ::

export USE_UNDERCLOUD_UI=${USE_UNDERCLOUD_UI:-1}

## #. Ironic is used as the default baremetal deployment layer. To use the
##    deprecated Nova-Baremetal deployment layer set USE_IRONIC=0.
##    Note however that as Nova-Baremetal is deprecated in Nova and TripleO
##    support for it will be removed once it is removed from Nova.
##    ::

export USE_IRONIC=${USE_IRONIC:-1}

if [ 0 -eq "$USE_IRONIC" ]; then
    echo "Nova-baremetal is deprecated, please migrate to Ironic ASAP." >&2
fi

## #. Set a list of image elements that should be included in all image builds.
##    Note that stackuser is only for debugging support - it is not suitable for
##    a production network. This is also the place to include elements such as
##    pip-cache or pypi-openstack if you intend to use them.
##    ::

export DIB_COMMON_ELEMENTS=${DIB_COMMON_ELEMENTS:-"stackuser common-venv"}

## #. If you have a specific Ubuntu mirror you want to use when building
##    images.
##    ::

# export DIB_COMMON_ELEMENTS="${DIB_COMMON_ELEMENTS} apt-sources"
# export DIB_APT_SOURCES=/path/to/a/sources.list to use.

## #. These elements are required for tripleo in all images we build.
##    ::

export DIB_COMMON_ELEMENTS="${DIB_COMMON_ELEMENTS} use-ephemeral"

## #. Choose the deploy image element to be used. `deploy-kexec` will relieve you of
##    the need to wait for long hardware POST times, however it has known stability
##    issues (please see https://bugs.launchpad.net/diskimage-builder/+bug/1240933).
##    If stability is preferred over speed, use the `deploy-baremetal` image
##    element (default) or `deploy-ironic` if using ironic.
##    ::

if [ $USE_IRONIC -eq 0 ]; then
    # nova baremetal
    export DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy-baremetal}
    export DEPLOY_NAME=deploy-ramdisk
else
    # Ironic
    export DEPLOY_IMAGE_ELEMENT=${DEPLOY_IMAGE_ELEMENT:-deploy-ironic}
    export DEPLOY_NAME=deploy-ramdisk-ironic
fi

## #. A messaging backend is required for the seed, undercloud, and overcloud
##    control node. It is not required for overcloud computes. The backend is
##    set through the ``*EXTRA_ARGS``.
##    rabbitmq-server is enabled by default. Another option is qpidd.
##    For overclouds we also use ``*EXTRA_ARGS`` to choose a cinder backend, set
##    to cinder-tgt by default.
##    ::

export SEED_DIB_EXTRA_ARGS=${SEED_DIB_EXTRA_ARGS:-"rabbitmq-server"}
export UNDERCLOUD_DIB_EXTRA_ARGS=${UNDERCLOUD_DIB_EXTRA_ARGS:-"rabbitmq-server"}
export OVERCLOUD_CONTROL_DIB_EXTRA_ARGS=${OVERCLOUD_CONTROL_DIB_EXTRA_ARGS:-'rabbitmq-server cinder-tgt'}

## #. The block storage nodes are deployed with the cinder-tgt backend by
##    default. Another option is cinder-lio.
##    ::

export OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS=${OVERCLOUD_BLOCKSTORAGE_DIB_EXTRA_ARGS:-'cinder-tgt'}

## #. Set distribution used for VMs (fedora, opensuse, ubuntu). If unset, this
##    will match TRIPLEO_OS_DISTRO, which is automatically gathered by devtest
##    and represent your build host distro (where the devtest code runs).
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

## #. Set the number of baremetal nodes to create in the virtual test
##    environment.
##    ::

# Node definitions are cheap but redeploying testenv's is not.
# Set NODE_CNT high enough for typical CI and Dev deployments for the
# foreseeable future
export NODE_CNT=${NODE_CNT:-15}

## #. Set size of root partition on our disk (GB). The remaining disk space
##    will be used for the persistent ephemeral disk to store node state.
##    ::

export ROOT_DISK=${ROOT_DISK:-10}

## #. Set the disk bus type. The default value is 'sata'. But if the VM is going
##    to be migrated or saved to disk, then 'scsi' would be more appropriate
##    for libvirt.
##    ::

export LIBVIRT_DISK_BUS_TYPE=${LIBVIRT_DISK_BUS_TYPE:-"sata"}

## #. Set number of compute, control and other type of nodes for the overcloud.
##    Only a value of 1 for OVERCLOUD_CONTROLSCALE is currently supported.
##    ::

export OVERCLOUD_COMPUTESCALE=${OVERCLOUD_COMPUTESCALE:-2}
export OVERCLOUD_CONTROLSCALE=${OVERCLOUD_CONTROLSCALE:-1}
export OVERCLOUD_BLOCKSTORAGESCALE=${OVERCLOUD_BLOCKSTORAGESCALE:-0}
export OVERCLOUD_CEPHSTORAGESCALE=${OVERCLOUD_CEPHSTORAGESCALE:-0}

## #. These optional variables can be set to remove dead nodes. See the merge.py
##    help for details of use. These example lines would remove Compute1 and
##    Compute3, and Control2 and Control4.
##    ::

##         export OVERCLOUD_COMPUTE_BLACKLIST=1,3
##         export OVERCLOUD_CONTROL_BLACKLIST=2,4

## #. You need to make the tripleo image elements accessible to diskimage-builder:
##    ::

export ELEMENTS_PATH=${ELEMENTS_PATH:-"$TRIPLEO_ROOT/tripleo-image-elements/elements"}

## #. Set the datafile to use to describe the 'hardware' in the devtest
##    environment. If this file already exists, you should skip running
##    devtest_testenv.sh as it writes to the file
##    ::

export TE_DATAFILE=${TE_DATAFILE:-"$TRIPLEO_ROOT/testenv.json"}

## #. By default Percona XtraDB Cluster is used when installing MySQL database,
##    set ``USE_MARIADB=1`` if you want use MariaDB instead, MariaDB is used by
##    default on Fedora based distributions because MariaDB packages are included
##    directly in distribution
##    ::


if [[ $NODE_DIST =~ .*(fedora|rhel|centos).* ]] ; then
    export USE_MARIADB=${USE_MARIADB:-1}
else
    export USE_MARIADB=0
fi


## #. Set ``USE_CEPH=1`` if you want to use Ceph as Cinder backend. Enabled
##    by default when ``OVERCLOUD_CEPHSTORAGESCALE`` is > 0
##    ::


if [ $OVERCLOUD_CEPHSTORAGESCALE -gt 0 ] ; then
    export USE_CEPH=${USE_CEPH:-1}
else
    export USE_CEPH=0
fi


## #. You can choose between using the old-style merge.py script for putting
##    together or the newer way of doing it directly via Heat.
##    ::

export USE_MERGEPY=${USE_MERGEPY:-1}

### --end
