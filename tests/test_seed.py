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

import base


class SeedTest(base.TripleoTest):

    def setUp(self):
        if not os.environ.has_key('SEED_IP'):
            self.fail('$SEED_IP is not set')

        self.endpoint_ip = os.environ['SEED_IP']
        self.keystone_password = 'unset'

        super(SeedTest, self).setUp()

    def testGlanceImages(self):
        image_names = [i.name for i in self.glance_client.images.list()]
        self.assertIn('undercloud', image_names)
        self.assertIn('undercloud-initrd', image_names)
        self.assertIn('undercloud-vmlinuz', image_names)
        self.assertIn('bm-deploy-ramdisk', image_names)
        self.assertIn('bm-deploy-kernel', image_names)
