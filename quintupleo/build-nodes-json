#!/usr/bin/env python

import argparse
import json
import os
import sys

from novaclient import client as novaclient

def main():
    parser = argparse.ArgumentParser(
        prog='build-nodes-json.py',
        description='Tool for collecting virtual IPMI details',
    )
    parser.add_argument('--bmc_prefix',
                        dest='bmc_prefix',
                        default='bmc',
                        help='BMC name prefix')
    parser.add_argument('--baremetal_prefix',
                        dest='baremetal_prefix',
                        default='baremetal',
                        help='Baremetal name prefix')
    parser.add_argument('--private_net',
                        dest='private_net',
                        default='private',
                        help='Private network name')
    parser.add_argument('--provision_net',
                        dest='provision_net',
                        default='undercloud',
                        help='Provisioning network name')
    args = parser.parse_args()

    bmc_base = args.bmc_prefix
    baremetal_base = args.baremetal_prefix
    private_net = args.private_net
    provision_net = args.provision_net
    username = os.environ.get('OS_USERNAME')
    password = os.environ.get('OS_PASSWORD')
    tenant = os.environ.get('OS_TENANT_NAME')
    auth_url = os.environ.get('OS_AUTH_URL')
    node_template = {
        'pm_type': 'pxe_ipmitool',
        'mac': '',
        'cpu': '',
        'memory': '',
        'disk': '',
        'arch': 'x86_64',
        'pm_user': 'admin',
        'pm_password': 'password',
        'pm_addr': '',
        }

    if not username or not password or not tenant or not auth_url:
        print 'Source an appropriate rc file first'
        sys.exit(1)

    nova = novaclient.Client(2, username, password, tenant, auth_url)

    bmcs = nova.servers.list(search_opts={'name': bmc_base + '_.*'})
    baremetals = nova.servers.list(search_opts={'name': baremetal_base + '_.*'})
    nodes = []

    for pair in zip(bmcs, baremetals):
        bmc = pair[0]
        baremetal = pair[1]
        node = dict(node_template)
        node['pm_addr'] = bmc.addresses[private_net][0]['addr']
        node['mac'] = [baremetal.addresses[provision_net][0]['OS-EXT-IPS-MAC:mac_addr']]
        flavor = nova.flavors.get(baremetal.flavor['id'])
        node['cpu'] = flavor.vcpus
        node['memory'] = flavor.ram
        node['disk'] = flavor.disk
        nodes.append(node)

    with open('nodes.json', 'w') as node_file:
        contents = json.dumps({'nodes': nodes})
        node_file.write(contents)
        print contents

if __name__ == '__main__':
    main()
