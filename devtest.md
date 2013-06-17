VM (on Ubuntu)
==============

(There are detailed instructions available below, the overview and
configuration sections provide background information).

Overview:
* Setup SSH access to let the seed node turn on/off other libvirt VMs.
* Setup a VM that is your seed node
* Setup N VMs to pretend to be your cluster
* Go to town testing deployments on them.
* For troubleshooting see [troubleshooting.md](troubleshooting.md)
* For generic deployment information see [Deploying.md](Deploying.md)

Configuration
-------------

The seed instance expects to run with its eth0 connected to the outside world,
via whatever IP range you choose to setup. You can run NAT, or not, as you
choose. This is how we connect to it to run scripts etc - though you can
equally log in on its console if you like.

We use flat networking with all machines on one broadcast domain for dev-test.

The eth1 of your seed instance should be connected to your bare metal cloud
LAN. The seed VM uses the rfc5735 TEST-NET-1 range - 192.0.2.0/24 for
bringing up nodes, and does its own DHCP etc, so do not connect it to a network
shared with other DHCP servers or the like. The instructions in this document
create a bridge device ('br99') on your machine to emulate this with virtual
machine 'bare metal' nodes.


  NOTE: We recommend using an apt/HTTP proxy and setting the http_proxy
        environment variable accordingly in order to speed up the image build
        times.  See footnote [3] to set up Squid proxy.

  NOTE: The CPU architecture specified in several places must be consistent.
	The examples here use 32-bit arch for the reduced memory footprint.  If
	you are running on real hardware, or want to test with 64-bit arch,
	replace i386 => amd64 and i686 => x86_64 in all the commands below. You
	will of course need amd64 capable hardware to do this.

Detailed instructions
---------------------

1. Before you start, check to see that your machine supports hardware
   virtualization, otherwise performance of the test environment will be poor.
   We are currently bringing up an LXC based alternative testing story, which
   will mitigate this, thoug the deployed instances will still be full virtual
   machines and so performance will be significantly less there without
   hardware virtualisation.

1. Also check ssh server is running on the host machine and port 22 is open for
   connections from virbr0 -  VirtPowerManager will boot VMs by sshing into the
   host machine and issuing libvirt/virsh commands. The user these instructions
   use is your own, but you can also setup a dedicated user if you choose.

1. Choose a base location to put all of the source code.

        mkdir ~/tripleo
        export TRIPLEO_ROOT=~/tripleo
        cd $TRIPLEO_ROOT

1. git clone this repository to your local machine.

        git clone https://github.com/tripleo/incubator.git

1. git clone bm_poseur to your local machine.

        git clone https://github.com/tripleo/bm_poseur.git

1. git clone diskimage-builder and the tripleo elements likewise.

        git clone https://github.com/stackforge/diskimage-builder.git
        git clone https://github.com/stackforge/tripleo-image-elements.git

1. Ensure dependencies are installed and required virsh configuration is performed:

        cd $TRIPLEO_ROOT/incubator
        scripts/install-dependencies

1. Configure a network for your test environment.
   This configures libvirt to setup a bridge with no ip address and adds an
   exclusion for dnsmasq so it does not listen on your test network. Note that
   the order of the parameters to bm_poseur is significant : copy-paste this
   line.

        cd $TRIPLEO_ROOT/bm_poseur/
        sudo ./bm_poseur --bridge-ip=none create-bridge

1. Create and start your seed VM. This script invokes diskimage-builder with
   suitable paths and options to create and start a VM that contains an
   all-in-one OpenStack cloud with the baremetal driver enabled, and
   preconfigures it for a development environment.

        cd $TRIPLEO_ROOT/tripleo-image-elements/elements/boot-stack
        sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" config.json

        cd $TRIPLEO_ROOT/incubator/
        scripts/boot-elements boot-stack -o bootstrap

   Your SSH pub key has been copied to the resulting 'bootstrap' VMs root
   user.  It has been started by the boot-elements script, and can be logged
   into at this point.

   The IP address of the VM is printed out at the end of boot-elements.

1. Get the IP of your 'bootstrap' VM

        BOOTSTRAP_IP=`scripts/get-vm-ip bootstrap`

   If you downloaded a pre-built bootstrap image you will need to log into it
   and customise the configuration with in it. See footnote [1].)

1. Create some 'baremetal' node(s) out of KVM virtual machines.
   Nova will PXE boot these VMs as though they were physical hardware.
   You can use bm_poseur to automate this, or if you want to create
   the VMs yourself, see footnote [2] for details on their requirements.

        sudo $TRIPLEO_ROOT/bm_poseur/bm_poseur --vms 1 --arch i686 create-vm

