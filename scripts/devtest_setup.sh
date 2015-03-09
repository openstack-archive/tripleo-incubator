#!/bin/bash
#
# Idempotent one-time setup for devtest.
# This can be run for CI purposes, by passing --trash-my-machine to it.
# Without that parameter, the script will error.
set -eux
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Setup the TripleO devtest environment."
    echo
    echo "Options:"
    echo "    --trash-my-machine -- make nontrivial destructive changes to the machine."
    echo "                          For details read the source."
    echo "    -c                 -- re-use existing source/images if they exist."
    echo
    exit $1
}

CONTINUE=0
USE_CACHE=${USE_CACHE:-0}

TEMP=`getopt -o h,c -l trash-my-machine -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ]; then
    echo "Terminating..." >&2;
    exit 1;
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --trash-my-machine) CONTINUE=1; shift 1;;
        -c) USE_CACHE=1; shift 1;;
        -h) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

if [ "0" = "$CONTINUE" ]; then
    echo "Not running - this script is destructive and requires --trash-my-machine to run." >&2
    exit 1
fi

### --include
## devtest_setup
## =============

## Configuration
## -------------

## The seed instance expects to run with its eth0 connected to the outside world,
## via whatever IP range you choose to setup. You can run NAT, or not, as you
## choose. This is how we connect to it to run scripts etc - though you can
## equally log in on its console if you like.

## We use flat networking with all machines on one broadcast domain for dev-test.

## The eth1 of your seed instance should be connected to your bare metal cloud
## LAN. The seed VM uses this network to bringing up nodes, and does its own
## DHCP etc, so do not connect it to a network
## shared with other DHCP servers or the like. The instructions in this document
## create a bridge device ('brbm') on your machine to emulate this with virtual
## machine 'bare metal' nodes.


## NOTE: We recommend using an apt/HTTP proxy and setting the http_proxy
##       environment variable accordingly in order to speed up the image build
##       times.  See footnote [#f3]_ to set up Squid proxy.

## NOTE: Likewise, setup a pypi mirror and use the pypi element, or use the
##       pip-cache element. (See diskimage-builder documentation for both of
##       these). Add the relevant element name to the DIB_COMMON_ELEMENTS
##       variable.

## .. _devtest-environment-configuration:

## Devtest test environment configuration
## --------------------------------------

## Devtest uses a JSON file to describe the test environment that OpenStack will
## run within. The JSON file path is given by $TE_DATAFILE. The JSON file contains
## the following keys:

## #. arch: The CPU arch which Nova-BM nodes will be registered with.
##    This must be consistent when VM's are created (in devtest_testenv.sh)
##    and when disk images are created (in devtest_seed / undercloud /
##    overcloud. The images are controlled by this testenv key, and VMs
##    are created by the same code that sets this key in the test environment
##    description, so you should only need to change/set it once, when creating
##    the test environment. We use 32-bit by default for the reduced memory
##    footprint. If you are running on real hardware, or want to test with
##    64-bit arch, replace i386 => amd64 in all the commands below. You will of
##    course need amd64 capable hardware to do this.

## #. host-ip: The IP address of the host which will run the seed VM using virsh.

## #. seed-ip: The IP address of the seed VM (if known). If not known, it is
##    looked up locally in the ARP table.

## #. ssh-key: The private part of an SSH key to be used when performing virsh
##    commands on $host-ip.

## #. ssh-user: The SSH username to use when performing virsh commands on
##    $host-ip.

## #. nodes: A list of node metadata. Each node has "memory" in MiB, "cpu" in
##    threads, "arch" (one of i386/amd64/etc), "disk" in GiB, a list of MAC
##    addresses for the node, and "pm_type", "pm_user", "pm_addr", and
##    "pm_password" fields.  Future iterations may add more Ironic power and
##    deploy driver selections here.

##    See the `os-cloud-config documentation
##    <http://docs.openstack.org/developer/os-cloud-config/usage.html#registering-nodes-with-a-baremetal-service>`_
##    for a sample

