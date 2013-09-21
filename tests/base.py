#!/usr/bin/python
# Copyright 2013 Red Hat, Inc.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import os
import unittest


# Activate the virtualenv created by install-dependencies so that we can use
# all the openstack client libraries.
# This must happen before any openstack client libraries are imported
openstack_tools_dir = os.path.join(
                        os.environ['TRIPLEO_ROOT'], 'tripleo-incubator',
                        'openstack-tools')
activate_this = '%s/bin/activate_this.py' % openstack_tools_dir
execfile(activate_this, dict(__file__=activate_this))


import glanceclient
from keystoneclient import v2_0 


class TripleoTest(unittest.TestCase):
    """Base class for tripleo tests.

    Performs common setup tasks that can be reused across different tests.

    Includes tests that are common to the 3 OpenStack clouds that are running
    after devtest: seed, undercloud, and overcloud.

    :cvar endpoint_ip IP address of OpenStack services to connect to and test.
    :type endpoint_ip string
    :cvar keystone_username Keystone username
    :type keystone_username string
    :cvar keystone_password Keystone password
    :type keystone_password string
    :cvar keystone_tenant Keystone tenant
    :type keystone_tenant string
    :cvar auth_url OpenStack Authentication URL
    :type auth_url string
    """

    endpoint_ip = ''
    keystone_username = 'admin'
    keystone_password = ''
    keystone_tenant = 'admin'
    auth_url = 'http://%s:5000/v2.0'

    def setUp(self):
        super(TripleoTest, self).setUp()

        self.auth_url = self.auth_url % self.endpoint_ip
        self.setup_keystone()
        self.setup_glance()

    def setup_keystone(self):
        self.keystone_client = v2_0.client.Client(
                                username=self.keystone_username,
                                password=self.keystone_password,
                                tenant_name=self.keystone_tenant,
                                auth_url=self.auth_url)

    def setup_glance(self):
        endpoint_kwargs = {
            'service_type': 'image',
            'endpoint_type': 'publicURL',
        }
        endpoint = self.keystone_client.service_catalog.url_for(**endpoint_kwargs)

        # glanceclient.shell strips the version off the end of the url as a
        # compatiblity check, so we need to do the same thing here.
        # Unfortunately, glanceclient doesn't expose a simple API to just build
        # a client object the same way that the CLI uses.
        if endpoint.endswith('//v1'):
            endpoint = endpoint.strip('//v1')

        token = self.keystone_client.auth_token
        self.glance_client = glanceclient.Client('1', endpoint, token=token)

    def testKeystoneAdminUser(self):
        users = self.keystone_client.users.list()
        user_names = [u.name for u in users]
        self.assertIn('admin', user_names)
