Using TripleO
=============

Learning
--------

Learning how TripleO all works is essential. Highly recommended is walking
through :doc:`devtest`.

Setup
-----

The incubator install-dependencies will install the basic tools needed to
build and deploy images via TripleO. What it won't do is larger scale tasks
like configuring a Ubuntu/Fedora/etc mirror, a pypi mirror, squid or similar
HTTP caches etc. If you are deploying rarely, these things are optional.

However, if you are building lots of images, having a local mirror of the
things you are installing can be extremely advantageous.

Operating
---------

The general design of TripleO is intended to produce small unix-like tools
that can be used to drive arbitrary cloud deployments. It is expected that
you will either wrap them in higher order tools (such as CM tools, custom UI's
or even just targeted scripts). TripleO is building a dedicated API to unify
all these small tools for common case deployments, called Tuskar, but that is
not yet ready for prime time. We'll start using it ourselves as it becomes
ready.

Take the time to learn the plumbing - nova, nova-bm or ironic, glance, keystone
etc.