1. Get the list of MAC addresses for all the VMs you have created.
   If you used bm_poseur to create the bare metal nodes, you can run this
   on your laptop to get the MACs:

        MAC=`$TRIPLEO_ROOT/bm_poseur/bm_poseur get-macs`

1. Copy the openstack credentials out of the bootstrap VM, and add the IP:

        scp root@$BOOTSTRAP_IP:stackrc ~/stackrc
        sed -i "s/localhost/$BOOTSTRAP_IP/" ~/stackrc
        source ~/stackrc

__(Note: all of the following commands should be run on your host machine, not inside the bootstrap VM)__
__(Note: if you have set http_proxy or https_proxy to a network host, you must either configure that network host to route traffic to your VM ip properly, or add the BOOTSTRAP_IP to your no_proxy environment variable value.)__

1. Nova tools have been installed in $TRIPLEO_ROOT/openstack-tools - you need
   to source the environment unless you have them installed already.

        . $TRIPLEO_ROOT/openstack-tools/bin/activate

1. Add your key to nova:

        nova keypair-add --pub-key ~/.ssh/id_rsa.pub default

1. Inform Nova on the bootstrap node of these resources by running this:

        nova baremetal-node-create ubuntu 1 512 10
	nova baremetal--interface add 1 $MAC

   If you have multiple VMs created by bm_poseur, you can simplify this process
   by running this script.

        for MAC in $($TRIPLEO_ROOT/bm_poseur/bm_poseur get-macs); do
            nova baremetal-node-create ubuntu 1 512 10 $MAC
            nova baremetal-interface-add $id $MAC
        done

   (This assumes the default flavor of CPU:1 RAM:512 DISK:10. Change values if needed.)

1. Wait for the following to show up in the nova-compute log on the bootstrap node

        ssh root@$BOOTSTRAP_IP "tail -f /var/log/upstart/nova-compute.log"

        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Auditing locally available compute resources
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free ram (MB): 512 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:327
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free disk (GB): 0 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:328
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free VCPUs: 1 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:333
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free ram (MB): 0
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free disk (GB): 0
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free VCPUS: 1

1. Create your base image. This is the image that baremetal nova
   will install on each node. You can also download a pre-built image,
   or experiment with different combinations of elements.

        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create -u ubuntu -a i386 -o base

1. Load the base image into Glance:

        $TRIPLEO_ROOT/incubator/scripts/load-image base.qcow2

1. Allow the VirtualPowerManager to ssh into your host machine to power on vms:

        ssh root@$BOOTSTRAP_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

1. Start the process of provisioning a baremetal node:

        nova boot --flavor 256 --image base --key_name default bmtest

   You can watch its console to observe the PXE boot/deploy process.
   After the deploy is complete, it will reboot into the base image.


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

* [3] Setting Up Squid Proxy

  - Install squid proxy: `apt-get install squid`
  - Set `/etc/squid3/squid.conf` to the following:
<pre><code>
          acl manager proto cache_object
          acl localhost src 127.0.0.1/32 ::1
          acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
          acl localnet src 10.0.0.0/8 # RFC1918 possible internal network
          acl localnet src 172.16.0.0/12  # RFC1918 possible internal network
          acl localnet src 192.168.0.0/16 # RFC1918 possible internal network
          acl SSL_ports port 443
          acl Safe_ports port 80      # http
          acl Safe_ports port 21      # ftp
          acl Safe_ports port 443     # https
          acl Safe_ports port 70      # gopher
          acl Safe_ports port 210     # wais
          acl Safe_ports port 1025-65535  # unregistered ports
          acl Safe_ports port 280     # http-mgmt
          acl Safe_ports port 488     # gss-http
          acl Safe_ports port 591     # filemaker
          acl Safe_ports port 777     # multiling http
          acl CONNECT method CONNECT
          http_access allow manager localhost
          http_access deny manager
          http_access deny !Safe_ports
          http_access deny CONNECT !SSL_ports
          http_access allow localnet
          http_access allow localhost
          http_access deny all
          http_port 3128
          cache_dir aufs /var/spool/squid3 5000 24 256
          maximum_object_size 1024 MB
          coredump_dir /var/spool/squid3
          refresh_pattern ^ftp:       1440    20% 10080
          refresh_pattern ^gopher:    1440    0%  1440
          refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
          refresh_pattern (Release|Packages(.gz)*)$      0       20%     2880
          refresh_pattern .       0   20% 4320
          refresh_all_ims on
         </pre></code>

 - Restart squid: `sudo service squid3 restart`
 - Set http_proxy environment variable: `http_proxy=http://your_ip_or_localhost:3128/`

