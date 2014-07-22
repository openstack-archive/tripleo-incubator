#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_writerc
## ===============

# #. Writes out a tripleorc file, located in
#    $TRIPLEO_ROOT/tripleorc.

# #. If a tripleorc exists, it will be saved to
#    $TRIPLEO_ROOT/tripleorc.backup. The existing tripleorc will be
#    overwritten.

# #. The resulting tripleorc can be sourced in to restore the
#    environment used in the current run.

### --end
if [ -e tripleorc ]; then
  tripleorc_path=$PWD/tripleorc
else
  tripleorc_path=$TRIPLEO_ROOT/tripleorc
fi

if [ -e $tripleorc_path ]; then
    tripleorc_bak="${tripleorc_path}.backup"
    echo "Resetting existing $PWD/tripleorc with new values"
    echo "A copy of the existing tripleorc may be found in"
    echo "${tripleorc_bak}"
    cp $tripleorc_path $tripleorc_bak
fi

write-tripleorc --overwrite $tripleorc_path
echo source $tripleorc_path to restore all values
echo ""

### --include
## #. If you need to recover the environment, you can source tripleorc.
##    ::

##      source $TRIPLEO_ROOT/tripleorc
### --end
