VM (on Ubuntu):

Overview:
* Setup a VM that is your bootstrap node
* Setup N VMs to pretend to be your cluster
* Go to town testing deployments on them.
* For troubleshooting see troubleshooting.md

Details:

* add a bridge to your own machine - e.g. ooodemo
  in /etc/network/interfaces:

        auto ooodemo
        iface ooodemo inet static
            # If you want ip4 connectivity from your machine to the demo environment.
            # This is optional (the demo environment has to be able to reach out which
            # is independent).
            # address 192.168.2.1
            # netmask 255.255.255.0
            # If you want to bridge it onto your LAN change none to eth0
            # - possibly unwise as DHCP requests will have to race to be
            # answered by the demo bootstrap VM rather than your LAN DHCP
            # server. It may be better to use NAT - but if so configure NAT by
            # hand: Do not use the libvirt NAT environment, because you don't
            # want dnsmasq answering DHCP queries for these VM's. Note that you
            # need one of NAT or bridging, as the setup process requires
            # branches of openstack from ye old internets.
            bridge_ports none
            # To do NAT:
            up iptables -t nat -A POSTROUTING -j MASQUERADE -s 192.168.2.0/24 ! -o ooodemo

  This sets up a bridge that we will use to communicate between a 'bootstrap'
  VM and the VM's that will pretend to be bare metal. 

* Exclude that bridge from dnsmasq:
 - add except-interface=ooodemo to your dnsmasq setup (e.g. in a file in /etc/dnsmasq.d/foo)

* Activate these changes:

        sudo ifup ooodemo
        sudo service libvirt-bin restart

* Create your bootstrap VM:
 - download an Ubuntu 12.10 .iso
 - using the libvirt GUI or command line (your choice) create a new VM, Give it
   1GB of memory, 8GB of disk and - this is the key bit - tell it to use the
   ooodemo shared network device rather than the default NAT set.
 - install Ubuntu into that VM
   - set default user name to "stack", or add as separate user
 - reboot it and manually configure its network. If you use different details,
   adjust everything mentioned in this file, including the localrc, to match.
   Using /etc/network/interfaces, removing resolvconf and editing
   /etc/resolv.conf is probably the most reliable approach.

            address 192.168.2.2
            netmask 255.255.255.0
            gateway 192.168.2.1
            # or your router (if you bridged)
   
   And for /etc/resolv.conf:

            nameserver - whatever your DNS details are.

 - If you want to ssh into this machine, ensure openssh-server is installed and
   use ssh-copy-id to copy your public key into it. This will also help
   establish that your VM can reach the internet to obtain packages.
 - If you don't copy your SSH id in, you will still need to ensure that /home/stack/.ssh/authorized_keys on your bootstrap node has some kind of public SSH key in it

 - Workaround https://bugs.launchpad.net/horizon/+bug/1070083 - (Quantal
   virtual machines).

            cd /usr/bin && sudo ln -s nodejs node; cd ~

* Create your 'baremetal' nodes.
 - using KVM create however many hardware notes your emulated cloud will have,
   ensuring that for each one you select ooodemo as the network device.
   - Give them no less than 1GB of disk each, we suggest 2GB.
   - 512MB of memory is probably enough.
   - Tell KVM you will install the virtual machine via PXE, as that will avoid
     asking you for a disk image or installation media.
   - A nice trick is to make one then to clone it N-1 times, after powering it
     off.
   - Specify the MAC address for each node. You need to feed this info
     to the populate-nova-bm-db.sh script later on.
   - Create 2 network cards for each VM: nova baremetal requires 2 NICs.

* Configure your bootstrap VM:
 - Setup a network proxy if you have one:

            export http_proxy=http://192.168.2.1:8080/
            export no_proxy=192.168.2.2
            echo 'Acquire::http::Proxy "http://192.168.2.1:8080/";' | sudo dd of=/etc/apt/apt.conf.d/60proxy

* Prep bootstrap VM:
 - install git and, as the "stack" user, clone devstack into /home/stack/devstack:

            git clone git://github.com/tripleo/devstack.git
            cd devstack
            git checkout baremetal-dev

 - clone demo into /home/stack/demo

            cd ..
            git clone git://github.com/tripleo/demo.git

 - copy the localrc into devstack

            cp demo/localrc devstack/localrc

 - create deployment ramdisk and kernel

            cd ~stack
            # Until our branch is merged (https://github.com/NTTdocomo-openstack/baremetal-initrd-builder/pull/1)
            # git clone https://github.com/NTTdocomo-openstack/baremetal-initrd-builder.git
            git clone https://github.com/tripleo/baremetal-initrd-builder.git
            cd baremetal-initrd-builder
            git checkout tripleo
            cd ..
            wget http://shellinabox.googlecode.com/files/shellinabox-2.14.tar.gz
            tar xzf shellinabox-2.14.tar.gz
            cd shellinabox-2.14
            sudo apt-get -y install gcc make
            ./configure
            make
            sudo make install

 - Create a cloud image - the baremetal image that will be deployed onto your
   cloud nodes.

            cd ~/demo/scripts
            ./create-baremetal-image.sh


* Start devstack in the bootstrap VM:

 - run devstack

            cd ~/devstack && ./stack.sh
            . ./openrc


 - Load images and configuration into devstack. This will update the nova DB,
   load deployment ramdisk, kernel and image, and create a bare metal flavor.
 
            cd ~/demo
            ./scripts/prepare-devstack-for-baremetal.sh

 - Inform nova about your baremetal nodes

            scripts/populate-nova-bm-db.sh -i "xx:xx:xx:xx:xx:xx" -j "yy:yy:yy:yy:yy:yy" add

* if all goes well, you should be able to run this to start a node now:

        source ~/devstack/openrc
        # flavor 6 is i386, which will work on 64-bit hardware.
        # use 7 for amd64.
        nova boot --flavor 6 --image bare_metal --key_name default bmtest

