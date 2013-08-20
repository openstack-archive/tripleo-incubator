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
create a bridge device ('brbm') on your machine to emulate this with virtual
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

__(Note: all of the following commands should be run on your host machine, not inside the seed VM)__

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

1. Check that the default libvirt connection for your user is qemu:///system.
   If it is not, set an environment variable to configure the connection.
   This configuration is necessary for consistency, as later steps assume
   qemu:///system is being used.

        # Check the output of "virsh uri"
        virsh uri
        # If it's not qemu:///system, export the following environment variable.
        export LIBVIRT_DEFAULT_URI=qemu:///system

1. Choose a base location to put all of the source code.

        mkdir ~/tripleo
        # exports are ephemeral - new shell sessions, or reboots, and you need
        # to redo them.
        export TRIPLEO_ROOT=~/tripleo
        cd $TRIPLEO_ROOT

1. git clone this repository to your local machine.

        git clone https://github.com/openstack/tripleo-incubator.git

1. Nova tools get installed in $TRIPLEO_ROOT/tripleo-incubator/scripts - you need to
   add that to the PATH.

        export PATH=$PATH:$TRIPLEO_ROOT/tripleo-incubator/scripts

1. Ensure dependencies are installed and required virsh configuration is
   performed:

        install-dependencies

1. Clone/update the other needed tools which are not available as packages.

        pull-tools

1. You need to make the tripleo image elements accessible to diskimage-builder:

        export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-image-elements/elements

1. Configure a network for your test environment.
   This configures an openvswitch bridge and teaches libvirt about it. 

        setup-network

1. Create a deployment ramdisk + kernel. These are used by the seed cloud and
   the undercloud for deployment to bare metal.

        $TRIPLEO_ROOT/diskimage-builder/bin/ramdisk-image-create -a i386 \
            ubuntu deploy -o deploy-ramdisk

1. Create and start your seed VM. This script invokes diskimage-builder with
   suitable paths and options to create and start a VM that contains an
   all-in-one OpenStack cloud with the baremetal driver enabled, and
   preconfigures it for a development environment.

        cd $TRIPLEO_ROOT/tripleo-image-elements/elements/seed-stack-config
        sed -i "s/\"user\": \"stack\",/\"user\": \"`whoami`\",/" config.json

        cd $TRIPLEO_ROOT
        boot-seed-vm

   Your SSH pub key has been copied to the resulting 'seed' VM's root
   user.  It has been started by the boot-elements script, and can be logged
   into at this point.

   The IP address of the VM is printed out at the end of boot-elements, or
   you can use the get-vm-ip script:

        export SEED_IP=`get-vm-ip seed`

1. Add a route to the baremetal bridge via the seed node (we do this so that
   your host is isolated from the networking of the test environment.

        # These are not persistent, if you reboot, re-run them.
        sudo ip route del 192.0.2.0/24 dev virbr0 || true
        sudo ip route add 192.0.2.0/24 dev virbr0 via $SEED_IP

1. Mask the SEED_IP out of your proxy settings

        export no_proxy=$no_proxy,192.0.2.1,$SEED_IP

1. If you downloaded a pre-built seed image you will need to log into it
   and customise the configuration within it. See footnote [1].)

1. Source the client configuration for the seed cloud.

        source $TRIPLEO_ROOT/tripleo-incubator/seedrc

1. Create some 'baremetal' node(s) out of KVM virtual machines.
   Nova will PXE boot these VMs as though they were physical hardware.
   If you want to create the VMs yourself, see footnote [2] for details on
   their requirements. The parameters to create-nodes are cpu count, memory
   (MB), disk size (GB), vm count.

        create-nodes 1 1024 10 3

1. Get the list of MAC addresses for all the VMs you have created.

        export MACS=`$TRIPLEO_ROOT/bm_poseur/bm_poseur get-macs`

1. Perform setup of your seed cloud. The 1 1024 10 is CPU count, memory in MB,
   disk in GB for your test nodes.

        SERVICE_TOKEN=unset setup-endpoints 192.0.2.1
        user-config
        setup-baremetal 1 1024 10 seed
        setup-neutron 192.0.2.2 192.0.2.3 192.0.2.0/24 192.0.2.1 ctlplane

1. Allow the VirtualPowerManager to ssh into your host machine to power on vms:

        ssh root@192.0.2.1 "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

1. Create your undercloud image. This is the image that the seed nova
   will deploy to become the baremetal undercloud. Note that stackuser is only
   there for debugging support - it is not suitable for a production network.

        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create ubuntu \
            -a i386 -o undercloud boot-stack nova-baremetal heat-cfntools \
            stackuser

1. Load the undercloud image into Glance:

        load-image undercloud.qcow2

1. Deploy an undercloud:

        heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/undercloud-vm.yaml \
          -P "PowerUserName=$(whoami)" undercloud

   You can watch the console via virsh/virt-manager to observe the PXE
   boot/deploy process.  After the deploy is complete, it will reboot into the
   image.