## #. baremetal-network:  A mapping of metadata describing the bare metal cloud
##    network. This is a flat network which is used to bring up nodes via
##    DHCP and transfer images. By default the rfc5735 TEST-NET-1 range -
##    192.0.2.0/24 is used. The following fields are available (along
##    with the default values for each field):
##    ::

##          {
##              "cidr": "192.0.2.0/24",
##              "gateway-ip": "192.0.2.1",
##              "seed": {
##                  "ip": "192.0.2.1",
##                  "range-start": "192.0.2.2",
##                  "range-end": "192.0.2.20"
##                  "physical_bridge_route": (null),
##                  "public_vlan": (null),
##              },
##              "undercloud": {
##                  "range-start": "192.0.2.21",
##                  "range-end": "192.0.2.40"
##                  "public_vlan": (null)
##              }
##          }

##    The physical_bridge_route and public_vlan keys default to absent, which
##    is suitable for a flat networking environment. When exterior access will
##    be on a vlan they should be filled out. For instance, if TEST-NET-2 were
##    our exterior subnet on VLAN 10, we might have the following as our
##    baremetal network, to use a baremetal router on .1, the seed on .2, and a
##    handful of addresses for both the seed and the undercloud dhcp pools. We
##    would also expect a route to the IPMI network to allow control of machines.
##    The gateway IP and physical_bridge_route if specified are also put into the
##    initial network definitions created by the _seed script, and so are
##    accessible via DHCP to the undercloud instances (and likewise overcloud).
##    ::

##          {
##              "cidr": "192.0.2.0/25",
##              "gateway-ip": "198.51.100.1",
##              "seed": {
##                  "ip": "192.0.2.1",
##                  "range-start": "192.0.2.2",
##                  "range-end": "192.0.2.20",
##                  "physical_bridge_route": {
##                      "prefix": "192.0.2.0/24",
##                      "via": "192.0.2.126"
##                  },
##                  "public_vlan": {
##                      "tag": 10,
##                      "ip": "198.51.100.2/24",
##                      "start": "198.51.100.3",
##                      "finish": "198.51.100.10"
##                  }
##              },
##              "undercloud": {
##                  "range-start": "192.0.2.21",
##                  "range-end": "192.0.2.40",
##                  "public_vlan": {
##                      "start": "198.51.100.11",
##                      "finish": "198.51.100.20"
##                  }
##              }
##          }

## #. power_manager: The class path for a Nova Baremetal power manager.
##    Note that this is specific to operating with Nova Baremetal and is ignored
##    for use with Ironic. However, since this describes the test environment,
##    not the code under test, it should always be present while we support
##    using Nova Baremetal.

## #. seed-route-dev: What device to route traffic for the initial undercloud
##    network. As our test network is unrouteable we require an explicit device
##    to avoid accidentally routing it onto live networks. Defaults to virbr0.

## #. remote-operations: Whether to operate on the local machine only, or
##    perform remote operations when starting VMs and copying disk images.
##    A non-empty string means true, the default is '', which means false.

## #. remote-host: If the test environment is on a remote host, this may be
##    set to the host name of the remote host. It is intended to help
##    provide valuable debug information about where devtest is hosted.

## #. env-num: An opaque key used by the test environment hosts for identifying
##    which environment seed images are being copied into.

## #. undercloud: an object with metadata for connecting to the undercloud in
##    the environment.

## #. undercloud.password: The password for the currently deployed undercloud.

## #. undercloud.endpoint: The Keystone endpoint URL for the undercloud.

## #. undercloud.endpointhost: The host of the endpoint - used for noproxy settings.

## #. overcloud: an object with metadata for connecting to the overcloud in
##    the environment.

## #. overcloud.password: The admin password for the currently deployed overcloud.

## #. overcloud.endpoint: The Keystone endpoint URL for the overcloud.

## #. overcloud.endpointhost: The host of the endpoint - used for noproxy settings.

## XXX: We're currently migrating to that structure - some code still uses
##      environment variables instead.

## Detailed instructions
## ---------------------

## **(Note: all of the following commands should be run on your host machine, not inside the seed VM)**

