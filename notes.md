VM (on Ubuntu):

Overview:
* Setup a VM that is your bootstrap node
* Setup N machines to pretend to be your cluster
* Go to town testing deployments on them.

Details:

* add a bridge to your own machine - e.g. ooodemo
in /etc/network/interfaces:
iface ooodemo inet manual
    # If you want ip4 connectivity from your machine to the demo environment
    # address 192.168.2.1
    # netmask 255.255.255.0
    # If you want to bridge it onto your LAN - possibly unwise as DHCP requests
    # will have to race to be answered by the demo bootstrap VM rather than
    # your LAN DHCP server. It may be better to use NAT - but if so configure
    # NAT by hand: Do not use the libvirt NAT environment, because you don't
    # want dnsmasq answering DHCP queries for these VM's.
    # bridge_ports eth0
and add ooodemo to the 'auto' line.

This sets up a bridge that we will use to communicate between a 'bootstrap' VM and the VM's that will pretend to be bare metal. 

will bridge that onto eth0. It doesn't need any ports at all, unless you want to have remote access to it.

* Exclude that bridge from dnsmasq:
 - add except-interface=ooodemo to your dnsmasq setup (e.g. in a file in /etc/dnsmasq.d/foo)

* Activate these changes:
 - sudo service networking restart
 - sudo service libvirt-bin restart

* Create your bootstrap VM:
 - download an Ubuntu 12.10 .iso
 - using the libvirt GUI or command line (your choice) create a new VM, Give it 1GB of memory, 8GB of disk and - this is the key bit - tell it to use the ooodemo shared network device rather than the default NAT set.
 - install Ubuntu into that VM
 - reboot it and manually configure its network:
   192.168.2.2 netmask 255.255.255.0 gateway (if you set up NAT) 192.168.2.1
 - grab devstack (from where?)
 - grab the localrc for devstack (from where)
 - run devstack

* Create your deployment images
 - <here be dragons>

 1) ubuntu desktop machine
 • wired network no DHCP
 • devstack with patch?
 • wired network with no DHCP server
 • devstack with a minor patch (ah! i need to push this to github)
 • fancy localrc file (ah! I should stick this somewhere for everyone)
 • our nova branch
 • deploy kernel and ramdisk made by NTT's script (or NobodyCam's version thereof)
 10:11 < devananda> - some luck

