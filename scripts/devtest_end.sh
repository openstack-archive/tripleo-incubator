#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Save your devtest environment::

##      write-tripleorc --overwrite $TRIPLEO_ROOT/tripleorc

### --end
if [ -e tripleorc ]; then
  echo "Resetting existing $PWD/tripleorc with new values"
  tripleorc_path=$PWD/tripleorc
else
  tripleorc_path=$TRIPLEO_ROOT/tripleorc
fi
write-tripleorc --overwrite $tripleorc_path

echo "devtest.sh completed."
echo source $tripleorc_path to restore all values
echo ""

### --include
## #. If you need to recover the environment, you can source tripleorc.
##    ::

##      source $TRIPLEO_ROOT/tripleorc


## The End!
##
### --end
