VM (on Ubuntu):

Overview:
* Setup a VM that is your bootstrap node
* Setup N machines to pretend to be your cluster
* Go to town testing deployments on them.

Details:

* add a bridge to your own machine - e.g. ooodemo
  in /etc/network/interfaces:

        iface ooodemo inet manual
            # If you want ip4 connectivity from your machine to the demo environment.
            # This is optional (the demo environment has to be able to reach out which
            # is independent).
            # address 192.168.2.1
            # netmask 255.255.255.0
            # If you want to bridge it onto your LAN - possibly unwise as DHCP requests
            # will have to race to be answered by the demo bootstrap VM rather than
            # your LAN DHCP server. It may be better to use NAT - but if so configure
            # NAT by hand: Do not use the libvirt NAT environment, because you don't
            # want dnsmasq answering DHCP queries for these VM's. Note that you need
            # one of NAT or bridging, as the setup process requires branches of
            # openstack from ye old internets.
            # bridge_ports eth0
            # To do NAT:
            up iptables -t nat -A POSTROUTING -j MASQUERADE -s 192.168.2.0/24

  and add ooodemo to the 'auto' line.

  This sets up a bridge that we will use to communicate between a 'bootstrap'
  VM and the VM's that will pretend to be bare metal. 

* Exclude that bridge from dnsmasq:
 - add except-interface=ooodemo to your dnsmasq setup (e.g. in a file in /etc/dnsmasq.d/foo)

* Activate these changes:
 - sudo service networking restart
 - sudo service libvirt-bin restart

* Create your bootstrap VM:
 - download an Ubuntu 12.10 .iso
 - using the libvirt GUI or command line (your choice) create a new VM, Give it
   1GB of memory, 8GB of disk and - this is the key bit - tell it to use the
   ooodemo shared network device rather than the default NAT set.
 - install Ubuntu into that VM
   - set default user name to "stack", or add as separate user
 - reboot it and manually configure its network. If you use different details,
   adjust everything mentioned in this file, including the localrc, to match.
   + address 192.168.2.2
   + netmask 255.255.255.0
   + gateway (if you set up NAT) 192.168.2.1 or your router (if you bridged)
   + DNS - whatever your DNS details are.
 - If you want to ssh into this machine, ensure openssh-server is installed and
   use ssh-copy-id to copy your public key into it. This will also help
   establish that your VM can reach the internet to obtain packages.

* Configure your bootstrap VM:
 - install git and, as the "stack" user, clone devstack into /home/stack/devstack:
   git clone git://github.com/tripleo/devstack.git
   cd devstack
   git checkout baremetal-dev
 - clone demo into /home/stack/demo
   cd ..
   git clone git://github.com/tripleo/demo.git
 - copy the localrc into devstack (and edit it?)
   cp demo/localrc devstack/localrc
 - run devstack
   cd devstack && ./stack.sh

* Create your deployment images
 - using KVM create however many hardware notes your emulated cloud will have,
   ensuring that for each one you select ooodemo as the network device.
   - Give them no less than 1GB of disk each, we suggest 2GB.
   - 512MB of memory is probably enough.
   - Tell KVM you will install the virtual machine via PXE, as that will avoid
     asking you for a disk image or installation media.
   - A nice trick is to make one then to clone it N-1 times, after powering it
     off.
 - <here be dragons>

devas notes
-----------

* after deploy and run-time images are created, and devstack is started,
  edit and run the following to inform the baremetal hypervisor of your hardware
        export BM_SERVICE_HOST_NAME=
        export BM_TARGET_MAC=
        export BM_FAKE_MAC=
        export BM_KERNEL=vmlinuz-3.2.0-29-generic
        export BM_RAMDISK=bm-deploy-ramdisk.3.2.0-29.img
        export BM_RUN_KERNEL=vmlinuz-3.2.0-29-generic
        export BM_RUN_RAMDISK=initrd.img-3.2.0-29-generic
        cd ~/demo/scripts/
        ./prepare-devstack-for-baremetal.sh
* if all goes well, you should be able to run this to start a node now:
  source ~/devstack/openrc && nova boot --flavor 99 --image bare_metal --key_name default bmtest

* What my home environment looks like
 - 1gE cisco switch (no DHCP)
 - local git and apt mirror
 - a "server" running devstack
 - a "server" available for PXE boot
 - limited bandwidth (monkeys in a tree provide my internet)
