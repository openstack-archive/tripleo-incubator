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

Spacing and Indentation
=======================
- Shell scripts should use 4 spaces (not tabs) for indentation.
- No trailing whitespace.
- Files should end with a newline.
- Wrap lines at 100 chars.


Bash-isms
=========
- The interpreter is /bin/bash.
- Use "set -e" and "set -o pipefail" to exit early on errors.
- Use "set -u" to catch typos in variable names.
- Variables should be double-quoted and braced: "${VAR}" not $VAR.
- Use $() not `` for subshell commands.
- Prefer [] for tests over [[]]
- Use functions to avoid repetition.

Script Input
============
- Do not use environment variables as input. Prefer command-line arguments.
- If passing structured data, use JSON in files. Do not pass bare JSON on the
  command line. Use process substitution <() to help with this.

Variables
=========
- Boolean properties should be unset::
    MY_FLAG=
  for false, and a value of 1 for true. Test with -n or -z.
- Within a shell script, variables that are defined for local use should be
  lower_cased. Variables that are passed in or come from outside the script
  should be UPPER_CASED.

