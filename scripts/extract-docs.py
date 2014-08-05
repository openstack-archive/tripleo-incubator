#!/usr/bin/env python
# encoding: utf-8

# Copyright 2013 Hewlett-Packard Development Company, L.P.
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
#

"""Pre-processor for munging files before inestion by sphinx.

Read a file with embedded comments and:
 - discard undesired portions
 - strip leading '## ' from lines
 - indent other non-empty lines by 8 spaces

This allows a script to have copious documentation but also be presented as a
markdown / ReST file.


"""

from __future__ import print_function

import re


import begin

@begin.start
def run(filename, begin_enabled=False):
    """Process FILENAME for ingestion by sphinx.
    
    If begin-enabled is true, processing will start from the first line.
    If begin-enabled is false, processing will start from the first --include"""
    
    _enabled=begin_enabled

    with open(filename) as infile:
        for line in infile:
            output = None
            if re.search("^### --include", line):
                _enabled=True
                output="\n"
            elif re.search("^### --end", line):
                _enabled=False
                output="\n"
            elif re.search("#nodocs$", line):
                output="\n"
            elif re.match("^$", line):
                output=line

            if not output:
                if not _enabled:
                    output = "\n"
                elif re.match("## ", line):
                    output = line[3:]
                else:
                    output = "%s%s" %("        ", line)

            print(output,end="")

