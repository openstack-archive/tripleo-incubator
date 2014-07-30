Tripleo Style Guidelines
========================

- Step 1: Read the OpenStack Style Guidelines
  http://docs.openstack.org/developer/hacking/
- Step 2: Read Bashate
  http://git.openstack.org/cgit/openstack-dev/bashate/tree/README.rst
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
- Shell scripts should use 4 spaces (not tabs) for indentation.
- No trailing whitespace.
- Files should end with a newline.

Bash
~~~~
- The interpreter is ``/bin/bash``.
- Provide a shebang ``#!/bin/bash`` if you intend your script to be run rather than sourced.
- Use ``set -e`` and ``set -o pipefail`` to exit early on errors.
- Use ``set -u`` to catch typos in variable names.
- Use ``$()`` not `````` for subshell commands.
- Avoid repeated/copy-pasted code. Make it a function, or a shared script, etc.
- A ``do`` goes on the same line as its ``for`` or ``while``
- A ``then`` goes on the same line as its ``if``
- Heredocs must be explicitly ended rather than allowed to run until the end of the file.

Script Input
~~~~~~~~~~~~
- Avoid environment variables as input. Prefer command-line arguments.
- If passing structured data, use JSON in files. Avoid passing substantial amounts of
  bare JSON on the command line. Use process substitution ``<()`` to help with this.

Variables
~~~~~~~~~
- Within a shell script, variables that are defined for local use should be
  lower_cased. Variables that are passed in or come from outside the script
  should be UPPER_CASED.

References
----------

