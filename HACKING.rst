TripleO Style Guidelines
========================

- Step 1: Read the OpenStack Style Guidelines [1]_
- Step 2: Read Bashate [2]_
- Step 3: Read on

TripleO Specific Guidelines
-----------------------------

There is plenty of code that does not adhere to these conventions currently.
However it is useful to have conventions as consistently formatted code is
easier to read and less likely to hide bugs. New code should adhere to these
conventions, and developers should consider sensible adjustment of existing
code when working nearby.

Spacing and Indentation
~~~~~~~~~~~~~~~~~~~~~~~
Please follow conventions described in OpenStack style guidelines [1]_ and Bashate [2]_.

Bash
~~~~
As well as those rules described in Bashate [2]_:

- The interpreter is ``/bin/bash``.
- Provide a shebang ``#!/bin/bash`` if you intend your script to be run rather than sourced.
- Use ``set -e`` and ``set -o pipefail`` to exit early on errors.
- Use ``set -u`` to catch typos in variable names.
- Use ``$()`` not `````` for subshell commands.
- Double quote substitutions by default. It's OK not to quote if it's important
  that the result be multiple words. EG given VAR="a b":

    ``echo "${VAR}"``
      quote variables
    ``echo "$(echo a b)"``
      quote subshells
    ``echo "$(echo "${VAR}")"``
      in subshells, the inner quotes must not be escaped
    ``function print_b() { echo "$2"; }; print_b ${VAR}``
      you must omit quotes for a variable to be passed as multiple arguments

- Avoid repeated/copy-pasted code. Make it a function, or a shared script, etc.

Script Input
~~~~~~~~~~~~
- Avoid environment variables as input. Prefer command-line arguments.
- If passing structured data, use JSON.
- Avoid passing substantial amounts of bare data (eg JSON) on the command
  line. It is preferred to place the data in a file and pass the filename.
  Using process substitution ``<()`` can help with this.

Variables
~~~~~~~~~
- Within a shell script, variables that are defined for local use should be
  lower_cased. Variables that are passed in or come from outside the script
  should be UPPER_CASED.

References
----------
.. [1]  http://docs.openstack.org/developer/hacking/
.. [2]  http://git.openstack.org/cgit/openstack-dev/bashate/tree/README.rst
