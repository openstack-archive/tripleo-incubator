Patching a Juno host cloud for QuintupleO
=========================================

neutron-quintupleo.patch can be applied by going to the neutron source directory
(eg /opt/devstack/neutron or /usr/lib/python2.7/site-packages) on each compute
node and running the following:

    patch -p1 < /path/to/quintupleo-setup/patches/juno/neutron-quintupleo.patch

The neutron-openvswitch-agent service then needs to be restarted.

nova-quintuleo.patch can be applied by going to the nova source directory
(eg /opt/devstack/nova or /usr/lib/python2.7/site-packages) on each compute
node and  and running the following:

    patch -p1 < /path/to/quintupleo-setup/patches/juno/nova-quintuleo.patch

The nova-compute service then needs to be restarted.