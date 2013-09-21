# TripleO tests

These tests are a testsuite that can be run against the 3 OpenStack clouds that
get set up as part of devtest.  The tests are functional in nature in that they
connect directly to the services to verify that everything got setup correctly.

Some tests are common across the 3 OpenStack clouds that are running at the end
of devtest (seed/undercloud/overcloud).  The framework allows for specifying
these common tests once, and also for writing tests that are specific to just
1 or 2 of the clouds.

See the test modules themselves for examples of how to write tests.

## Running the tests

Tests should be run from the `tripleo-incubator/tests` directory.

Additionally, you **must** have all the environment variables that are defined as
part of devtest defined in the shell that you are using to run tests.  These
environment variables are used by the tests for both set up configuration and
test verification.

You can use python's nose library to execute the tests (we may look at
integrating with testr and/or tox at a later date).

    nosetests

To test just one of the clouds:

    nosetests test_seed
    nosetests test_undercloud
    nosetests test_overcloud
