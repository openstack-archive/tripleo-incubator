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

* Create your demo image. This can be done in the same environment
  that built the bootstrap image. This is the image that baremetal nova
  will install on each node. You can also download a pre-built image,
  or experiment with different combinations of elements.

        cd ~/diskimage-builder/
        bin/disk-image-create base -a i386 -o ~/incubator/demo

* Register the bootstrap image with libvirt.
  This defaults to load the file $(cwd)/bootstrap.qcow2, generated above.

        cd ~/incubator/
        bootstrap/configure-bootstrap-vm

* Start the bootstrap node and log in via the console. Get the IP address
  of eth0, you will need it in a minute.

        sudo virsh start bootstrap

  If you downloaded a pre-built bootstrap image, you will need to customize
  it. See footnote [1].

* Copy the demo image into your bootstrap node's devstack/files/ directory.
  It will get automatically loaded into devstack's glance later on.

        scp ~/incubator/demo.qcow2 <bootstrap-IP>:~/devstack/files/

* Setup the baremetal cloud on the bootstrap node. This will run sudo, so it
  will prompt you for a password when it starts. After that, it may take
  quite a while, depending on network speed and hardware.
  Run this in a shell on the bootstrap node.

        ~/incubator/scripts/demo

  When it finishes, you should see a message like the following:

        stack.sh completed in 672 seconds.

* Create some 'baremetal' node(s) out of KVM virtual machines. Nova
  will PXE boot these VMs as though they were physical hardware. You can
  use bm_poseur to automate this, or if you want to create the VMs yourself,
  see footnote [2] for details on their requirements.
   
        sudo ~/bm_poseur/bm_poseur --vms 1 --arch i686 create-vm

* Get the list of MAC addresses for all the VMs you have created.
  If you used bm_poseur to create the bare metal nodes, you can run this
  on your laptop to get the MACs:

        ~/bm_poseur/bm_poseur get-macs

  Note that each VM is given two NICs, so the MAC addresses for a single VM
  are printed as a comma-separated pair.

  If you are testing on real hardware, see footnote [3].

* Inform Nova of these resources by running this inside the bootstrap node:

        ~/incubator/scripts/populate-nova-bm-db.sh -i <MAC_1> -j <MAC_2> add

  If you have multiple VMs created by bm_poseur, you can simplify this process
  by running the output of the following bash script:

        for macs in $(~/bm_poseur/bm_poseur get-macs); do 
            i=${macs%%,*} && j=${macs##*,} 
            echo ~/incubator/scripts/populate-nova-bm-db.sh -i $i -j $j add 
        done

* Start the process of provisioning a baremetal node in Nova by running
  this inside the bootstrap node:

        source ~/devstack/openrc
        nova boot --flavor 11 --image demo --key_name default bmtest
        watch nova list

  Once 'nova list' shows a status of ACTIVE, you can turn on the VM which
  bm_poseur created:

        sudo virsh start baremetal_0

  Watch its console to observe the PXE boot/deploy process. You can also monitor
  progress in the 'baremetal' screen session in the bootstrap node. After the
  deploy is complete, the node will reboot into demo image.

  The End!
  


Footnotes
=========

* [1] Customize a downloaded bootstrap image.

  If you downloaded your bootstrap VM's image, you may need to configure it.
  Setup a network proxy, if you have one (e.g. 192.168.2.1 port 8080)

        echo << EOF >> ~/.profile
        export no_proxy=192.0.2.1
        export http_proxy=http://192.168.2.1:8080/
        EOF

  Add an ~/.ssh/authorized_keys file. The image rejects password authentication
  for security, so you will need to ssh out from the VM console. Even if you
  don't copy your authorized_keys in, you will still need to ensure that
  /home/stack/.ssh/authorized_keys on your bootstrap node has some kind of
  public SSH key in it, or the openstack configuration scripts will error.

* [2] Requirements for the "baremetal node" VMs

  If you don't use bm_poseur, but want to create your own VMs, here are some
  suggestions for what they should look like.
   - each VM should have two NICs
   - both NICs should be on br99
   - record the MAC addresses for each NIC
   - give each VM no less than 2GB of disk, and ideally give them
     more than BM_FLAVOR_ROOT_DISK, which defaults to 2GB
   - 512MB RAM is probably enough
   - if using KVM, specify that you will install the virtual machine via PXE.
     This will avoid KVM prompting for a disk image or installation media.

* [3] Notes for physical hardware environments

  If you are running a different environment, e.g. real hardware, you will
  need to edit the incubator environment as needed within the bootstrap
  node prior to running incubator/scripts/demo.

  See localrc, scripts/defaults, and scripts/img-defaults.
  Also see devstack/lib/baremetal for a full list of options that can
  inform Nova of the environment.

