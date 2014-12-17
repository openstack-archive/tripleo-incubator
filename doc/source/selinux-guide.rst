SELinux Developer Guide
=======================


Do I have a SELinux problem?
----------------------------

At the moment SELinux is set to run in permissive mode in TripleO. This means
that problems are logged but not blocked. To see if you have a SELinux problem
that needs to be fixed, examine /var/log/audit/audit.log in your local
development environment or from the TripleO-ci log archive. You may need to
examine the log files for multiple nodes (undercloud and/or overcloud).

Any line that has "denied" is a problem. This guide will talk about common
problems and how to fix them.


Workflow
--------

All changes are assumed to have been tested locally before a patch is submitted
upstream for review. Testing should include inspecting the local audit.log to
see that no new SELinux errors were logged.

If an error was logged, it should be fixed using the guidelines described below.

If no errors were logged, then the change is submitted for review. In addition
to getting the change to pass ci, the audit.log archived from the ci runs should
be inspected to see no new SELinux errors were logged. Problems should be fixed
until the audit.log is clear of new errors.

The archived audit.log filed can be found in the logs directory for each
individual instance that is brought up. For example the seed instance log files
can be seen here:

http://logs.openstack.org/03/115303/1/check-tripleo/check-tripleo-novabm-overcloud-f20-nonha/e5bef5c/logs/seed_logs/

audit.log is audit.txt.gz.

ps -efZ output can be found in host_info.txt.gz.


Updating SELinux file security contexts
---------------------------------------

The targeted policy expects directories and files to be placed in certain
locations. For example, nova normally has files under /var/log/nova and
/var/lib/nova. Its executables are placed under /usr/bin.

::

    [user@server files]$ pwd
    /etc/selinux/targeted/contexts/files
    [user@server files]$ grep nova *
    file_contexts:/var/lib/nova(/.*)?    system_u:object_r:nova_var_lib_t:s0
    file_contexts:/var/log/nova(/.*)?    system_u:object_r:nova_log_t:s0
    file_contexts:/var/run/nova(/.*)?    system_u:object_r:nova_var_run_t:s0
    file_contexts:/usr/bin/nova-api    --    system_u:object_r:nova_api_exec_t:s0
    file_contexts:/usr/bin/nova-cert    --    system_u:object_r:nova_cert_exec_t:s0

TripleO diverges from what the target policy expects and places files and
executables in different locations. When a file or directory is not properly
labeled the service may fail to startup. A SELinux avc denial is logged to
/var/log/audit.log when SELinux detects that a service doesn't have permission
to access a file or directory.

When the ephemeral element is active, upstream TripleO places /var/log and
/var/lib under the ephemeral mount point, /mnt/state. The directories and files
on these locations may not have the correct file security contexts if they were
installed outside of yum.

The directories and files in the ephemeral disk must be updated to have the
correct security context. Here is an example for nova:

https://github.com/openstack/tripleo-image-elements/blob/master/elements/nova/os-refresh-config/configure.d/20-nova-selinux#L6

::

    semanage fcontext -a -t nova_var_lib_t "/mnt/state/var/lib/nova(/.*)?"
    restorecon -Rv /mnt/state/var/lib/nova
    semanage fcontext -a -t nova_log_t "/mnt/state/var/log/nova(/.*)?"
    restorecon -Rv /mnt/state/var/log/nova

For nova we use semanage to relabel /mnt/state/var/lib/nova with the type
nova_var_lib_t and /mnt/state/var/log/nova with the type nova_var_log_t. Then
we call restorecon to apply the labels.

To see a file's security context run "ls -lZ <filename>".

::

    [user@server]# ls -lZ /mnt/state/var/lib
    drwxr-xr-x. root       root       system_u:object_r:file_t:s0      boot-stack
    drwxrwx---. ceilometer ceilometer system_u:object_r:file_t:s0      ceilometer
    drwxr-xr-x. root       root       system_u:object_r:file_t:s0      cinder
    drwxrwx---. glance     glance     system_u:object_r:glance_var_lib_t:s0 glance
    drwxr-xr-x. mysql      mysql      system_u:object_r:mysqld_db_t:s0 mysql
    drwxrwx---. neutron    neutron    system_u:object_r:neutron_var_lib_t:s0 neutron
    drwxrwxr-x. nova       nova       system_u:object_r:nova_var_lib_t:s0 nova
    drwxrwx---. rabbitmq   rabbitmq   system_u:object_r:rabbitmq_var_lib_t:s0 rabbitmq

TripleO installs many components under /opt/stack/venvs/. Executables under
/opt/stack/venvs/<component>/bin need to be relabeled. For these we do a path
substitution to tell SELinux policy that /usr/bin and
/opt/stack/venvs/<component>/bin are equivalent. When the image is relabeled
during image build or during first boot, SELinux will relabel the files under
/opt/stack/stack/venvs/<component>/bin as if they were installed under /usr/bin.

An example of a path substitution for nova:

https://github.com/openstack/tripleo-image-elements/blob/master/elements/nova/install.d/nova-source-install/74-nova

::

    add-selinux-path-substitution /usr/bin $NOVA_VENV_DIR/bin


