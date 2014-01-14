#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## #. Save your devtest environment.
##    ::

write-tripleorc --overwrite

## #. If you need to recover the environment, you can source tripleorc.
##    ::
## 
##      source tripleorc
## 

echo "devtest.sh completed." #nodocs
echo source tripleorc to restore all values #nodocs
echo "" #nodocs

## The End!
## 
### --end
