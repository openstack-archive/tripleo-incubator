#!/usr/bin/python
#
# Copyright (c) 2014 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

'''
Deep-merge JSON-formatted strings provided via a command line. Arrays met on
the same level and same path are concatenated. In case if only one string
provided, this utility can be used as JSON formatter (with -p).
'''

import argparse
import json

parser = argparse.ArgumentParser(description='Utility to merge JSON strings')
parser.add_argument('-p', '--pretty', action='store_true',
                    help='pretty-format JSON output')
parser.add_argument('json_string', nargs='+', help='JSON string to merge')
args = parser.parse_args()


def dict_merge(d1, d2):
    '''Performs a merge of 2 dictionaries, potentially with recursion'''
    for k in d2.keys():
        if k in d1 and isinstance(d1[k], dict) and isinstance(d2[k], dict):
            dict_merge(d1[k], d2[k])
        elif k in d1 and isinstance(d1[k], list) and isinstance(d2[k], list):
            d1[k] = d1[k] + d2[k]
        else:
            d1[k] = d2[k]

if __name__ == '__main__':
    out = json.loads(args.json_string[0])
    for j in args.json_string[1:]:
        dict_merge(out, json.loads(j))

    if args.pretty:
        print json.dumps(out, sort_keys=True, indent=4)
    else:
        print json.dumps(out)