Allowing port access
--------------------

Services are granted access to a prespecified set of ports by the
selinux-policy. A list of ports for a service can be seen using

::

    semanage port -l | grep http

You can grant a service access to additional ports by using semanage.

::

    semanage port -a -t http_port_t -p tcp 9876

If the port you are adding is a standard or default port, then it would be
appropriate to also file a bug against upstream SELinux to ask for the policy
to include it by default.


Using SELinux booleans
----------------------

Sometimes a problem can be fixed by toggling a SELinux boolean to allow certain
actions.

Currently we enable two booleans in TripleO.

https://github.com/openstack/tripleo-image-elements/blob/master/elements/keepalived/os-refresh-config/configure.d/20-keepalived-selinux

::

    setsebool -P domain_kernel_load_modules 1

https://github.com/openstack/tripleo-image-elements/blob/master/elements/haproxy/os-refresh-config/configure.d/20-haproxy-selinux

::

    setsebool -P haproxy_connect_any 1

domain_kernel_load_modules is used with the keepalived element to allow
keepalive to load kernel modules.

haproxy_connect_any is used with the haproxy element to allow it to proxy any
port.

When a boolean is enabled, it should be enabled within the element that requires
it.

"semanage boolean -l" lists the booleans that are available in the current
policy.

When would you know to use a boolean? Generating a custom policy for the denials
you are seeing will tell you whether a boolean can be used to fix the denials.

For example, when I generated a custom policy for the haproxy denials I was
seeing in audit.log, the custom policy stated that haproxy_connect_any could be
used to fix the denials.

::

    #!!!! This avc can be allowed using the boolean 'haproxy_connect_any'
    allow haproxy_t glance_registry_port_t:tcp_socket name_bind;

    #!!!! This avc can be allowed using the boolean 'haproxy_connect_any'
    allow haproxy_t neutron_port_t:tcp_socket name_bind;

How to generate a custom policy is discussed in the next section.


Generating a custom policy
--------------------------

If relabeling or toggling a boolean doesn't solve your problem, the next step is
to generate a custom policy used as an hotfix to allow the actions that SELinux
denied.

To generate a custom policy, use this command

::

    ausearch -m AVC | audit2allow -M <custom-policy-name>

.. note:: Not all AVCs should be allowed from an ausearch.  In fact, most of
   them are likely leaked file descriptors, mislabeled files, and bugs in code.

The custom policies are stored under
tripleo-image-elements/elements/selinux/custom-policies. We use a single policy
file for each component (one for nova, keystone, etc..). It is organized as per
component to mirror how the policies are organized upstream. When you generate
your custom policy, instead of dropping in a new file, you may need to edit an
existing policy file to include the new changes.

Each custom policy file must contain comments referencing the upstream bugs
(launchpad and upstream SELinux) that the policy is intended to fix. The
comments help with housekeeping. When a bug is fixed upstream, a developer can
then quickly search for the bug number and delete the appropriate lines from the
custom policy file that are no longer needed.

Example: https://review.openstack.org/#/c/107233/3/elements/selinux/custom-policies/tripleo-selinux-ssh.te


Filing bugs for SELinux policy updates
--------------------------------------

The custom policy is meant to be used as a temporary solution until the
underlying problem is addressed. Most of the time, the upstream SELinux policy
needs to be updated to incorporate the rules suggested by the custom policy. To
ensure that that upstream policy is updated, we need to file a bug against the
selinux-policy package.

For Fedora, use this link to create a bug

https://bugzilla.redhat.com/enter_bug.cgi?component=selinux-policy&product=Fedora

For RHEL 7, use this link to create a bug, and file against the
openstack-selinux component, not the selinux-policy component because it is
released less frequently.

https://bugzilla.redhat.com/enter_bug.cgi?product=Red%20Hat%20OpenStack

Under "Version-Release number" include the package and version of the affected
component.

::

    Example:
    selinux-policy-3.12.1-179.fc20.noarch
    selinux-policy-targeted-3.12.1-179.fc20.noarch
    openssh-6.4p1-5.fc20.i686
    openssh-clients-6.4p1-5.fc20.i686
    openssh-server-6.4p1-5.fc20.i686

Include the ps -efZ output from the affected system. And most importantly
attach the /var/log/audit/audit.log to the bug.

Also file a bug in launchpad, referencing the bugzilla. When you commit the
custom policy into github, the commit message should reference the launchpad
bug id. The launchpad bug should also be tagged with "selinux" to make SELinux
bugs easier to find.

Setting SELinux to enforcing mode
---------------------------------

By default in TripleO, SELinux runs in permissive mode. This is set in the
NODE_DIST environment variable in the devtest scripts.

::

    export NODE_DIST="fedora selinux-permissive"

To set SELinux to run in enforcing mode, remove the selinux-permissive element
by adding this line to your ~/.devtestrc file.

::

    export NODE_DIST="fedora"


Additional Resources
--------------------

1. http://openstack.redhat.com/SELinux_issues
2. http://docs.fedoraproject.org/en-US/Fedora/19/html/Security_Guide/ch09.html