## #. Before you start, check to see that your machine supports hardware
##    virtualization, otherwise performance of the test environment will be poor.
##    We are currently bringing up an LXC based alternative testing story, which
##    will mitigate this, though the deployed instances will still be full virtual
##    machines and so performance will be significantly less there without
##    hardware virtualization.

## #. As you step through the instructions several environment
##    variables are set in your shell.  These variables will be lost if
##    you exit out of your shell.  After setting variables, use
##    scripts/write-tripleorc to write out the variables to a file that
##    can be sourced later to restore the environment.

## #. Also check ssh server is running on the host machine and port 22 is open for
##    connections from virbr0 -  VirtPowerManager will boot VMs by sshing into the
##    host machine and issuing libvirt/virsh commands. The user these instructions
##    use is your own, but you can also setup a dedicated user if you choose.

### --end
if [ "$USE_CACHE" == "0" ] ; then
    if [ -z "${ZUUL_REF:-''}" ]; then
        cd $TRIPLEO_ROOT/tripleo-incubator ; git pull
    fi
fi

if [ "$NODE_DIST" == 'unsupported' ]; then
    echo 'Unsupported OS distro.'
    exit 1
fi
### --include

## #. Install required system packages
##    ::

if [ "$USE_CACHE" = "0" ] ; then #nodocs
    install-dependencies
fi #nodocs

## #. Clone/update the other needed tools which are not available as packages.
##    The DIB_REPOLOCATION_* and DIB_REPOREF_* environment variables will be used,
##    if set, to select the diskimage_builder, tripleo_image_elements and
##    tripleo_heat_templates to check out. Setting TRIPLEO_ADDITIONAL_PULL_TOOLS
##    to full git URLs will also allow you to add extra repositories to be cloned
##    or updated by the pull-tools script.
##    ::

if [ "$USE_CACHE" = "0" ] ; then #nodocs
    pull-tools
fi #nodocs

## #. Install client tools
##    ::

if [ "$USE_CACHE" = "0" ] ; then #nodocs
    setup-clienttools
fi #nodocs

## #. Ensure current user can manage libvirt resources
##    ::

set-usergroup-membership

## .. rubric:: Footnotes
## .. [#f3] Setting Up Squid Proxy
## 
##    * Install squid proxy
##      ::
## 
##          apt-get install squid
## 
##    * Set `/etc/squid3/squid.conf` to the following
##      ::
## 
##          acl localhost src 127.0.0.1/32 ::1
##          acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
##          acl localnet src 10.0.0.0/8 # RFC1918 possible internal network
##          acl localnet src 172.16.0.0/12  # RFC1918 possible internal network
##          acl localnet src 192.168.0.0/16 # RFC1918 possible internal network
##          acl SSL_ports port 443
##          acl Safe_ports port 80      # http
##          acl Safe_ports port 21      # ftp
##          acl Safe_ports port 443     # https
##          acl Safe_ports port 70      # gopher
##          acl Safe_ports port 210     # wais
##          acl Safe_ports port 1025-65535  # unregistered ports
##          acl Safe_ports port 280     # http-mgmt
##          acl Safe_ports port 488     # gss-http
##          acl Safe_ports port 591     # filemaker
##          acl Safe_ports port 777     # multiling http
##          acl CONNECT method CONNECT
##          http_access allow manager localhost
##          http_access deny manager
##          http_access deny !Safe_ports
##          http_access deny CONNECT !SSL_ports
##          http_access allow localnet
##          http_access allow localhost
##          http_access deny all
##          http_port 3128
##          maximum_object_size 1024 MB
##          cache_dir aufs /var/spool/squid3 5000 24 256
##          coredump_dir /var/spool/squid3
##          refresh_pattern ^ftp:       1440    20% 10080
##          refresh_pattern ^gopher:    1440    0%  1440
##          refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
##          refresh_pattern (Release|Packages(.gz)*)$      0       20%     2880
##          refresh_pattern .       0   20% 4320
##          refresh_all_ims on
## 
##    * Restart squid
##      ::
## 
##          sudo service squid3 restart
## 
##    * Set http_proxy environment variable
##      ::
## 
##          http_proxy=http://your_ip_or_localhost:3128/
## 
## 
### --end
