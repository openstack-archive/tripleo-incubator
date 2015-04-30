TripleO Overcloud Network Isolation
===================================

Intro
-----

This document outlines how to deploy a TripleO overcloud with split
out (isolated) physical networks for various types of traffic.  Using this
approach it is possible to host traffic for specific types of network traffic
(tenants, storage, cluster management, etc.) in isolated networks. This is
in contrast to the TripleO default network topology which hosts all traffic
on the same flat 'ctlplane' network used for provisioning, and tenant
traffic runs in a GRE or VXLAN tunnel on the same physical network.

IP address management is done with Neutron. In this document we describe
how to modify the tripleo-heat-templates to create networks, and assign
static IP addresses on multiple network interfaces to each machine deployed
to host the Overcloud.

Creating Extra Physical Networks
--------------------------------

A physical network is created on the undercloud Neutron for each
isolated network you wish to create. This is accomplished by using
the Heat OS::Neutron::Net resource within tripleo-heat-templates.
`This review`_ added the isolated network templates, and has a separate
definition file for each isolated network.

.. _This review: https://review.openstack.org/#/c/177843/

By default, each TripleO::Network resource is defined by the
``network/noop.yaml`` file, which does not create a network and instead
always points to the Undercloud 'ctlplane' network (the provisioning
network). The default values in the resource registry may be overridden
in an environment file to enable the networks.

To enable extra networks to be created, each network definition file
needs to be referenced in the environment file.

Example::

  resource_registry:

    # TripleO network architecture
    OS::TripleO::Network: network/networks.yaml
    OS::TripleO::Network::External: network/external.yaml
    OS::TripleO::Network::InternalApi: network/internal_api.yaml
    OS::TripleO::Network::Storage: network/storage.yaml
    OS::TripleO::Network::StorageMgmt: network/storage_mgmt.yaml
    OS::TripleO::Network::Tenant: network/tenant.yaml

.. note::
  It should be noted that creation of these split out networks via
  the tripleo-heat-templates is optional. It is entirely possible
  to use os-cloud-config's setup-neutron script to do the same thing.
  The tripleo-heat-template approach is beneficial in that it allows
  you to customize the networks using environment files with template
  parameters.

Customizing Network CIDR
------------------------

Each network template within the tripleo-heat-templates ``network`` directory
contains parameters that allow you to customize how it is created. One
of the most common changes would be to use a custom network CIDR for
each network. Although default ranges have been specified for each network
type these are editable by setting a parameter value in an environment file.


Example::

  parameter_defaults:

    ExternalNetCidr: 10.0.0.0/24
    InternalApiNetCidr: 172.17.0.0/24
    StorageNetCidr: 172.18.0.0/24
    StorageMgmtNetCidr: 172.19.0.0/24
    TenantNetCidr: 172.16.0.0/24

Network Assignments by Role
---------------------------

Each flavor of OpenStack servers has a set of networks that are associated with
that flavor. The Controller nodes need to connect to every network, but other
flavors only need to connect to a subset of the networks. This is defined in
the role definition file, e.g. ``controller-puppet.yaml``.

Controller: External, Internal API, Storage, Storage Mgmt, Tenant
Compute: Internal API, Storage, Tenant
Object Storage: Storage Mgmt
Block Storage: Storage, Storage Mgmt
Ceph Storage: Storage Mgmt

Assinging OpenStack Services to Isolated Networks
-------------------------------------------------

Each OpenStack service is assigned to a network in the resource registry. The
service will be bound to the host IP within the named network on each host.
A service can be assigned to an alternate network by overriding the service to
network map in an environment file.

Example::

  parameter_defaults:

    ServiceNetMap:
      NeutronLocalIp: tenant
      CeilometerApiNetwork: internal_api
      MongoDbNetwork: internal_api
      CinderApiNetwork: internal_api
      CinderIscsiNetwork: storage
      GlanceApiNetwork: storage
      GlanceRegistryNetwork: internal_api

.. note::
  Although the OpenStack services are divided among these 5 named networks,
  the number of actual physical networks may differ. For instance, if a given
  deployment had no separate storage network, the tenant network could be
  used for both VM connectivity and storage. ServiceNetMap determines which
  networks are used for which services.

Assigning Ports to Each Machine
-------------------------------

Each server will have a set of ports created for it, one on each network
where the server is attached. Each port has an associated IP address, and
the IP addresses are passed on for use by Puppet and os-net-config. The
network interfaces are configured with the IPs by os-net-config, and
Puppet configures the OpenStack services to bind to the IPs.

The mapping of the ports is done in the files in the ``network/ports``
subdirectory in the tripleo-heat-templates.

The following example maps the IP address associated with a port to a
parameter (ip_subnet) which is used to write out the os-net-config configuration
files and the Puppet hieradata.

Example::

  heat_template_version: 2015-04-30

  description: >
    Creates a port on the storage network.

  parameters:
    StorageNetName:
      description: Name of the storage neutron network
      default: storage
      type: string
    ControlPlaneIP: # Here for compatability with noop.yaml
      description: IP address on the control plane
      type: string

  resources:

    StoragePort:
      type: OS::Neutron::Port
      properties:
        network: {get_param: StorageNetName}
        replacement_policy: AUTO

  outputs:
    ip_address:
      description: storage network IP
      value: {get_attr: [StoragePort, fixed_ips, 0, ip_address]}
    ip_subnet:
      # FIXME: this assumes a 2 digit subnet CIDR (need more heat functions?)
      description: IP/Subnet CIDR for the storage network IP
      value:
            list_join:
              - ''
              - - {get_attr: [StoragePort, fixed_ips, 0, ip_address]}
                - '/'
                - {get_attr: [StoragePort, subnets, 0, cidr, -2]}
                - {get_attr: [StoragePort, subnets, 0, cidr, -1]}

Configuring Assigned Ports with Custom os-net-config Templates
--------------------------------------------------------------

The following example configures additional tenant and storage networks
alongside of the default ctlplane network which is used for provisioning and
Heat API updates.

Example::

  heat_template_version: 2014-10-16

  description: >
    Software Config to drive os-net-config for a compute node.

  parameters:
    ExternalIpSubnet:
      description: an ip address on the external network
      type: string
    InternalApiIpSubnet:
      description: an ip address on the internal API network
      type: string
    StorageIpSubnet:
      description: an ip address on the storage network
      type: string
    StorageMgmtIpSubnet:
      description: an ip address on the storage management network
      type: string
    TenantIpSubnet:
      description: an ip address on the tenant network
      type: string


  resources:
    OsNetConfigImpl:
      type: OS::Heat::StructuredConfig
      properties:
        group: os-apply-config
        config:
           os_net_config:
            network_config:
              -
                type: interface
                name: nic1 # Undercloud 'ctlplane' provisioning net
                use_dhcp: true
              -
                type: interface
                name: nic2
                use_dhcp: false
                addresses:
                  -
                    ip_netmask: {get_param: InternalApiIpSubnet}
              -
                type: interface
                name: nic3
                use_dhcp: false
                addresses:
                  -
                    ip_netmask: {get_param: TenantIpSubnet}
              -
                type: interface
                name: nic4
                use_dhcp: false
                addresses:
                  -
                    ip_netmask: {get_param: StorageIpSubnet}
