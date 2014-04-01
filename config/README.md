TripleO Configuration
=====================

This directory holds the configuration information that is used by a devtest.sh run.

This is intended to provide defined inputs that are usable by the developer-focused
incubator scripts, but also to allow the inputs to be separated from the developer
scripts and specified independently.  One such use-case for this is to allow for the
configuration to exist in a git repository of its own that many users can then
contribute to independently of the mechanics that process the input.

Initially devtest.sh is being changed to work with the configuration directories,
but over time it is expected that the individual tools should be able to parse the
configuration directories directly.

    e.g. disk-image-create --config-dir /path/to/here

The first set of configurations are for the default devtest at the time of writing
this.  As per the thoughts expressed in [devtest-env-reqs][1] this could be used to
provide other supported configurations, such as a ha or minimal configuration.

Over time, it is expected that there will be a python tool that will read the
configuration (possibly os-apply-config, or a wrapper that uses that), and
another tool that will write changes to the configuration.  Such tools could
abstract high-level choices between things to make them options to the reading of the
configurations rather than requiring configuration changes to select them.

[1]: https://etherpad.openstack.org/p/devtest-env-reqs