1. Get the undercloud IP from 'nova list'

   export UNDERCLOUD_IP=$(nova list | grep ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

1. Source the undercloud configuration:

        source $TRIPLEO_ROOT/tripleo-incubator/undercloudrc

1. Exclude the undercloud from proxies:

        export no_proxy=$no_proxy,$UNDERCLOUD_IP

1. Perform setup of your undercloud. The 1 1024 10 is CPU count, memory in MB, disk
   in GB for your test nodes.

        SERVICE_TOKEN=unset setup-endpoints $UNDERCLOUD_IP
        user-config
        setup-baremetal 1 1024 10 undercloud
        setup-neutron 192.0.2.5 192.0.2.24 192.0.2.0/24 $UNDERCLOUD_IP ctlplane

1. Allow the VirtualPowerManager to ssh into your host machine to power on vms:

        ssh heat-admin@$UNDERCLOUD_IP "cat /opt/stack/boot-stack/virtual-power-key.pub" >> ~/.ssh/authorized_keys

1. Create your overcloud control plane image. This is the image the undercloud
   will deploy to become the KVM (or Xen etc) cloud control plane. Note that
   stackuser is only there for debugging support - it is not suitable for a
   production network.

        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create ubuntu \
            -a i386 -o overcloud-control boot-stack cinder heat-cfntools \
            neutron-network-node stackuser

1. Load the image into Glance:

        load-image overcloud-control.qcow2

1. Create your overcloud compute image. This is the image the undercloud
   deploys to host KVM instances. Note that stackuser is only there for
   debugging support - it is not suitable for a production network.

        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create ubuntu \
            -a i386 -o overcloud-compute nova-compute nova-kvm \
            neutron-openvswitch-agent heat-cfntools stackuser

1. Load the image into Glance:

        load-image overcloud-compute.qcow2

1. Deploy an overcloud:

        make -C $TRIPLEO_ROOT/tripleo-heat-templates overcloud.yaml
        heat stack-create -f $TRIPLEO_ROOT/tripleo-heat-templates/overcloud.yaml \
          overcloud

   You can watch the console via virsh/virt-manager to observe the PXE
   boot/deploy process.  After the deploy is complete, the machines will reboot
   and be available.

1. Get the overcloud IP from 'nova list'

   export OVERCLOUD_IP=$(nova list | grep notcompute.*ctlplane | sed  -e "s/.*=\\([0-9.]*\\).*/\1/")

1. Source the overcloud configuration:

        source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc

1. Exclude the undercloud from proxies:

        export no_proxy=$no_proxy,$OVERCLOUD_IP

1. Perform admin setup of your overcloud.

        SERVICE_TOKEN=unset setup-endpoints $OVERCLOUD_IP
        user-config
        setup-neutron "" "" 10.0.0.0/8 "" "" 192.0.2.45 192.0.2.64 192.0.2.0/24

1. Workaround https://bugs.launchpad.net/diskimage-builder/+bug/1211165

        nova flavor-delete m1.tiny
        nova flavor-create m1.tiny 1 512 2 1

1. Build an end user disk image and register it with glance.

        $TRIPLEO_ROOT/diskimage-builder/bin/disk-image-create ubuntu \
            -a i386 -o user
        glance image-create --name user --public --disk-format qcow2 \
            --container-format bare --file user.qcow2

1. Log in as a user.

        source $TRIPLEO_ROOT/tripleo-incubator/overcloudrc-user
        user-config

1. Deploy your image.

        nova boot --key-name default --flavor m1.tiny --image user demo

1. Add an external IP for it.

        PORT=$(neutron port-list -f csv -c id --quote none | tail -n1)
        neutron floatingip-create ext-net --port-id "${PORT//[[:space:]]/}"

1. And allow network access to it.

        neutron security-group-rule-create default --protocol icmp \
          --direction ingress --port-range-min 8 --port-range-max 8
        neutron security-group-rule-create default --protocol tcp \
          --direction ingress --port-range-min 22 --port-range-max 22

The End!



Footnotes
=========

* [1] Customize a downloaded seed image.

  If you downloaded your seed VM image, you may need to configure it.
  Setup a network proxy, if you have one (e.g. 192.168.2.1 port 8080)

        # Run within the image!
        echo << EOF >> ~/.profile
        export no_proxy=192.0.2.1
        export http_proxy=http://192.168.2.1:8080/
        EOF

  Add an ~/.ssh/authorized_keys file. The image rejects password authentication
  for security, so you will need to ssh out from the VM console. Even if you
  don't copy your authorized_keys in, you will still need to ensure that
  /home/stack/.ssh/authorized_keys on your seed node has some kind of
  public SSH key in it, or the openstack configuration scripts will error.

  You can log into the console using the username 'stack' password 'stack'.

* [2] Requirements for the "baremetal node" VMs

  If you don't use bm_poseur, but want to create your own VMs, here are some
  suggestions for what they should look like.
   - each VM should have 1 NIC
   - eth0 should be on brbm
   - record the MAC addresses for the NIC of each VM.
   - give each VM no less than 2GB of disk, and ideally give them
     more than BM_FLAVOR_ROOT_DISK, which defaults to 2GB
   - 1GB RAM is probably enough (512MB is not enough to run an all-in-one
     OpenStack), and 768M isn't enough to do repeated deploys with.
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

