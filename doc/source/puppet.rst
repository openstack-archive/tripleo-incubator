TripleO Overcloud deployment with Puppet
========================================

Intro
-----

This document outlines how to deploy a TripleO overcloud using Puppet
for configuration. TripleO currently supports using Puppet for configuration
using Heat metadata directly via the normal os-collect-config/os-refresh-config
agents. No puppet-master or puppet DB infrastructure is required.

Building Images
---------------
When building TripleO images for use with Puppet the following elements
should be installed:

- ``hosts``
- ``os-net-config``
- ``os-collect-config``
- ``heat-config-puppet``
- ``puppet-modules``
- ``hiera``

The ``hosts`` and ``os-net-config`` are normal TripleO image elements and are still
used to deploy basic physical networking configuration required to bootstrap
the node.

The ``os-collect-config``, and ``heat-config-puppet`` elements provide mechanism
to run ``puppet apply`` commands that have been configured via Heat software
deployment configurations.

The ``puppet-modules`` element installs all of the required ``stackforge
puppet-*`` modules. This element has two modes of operation: package or source
installs.  The package mode assumes that all of the required modules exist in
a single distribution provided package. The source mode deploys the puppet
modules from Git at image build time and automatically links them into
``/etc/puppet/modules``. The source mode makes use of source repositories so
you can, for example, pin to a specific ``puppetlabs-mysql`` module version by setting::

    DIB_REPOREF_puppetlabs_mysql=<GIT COMMIT HASH>

The ``hiera`` element provides a way to configure the hiera.yaml and hieradata
files on each node directly via Heat metadata. The ``tripleo-heat-templates``
are used to drive this configuration.

When building images for use with Puppet it is important to note that
regardless of whether you use source or package mode to install these core
elements the actual OpenStack service packages (Nova, Neutron, Keystone, etc)
will need to be installed via normal distro packages. This is required in
order to work with the stackforge puppet modules.

The OpenStack service packages can be installed at DIB time via the -p
option or at deployment time when Puppet is executed on each node.

Heat Templates
--------------

When deploying an overcloud with Heat only the newer
``overcloud-without-mergepy.yaml`` supports Puppet. To enable Puppet simply use
the ``overcloud-resource-registry-puppet.yaml`` instead of the normal
``overcloud-resource-registry.yaml`` with your Heat ``stack-create`` command.

Running Devtest Overcloud with Delorean on Fedora
-------------------------------------------------

This section describes the variables required in order to run
``devtest_overcloud.sh`` with Puppet. It assumes you have a fully working
TripleO undercloud (or seed) which has been preconfigured to work
in your environment.

.. note::

   The following instructions assume this pre-existing config from a normal devtest Fedora setup::

       export NODE_DIST='fedora selinux-permissive'
       export DIB_RELEASE=20
       export RDO_RELEASE=juno

       # Enable packages for all elements by default
       export DIB_DEFAULT_INSTALLTYPE=package

       # Install undercloud mariadb-rpm this way since we set USE_MARIADB=0
       export SEED_DIB_EXTRA_ARGS='rabbitmq-server mariadb-rpm'
       export UNDERCLOUD_DIB_EXTRA_ARGS='rabbitmq-server mariadb-rpm'

   By default TripleO uses puppet for configuration only. Packages (RPMs, etc)
   are typically installed at image build time.

   If you wish to have packages installed at deploy time via Puppet it
   is important to have a working undercloud nameserver. You can configure
   this by adding the appropriate undercloud.nameserver setting
   settings to your undercoud-env.json file. Alternately, If going directly
   from the seed to the overcloud then you'll need to set seed.nameserver
   in your testenv.json. If you wish to install packages at deploy
   time you will also need to set EnablePackageInstall to true in your
   overcloud-resource-registry-puppet.yaml (see below for instructions
   on how to override your Heat resource registry).

1) Git clone the tripleo-puppet-elements [1]_ project into your $TRIPLEO_ROOT.  This is currently a non-standard image elements repository and needs to be manually cloned in order to build Puppet images.

2) Add tripleo-puppet-elements to your ELEMENTS_PATH::

    export ELEMENTS_PATH=$ELEMENTS_PATH:$TRIPLEO_ROOT/tripleo-puppet-elements/elements:$TRIPLEO_ROOT/heat-templates/hot/software-config/elements

3) Setup variables to override the normal DIB image elements::

    export OVERCLOUD_CONTROL_DIB_ELEMENTS='sysctl hosts baremetal dhcp-all-interfaces os-collect-config heat-config-puppet puppet-modules hiera os-net-config delorean-repo rdo-release'
    # NOTE: This pre-installs Rabbit and Maria in the Controller.
    # We let Puppet install the OpenStack services on the controller for
    # now as this triggers an initial db_sync. We can re-work the db_sync
    # Puppet modules a bit and allow pre-installed OS packages in the
    # controller image.
    export OVERCLOUD_CONTROL_DIB_EXTRA_ARGS='overcloud-controller'
    export OVERCLOUD_COMPUTE_DIB_ELEMENTS='sysctl hosts baremetal dhcp-all-interfaces os-collect-config heat-config-puppet puppet-modules hiera os-net-config delorean-repo rdo-release'
    # NOTE: This pre-installs the Nova, Neutron, and Ceilometer packages in
    # the compute image
    export OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS='overcloud-compute'
    export OVERCLOUD_CEPHSTORAGE_DIB_ELEMENTS='sysctl hosts baremetal dhcp-all-interfaces os-collect-config heat-config-puppet puppet-modules hiera os-net-config delorean-repo rdo-release'
    export OVERCLOUD_CEPHSTORAGE_DIB_EXTRA_ARGS='overcloud-ceph-storage'

4) Override the tripleo-heat-templates resource registry::

    export RESOURCE_REGISTRY_PATH="$TRIPLEO_ROOT/tripleo-heat-templates/overcloud-resource-registry-puppet.yaml"

5) Explicitly disable the USE_MARIADB and USE_CEPH flags. This is because they inject extra elements into the DIB arguments which we do not want when using Puppet::

    export USE_MARIADB=0
    export USE_CEPH=0

6) Configure your Delorean repo URL. This is used to fetch more recently built upstream packages for your OpenStack services::

    export DELOREAN_REPO_URL="http://209.132.178.33/repos/current"

 For more information on Delorean see [2]_

7) Enable the use of stackforge modules from Git. This is to work around the fact that the Fedora RPM doesn't have puppet-keepalived yet::

    export DIB_INSTALLTYPE_puppet_modules=source

8) Source your undercloud environment RC file (perhaps via the select-cloud script). Then execute devtest_overcloud.sh using the new no-mergepy templates::

    devtest_overcloud.sh --no-mergepy

References
----------
.. [1]  http://git.openstack.org/openstack/tripleo-puppet-elements/
.. [2]  https://github.com/openstack-packages/delorean
