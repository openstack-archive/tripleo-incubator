Tripleo Style Commandments
==========================

- Step 1: Read the OpenStack Style Commandments
  http://docs.openstack.org/developer/hacking/
- Step 2: Read on

TripleO Specific Commandments
-----------------------------

There is plenty of code that does not adhere to these conventions currently.
However is it useful to have conventions as consistently formatted code is
easier to read and less likely to hide bugs. New code should adhere to these
conventions, and developers should consider sensible adjustment of existing
code when working nearby.

- Shell scripts should use 4 spaces for indentation.
- Boolean properties should use unset, ie
    MY_FLAG=
  for false, and a value of 1 for true
- Within a shell script, variables that are defined for local use should be
  lower_cased. Variables that are passed in or come from outside the script
  should be UPPER_CASED.

