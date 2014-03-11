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

#################
#
# Read a shell script with embedded comments and:
#  - discard undesired portions
#  - strip leading '## ' from lines
#  - indent other non-empty lines by 8 spaces
#  - output the result to a nominated file
# This allows a script to have copious documentation but also be presented as a
# markdown / ReST file.
#

/^### --include/ {
    for (;;) {
        if ((getline line) <= 0)
            unexpected_eof()
        if (line ~ /^### --end/)
            break
        if (match(line, ".* #nodocs$"))
            continue
        if (line ~ /dirname..0/)
            sub(/..dirname..0./, ".", line)
        if (substr(line, 0, 3) == "## ") {
            line = substr(line, 4);
        } else if (line != "") {
            line = "        "line
        }
        print line > "/dev/stdout"
    }
}


function unexpected_eof() {
    printf("%s:%d: unexpected EOF or error\n", FILENAME, FNR) > "/dev/stderr"
    exit 1
}


END {
    if (curfile)
        close(curfile)
}

# vim:sw=4:sts=4:expandtab:textwidth=79
