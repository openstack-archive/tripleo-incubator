VM (on Ubuntu)
==============

(There are detailed instructions available below, the overview and
configuration sections provide background information).

Overview:
* Setup a VM that is your bootstrap node
* Setup N VMs to pretend to be your cluster
* Go to town testing deployments on them.
* For troubleshooting see troubleshooting.md

Configuration
-------------

The bootstrap instance expects to run with its eth0 connected to the outside
world, via whatever IP range you choose to setup. You can run NAT, or not, as
you choose. This is how we connect to it to run scripts etc - though you can
equally log in on its console if you like.

As we have not yet brought quantum up, we're using flat networking, with a
single broadcast domain which all the bare metal machines are connected to.

According, the eth1 of your bootstrap instance should be connected to your bare
metal cloud LAN. The bootstrap VM uses the rfc5735 TEST-NET-1 range -
192.0.2.0/24 for bringing up nodes, and does its own DHCP etc, so do not
connect it to a network shared with other DHCP servers or the like. The
instructions in this document create a bridge device ('br99') on your
machine to emulate this with virtual machine 'bare metal' nodes.

Detailed instructions
---------------------

* git clone this repository to your local machine.

* git clone https://github.com/tripleo/bm_poseur to your local machine.

* git clone https://github.com/stackforge/diskimage-builder.git likewise.

* Configure a network for your test environment.
  (This alters your /etc/network/interfaces file and adds an exclusion for
  dnsmasq so it doesn't listen on your test network.)

	sudo bm_poseur --bridge-ip=none create-bridge

* Activate these changes (alternatively, restart):

        sudo service libvirt-bin restart

* Create your bootstrap VM
  N.B.: We recommend using an apt/HTTP proxy and setting the http_proxy
         environment variable accordingly.
  N.B.: This build will be extremely slow on Ubuntu 12.04 (precise). This
         is due to nbd-qemu lacking writeback caching. Using 12.10 will be
         significantly faster.

        disk-image-create vm devstack local-config -o bootstrap -a i386

  The resulting vm has a user 'stack' with password 'stack'.

* Register the bootstrap image with libvirt:

        sudo bootstrap/configure-bootstrap-vm

* Start the instance and log in via the console. (The instance is called
  'bootstrap').

        sudo virsh start bootstrap

* sshd is installed. If you built the image locally, your
  ~/.ssh/authorized_keys will have been copied into the stack user on the
  image. The image rejects password authentication for security. if you
  downloaded the image, you will need to get the authorized keys file on
  there yourself (e.g. by sshing out from the VM console).
 - Even if you don't copy your SSH id in, you will still need to ensure that
   /home/stack/.ssh/authorized_keys on your bootstrap node has some kind of
   public SSH key in it, or the openstack configuration scripts will error.

* Configure your bootstrap VM (only needed if you downloaded an image: locally
  created ones inherit these settings during the creation step):

  - Setup a network proxy if you have one (e.g. 192.168.2.1 port 8080):

            echo << EOF >> ~/.profile
            export no_proxy=192.0.2.1
            export http_proxy=http://192.168.2.1:8080/
            EOF

* Create your 'baremetal' nodes.
 - using KVM create however many hardware notes your emulated cloud will have,
   ensuring that for each one you select br99 as the network device.
   - Give them no less than 2GB of disk each - a populated Ubuntu server w/APT
     cache will sit right on 1G, and you need some room to work with...
   - 512MB of memory is probably enough.
   - Tell KVM you will install the virtual machine via PXE, as that will avoid
     asking you for a disk image or installation media.
   - A nice trick is to make one then to clone it N-1 times, after powering it
     off.
   - Specify the MAC address for each node. You need to feed this info
     to the populate-nova-bm-db.sh script later on.
   - Create 2 network cards for each VM: nova baremetal requires 2 NICs.
 - You can automate this with bm_poseur:
   - bm_poseur --vms 10 --arch i386 create-vm

* If you are running a different environment - e.g. real hardware, custom
  network range etc, edit the demo environment as needed (see demo/localrc,
  demo/scripts/defaults, and demo/scripts/img-defaults).

* Setup the bare metal cloud on the bootstrap node. (this will use sudo, so
  don't just wander off and ignore it :). Run this in a shell on the bootstrap
  node.

        BM_DNSMASQ_IFACE=eth0 ~/demo/scripts/demo

* Inform nova about your baremetal nodes

        scripts/populate-nova-bm-db.sh -i "xx:xx:xx:xx:xx:xx" -j "yy:yy:yy:yy:yy:yy" add
        ...

* if all went well, you should be able to run this to start a node now:

        source ~/devstack/openrc
        # flavor 6 is i386, which will work on 64-bit hardware.
        # use 7 for amd64.
        nova boot --flavor 6 --image demo --key_name default bmtest

