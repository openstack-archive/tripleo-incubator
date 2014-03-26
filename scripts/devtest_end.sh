#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Save your devtest environment.
##    ::

### --end
if [ -e tripleorc ]; then
  echo "Resetting existing $PWD/tripleorc with new values"
  write-tripleorc --overwrite tripleorc
else
### --include
  write-tripleorc --overwrite $TRIPLEO_ROOT/tripleorc
fi #nodocs

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
