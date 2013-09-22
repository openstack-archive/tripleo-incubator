# Copyright (c) 2013 Hewlett-Packard Development Company, L.P.
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


def builder_inited(app):
    app.info('In: ' + os.path.abspath('.'))
    source_dir = app.srcdir
    build_dir = app.outdir
    app.info('Generating devtest from %s into %s' % (source_dir, build_dir))
    os.system('scripts/extract-docs')


def setup(app):
    app.connect('builder-inited', builder_inited)
