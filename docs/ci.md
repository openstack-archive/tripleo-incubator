CI For TripleO
==============

Eventually, if/when TripleO becomes an official Openstack project, all CI for
it should be on Openstack systems. Until then we still need CI.

Jenkins
-------

* Jenkins from jenkins apt repo.
* IRC notification service, notify-only on #triple on freenode, port 7000 ssl.
* Github OAuth plugin, permit all from tripleo organisation, and organisation
  members as service admins.
* Grant jenkin builders sudo [may want lxc containers or cloud instances for
  security isolation]
*
* Jobs to build:
 * bootstrap VM from-scratch (archive bootstrap.qcow2).
   demo/make-bootstrap-image
 * baremetal devstack execution (archive the resulting image).
 * bootstrap VM via image-build chain (archive bm-cloud.qcow2).
 * baremetal SPOF node build (archive the resulting image).
 * baremetal demo node build (archive the resulting image).
 * Tempest w/baremetal using libvirt networking as the power API.
