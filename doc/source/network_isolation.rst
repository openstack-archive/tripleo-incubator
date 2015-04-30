TripleO Overcloud Network Isolation
===================================

Intro
-----

This document outlines how to deploy a TripleO overcloud with split
out (isolated) physical networks for various types of traffic.  Using this
approach it is possible to host traffic for specific network tasks
(tenants, storage, cluster managment, etc.) in isolated networks. This is
in contrast to the TripleO default network topology which hosts all traffic
on the same flat ctlplane network used for provisioning within the
Undercloud where tenant traffic runs in a GRE or VXLAN tunnel on the same
physical network.

IP address management is done with Neutron. In this document we describe
how to modify the tripleo-heat-templates to create networks, and assign
static IP addresses on multiple network interfaces to each machine deployed
to host the Overcloud.

Creating extra physical networks
--------------------------------

A physical network is created on the undercloud Neutron for each
isolated network you wish to create. This is accomplished by using
the Heat OS::Neutron::Net resource within tripleo-heat-templates.
To enable extra networks to be created you can edit the
resource registry (overcloud-resource-registry.yaml or
overcloud-resource-registry-puppet.yaml) and configure a
resource for each network you wish to create. By default
all network resources use network/noop.yaml which is a no-op
template that doesn't create any network at all and continues
to use the ctlplane for this type of traffic. Swapping out
the noop.yaml template with a custom network template for
the named resource type will enable that network.

Example::

    resource_registry:

      # TripleO network architecture
      OS::TripleO::Network: network/networks.yaml
      OS::TripleO::Network::InternalApi: network/internal_api.yaml
      OS::TripleO::Network::PublicApi: network/public_api.yaml
      OS::TripleO::Network::ClusterMgmt: network/cluster_mgmt.yaml
      OS::TripleO::Network::Storage: network/storage.yaml
      OS::TripleO::Network::External: network/external.yaml
      OS::TripleO::Network::Tenant: network/tenant.yaml

.. note::
  It should be noted that creation of these split out networks via
  the tripleo-heat-templates is optional. It is entirely possible
  to use os-cloud-config's setup-neutron script to do the same thing.
  The tripleo-heat-template approach is beneficial in that it allows
  you to customize the networks using the resource registry and
  template parameters.

Customizing Network CIDR
------------------------

Each network template within the tripleo-heat-templates ``network`` directory
contains parameters that allow you to customize how it is created. One
of the most common changes might be to use a custom network CIDR for
each network. Although default ranges have been specified for each network
type these are easily editable by setting a parameter value in the
parameter_defaults section of the Heat resource registry environment.

Example::

    parameter_defaults:
      ClusterMgmtNetCidr: 172.0.18.0/24
      ExternalNetCidr: 10.0.2.0/24
      InternalApiNetCidr: 172.0.17.0/24
      PublicApiNetCidr: 10.0.1.0/24
      StorageNetCidr: 172.0.19.0/24
      TenantNetCidr: 172.16.0.0/24

.. note::
  We are making use of parameter_defaults for configuration of these settings
  so that we don't have to wire them into the top level overcloud templates
  within tripleo-heat-templates. This mechanism allows us to cleanly configure
  optional things within nested stacks stacks.


Assigning Ports to each Machine
-------------------------------

Each server will have a set of ports created for it, one on each network.
Each port has an associated IP address, and the IP addresses are passed on for
use by Puppet and os-net-config. The network interfaces are configured with
the IPs by os-net-config, and Puppet configures the OpenStack services to bind
to the IPs.

The mapping of the ports is done in the file ``net_ip_map.yaml``, which is in
the ``network/ports`` subdirectory in the tripleo-heat-templates.

The following example maps the IP address associated with each port to a
parameter which is used to write out the os-net-config configuration files and
the Puppet hieradata.

Example::

    resource_registry:

      OS::TripleO::Network::Ports::NetIpMap: network/ports/net_ip_map.yaml


    net_ip_map.yaml:

      heat_template_version: 2014-10-16

      parameters:
        InternalApiIp:
          type: string
        PublicApiIp:
          type: string
        ClusterMgmtIp:
          type: string
        StorageIp:
          type: string
        ExternalIp:
          type: string
        TenantIp:
          type: string

      outputs:
        net_ip_map:
          description: >
            A Hash containing a mapping of network names to assigned IPs
            for a specific machine.
          value:
            internal_api: {get_param: InternalApiIp}
            public_api: {get_param: PublicApiIp}
            cluster_mgmt: {get_param: ClusterMgmtIp}
            storage: {get_param: StorageIp}
            external: {get_param: ExternalIp}
            tenant: {get_param: TenantIp}

.. note::
     Although the OpenStack services are divided among these 6 named networks,
  the number of actual physical networks may differ. For instance, if a given
  deployment had no separate public_api network, the external network could be
  used for both external VM connectivity and OpenStack Public APIs. The service
  map determines which networks are used for which services.


Assinging OpenStack Services to isolated networks
-------------------------------------------------

TODO (give example of how to map services onto networks using the service_map)


Configuring Assigned Ports with custom os-net-config templates
--------------------------------------------------------------

TODO (give example of how to create a custom os-net-config template
 which configures these IPs as static IPs locally)

The following example configures only an additional tenant network
alongside of the default ctlplane network which is used for
provisioning and Heat API updates.

Example::

  heat_template_version: 2014-10-16

  description: >
    Software Config to drive os-net-config for a simple bridge.

  parameters:
    InternalApiIpSubnet:
      description: an ip address on the internal API network
      type: string
    PublicApiIpSubnet:
      description: an ip address on the public API network
      type: string
    ClusterMgmtIpSubnet:
      description: an ip address on the cluster mgmt network
      type: string
    StorageIpSubnet:
      description: an ip address on the storage network
      type: string
    ExternalIpSubnet:
      description: an ip address on the external network
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
                name: nic2
                use_dhcp: false
                addresses:
                -
                  ip_netmask: {get_param: TenantIpSubnet}
              -
                type: ovs_bridge
                name: {get_input: bridge_name}
                use_dhcp: true
                members:
                  -
                    type: interface
                    name: {get_input: interface_name}
                    primary: true
