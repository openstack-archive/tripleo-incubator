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

        cd ~/diskimage-builder/
        bin/disk-image-create vm devstack local-config -a i386 -o ~/incubator/bootstrap

  The resulting vm has a user 'stack' with password 'stack'.

* Register the bootstrap image with libvirt.
  This defaults to load the file $(cwd)/bootstrap.qcow2, generated above

        cd ~/incubator/
        bootstrap/configure-bootstrap-vm

* Start the instance and log in via the console. (The instance is called
  'bootstrap'). Get the IP address of eth0, you will need it in a minute.

        sudo virsh start bootstrap

* Create your demo image. This can be done in the same environment
  that build the bootstrap image. This is the image that baremetal nova
  will install on each VM. You can also download a pre-built image,
  or experiment with different combinations of elements.

        cd ~/diskimage-builder/
        bin/disk-image-create base -a i386 -o ~/incubator/demo

* Copy this image into your bootstrap node devstack/files/ directory.
  It will get automatically loaded into devstack's glance later on.

        scp ~/incubator/demo.qcow2 <bootstrap-IP>:~/devstack/files/

* If you downloaded your bootstrap VM's image, you may need to configure it.

  - Setup a network proxy if you have one (e.g. 192.168.2.1 port 8080)

            echo << EOF >> ~/.profile
            export no_proxy=192.0.2.1
            export http_proxy=http://192.168.2.1:8080/
            EOF

  - Add an ~/.ssh/authorized_keys file
    The image rejects password authentication for security, so you will need to
    ssh out from the VM console. Even if you don't copy your authorized_keys in,
    you will still need to ensure that /home/stack/.ssh/authorized_keys on your
    bootstrap node has some kind of public SSH key in it,
    or the openstack configuration scripts will error.

* Create your 'baremetal' node(s)

 - using KVM create however many hardware nodes your emulated cloud will have,
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
 - You can automate this with bm_poseur, for example:
   
            bm_poseur --vms 5 --arch i386 create-vm

   Note: if you get an error that "arch 'i386' combination is not supported"
         then replace "i386" with "i686"

* If you are running a different environment - e.g. real hardware, custom
  network range etc, edit the incubator environment as needed
  (see incubator/localrc, incubator/scripts/defaults, and
  incubator/scripts/img-defaults).

* Setup the baremetal cloud on the bootstrap node. This will use sudo, so
  don't just wander off and ignore it :). Run this in a shell on the bootstrap
  node.

        ~/incubator/scripts/demo

* Inform baremetal nova about the VMs it should control. Get the list of MACs
  by running this on your laptop:

         bm_poseur get-macs

  Then feed this information to nova by running this inside the bootstrap VM:

         ~/incubator/scripts/populate-nova-bm-db.sh -i <MAC> -j <MAC2> add

  Note that, if your VM only has one MAC, then the second option may be an
  arbitrary fake MAC, such as 12:34:56:78:90:12

* If all went well, you should be able to run this inside the bootstrap node
  to start the process of provisioning a baremetal node on your other VM(s).

        source ~/devstack/openrc
        nova boot --flavor 11 --image demo --key_name default bmtest
        watch nova list

  If 'nova list' shows a status of ACTIVE, you can turn on the VM which
  bm_poseur created and watch its console to observe the PXE boot/deploy process.

         sudo virsh start baremetal_0

