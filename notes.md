VM (on Ubuntu)
==============

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
instructions in this document create a bridge device ('ooodemo') on your
machine to emulate this with virtual machine 'bare metal' nodes.

Detailed instructions
---------------------

* git checkout this repository to your local machine.

* Configure a network for your test environment.
  (This alters your /etc/network/interfaces file and adds an exclusion for
  dnsmasq so it doesn't listen on your test network.)

        sudo bootstrap/configure-baremetal-network -y

* Activate these changes (alternatively, restart):

        sudo ifup ooodemo
        sudo service libvirt-bin restart

* Create your bootstrap VM (having an HTTP proxy is recommended. If you do
  ensure the http_proxy environment variable is exported):

        bootstrap/make-bootstrap-image

  The resulting vm has a user 'stack' with password 'stack'.

* Register the bootstrap image with kvm:

        bootstrap/configure-bootstrap-vm

* Start the instance and log in via the console. (The instance is called
  'bootstrap').
 - install openssh if you want to ssh in from your host. Do not install other
   network services such as DNS.
 - If you installed ssh you probably want to ssh-copy-id your ssh public key in
   at this point.
 - If you don't copy your SSH id in, you will still need to ensure that
   /home/stack/.ssh/authorized_keys on your bootstrap node has some kind of
   public SSH key in it, or the openstack configuration scripts will error.
 - configure eth1 for communicating with your baremetal nodes - put this at the
   end of your /etc/network/interfaces. The iptables commands expose the
   metadata service needed by the nodes as they boot and permit baremetal nodes
   to access the rest of the world by routing via the bootstrap node (libvirt
   rejects traffic from unknown ip addresses, meaning that using the default
   libvirt nat environment requires the MASQUERADE for the bare metal nodes
   unless you reconfigure libvirt as well).  Alternatively you can create a second
   dedicated bridge on your actual machine, put an ip address on it and configure
   eth0 in the bootstrap node manually or by manually configuring dnsmasq (or
   similar) on your machine to serve on that bridge.

            auto eth1
                iface eth1 inet static
                address 192.0.2.1
                netmask 255.255.255.0
                up iptables -t nat -A PREROUTING -d 169.254.169.254 -p tcp -m tcp --dport 80 -j REDIRECT --to-port 8775
                up iptables -t nat -A POSTROUTING  -s 192.0.2.0/24 -o eth0 -j MASQUERADE
                up ip addr add 192.0.2.33 dev eth1

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

* Configure your bootstrap VM (only needed if you downloaded an image: locally
  created ones inherit these settings during the creation step):

  - Setup a network proxy if you have one (e.g. 192.168.2.1 port 8080):

            echo << EOF >> ~/.profile
            export no_proxy=192.0.2.1
            export http_proxy=http://192.168.2.1:8080/
            EOF

 - if you have varied from the defaults described here, edit the demo
   environment as needed (see demo/localrc, demo/scripts/defaults, and
   demo/scripts/img-defaults).

 - now make all the magic happen (this will use sudo, so don't just wander off
   and ignore it :))

            ~/demo/scripts/demo

 - Inform nova about your baremetal nodes

            scripts/populate-nova-bm-db.sh -i "xx:xx:xx:xx:xx:xx" -j "yy:yy:yy:yy:yy:yy" add

* if all goes well, you should be able to run this to start a node now:

        source ~/devstack/openrc
        # flavor 6 is i386, which will work on 64-bit hardware.
        # use 7 for amd64.
        nova boot --flavor 6 --image bare_metal --key_name default bmtest

