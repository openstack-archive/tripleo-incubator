#!/bin/bash

set -eu
set -o pipefail

### --include
## devtest_end
## ============

## If you need to recover the environment, you can source tripleorc::
##     source $TRIPLEO_ROOT/tripleorc
##
## The End!
##
### --end

echo "devtest.sh completed."
echo source $tripleorc_path to restore all values
echo ""

