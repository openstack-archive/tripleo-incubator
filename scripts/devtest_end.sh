#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Save your devtest environment.
##    ::

if [ -e tripleorc ]; then
  echo "Resetting existing $PWD/tripleorc with new values"
  write-tripleorc --overwrite -f tripleorc
else
  write-tripleorc --overwrite -f $TRIPLEO_ROOT/tripleorc
fi

## #. If you need to recover the environment, you can source tripleorc.
##    ::
## 
##      source tripleorc
## 

echo "devtest.sh completed." #nodocs
echo source $TRIPLEO_ROOT/tripleorc to restore all values #nodocs
echo "" #nodocs

## The End!
## 
### --end
