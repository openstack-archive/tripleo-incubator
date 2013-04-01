VM (on Ubuntu)
==============

(There are detailed instructions available below, the overview and
configuration sections provide background information).

Overview:
* Setup a VM that is your bootstrap node
* Setup N VMs to pretend to be your cluster
* Go to town testing deployments on them.
* For troubleshooting see [troubleshooting.md](troubleshooting.md)

Configuration
-------------

The bootstrap instance expects to run with its eth0 connected to the outside
world, via whatever IP range you choose to setup. You can run NAT, or not, as
you choose. This is how we connect to it to run scripts etc - though you can
equally log in on its console if you like.

As we have not yet taught quantum how to deploy VLANs to bare metal instances,
we're using flat networking, with a single broadcast domain which all the bare
metal machines are connected to.

According, the eth1 of your bootstrap instance should be connected to your bare
metal cloud LAN. The bootstrap VM uses the rfc5735 TEST-NET-1 range -
192.0.2.0/24 for bringing up nodes, and does its own DHCP etc, so do not
connect it to a network shared with other DHCP servers or the like. The
instructions in this document create a bridge device ('br99') on your
machine to emulate this with virtual machine 'bare metal' nodes.


  NOTE: We recommend using an apt/HTTP proxy and setting the http_proxy
        environment variable accordingly.

  NOTE: Building images will be extremely slow on Ubuntu 12.04 (precise). This
        is due to nbd-qemu lacking writeback caching. Using 12.10 will be
        significantly faster.

  NOTE: The CPU architecture specified in several places must be consistent.
        This document's examples use 32-bit arch for the reduced memory footprint.
        If you are running on real hardware, or want to test with 64-bit arch,
        replace i386 => amd64 and i686 => x86_64 in all the commands below.
        Also, you need to edit incubator/localrc and change BM_CPU_ARCH accordingly.

Detailed instructions
---------------------

* git clone this repository to your local machine.

        git clone https://github.com/tripleo/incubator.git

* git clone bm_poseur to your local machine.

        git clone https://github.com/tripleo/bm_poseur.git

* git clone diskimage-builder likewise.

        git clone https://github.com/stackforge/diskimage-builder.git

* Ensure dependencies are installed and required virsh configuration is performed:

        scripts/install-dependencies

* Configure a network for your test environment.
  (This alters your /etc/network/interfaces file and adds an exclusion for
  dnsmasq so it doesn't listen on your test network.)

        cd ~/bm_poseur/
        sudo ./bm_poseur --bridge-ip=none create-bridge

* Activate these changes (alternatively, restart):

        sudo service libvirt-bin restart

* Create your bootstrap VM

        cd ~/diskimage-builder/
        bin/disk-image-create -u base vm devstack local-config stackuser -a i386 -o ~/incubator/bootstrap

  The resulting vm has a user 'stack' with password 'stack'.

* Create your demo image. This can be done in the same environment
  that built the bootstrap image. This is the image that baremetal nova
  will install on each node. You can also download a pre-built image,
  or experiment with different combinations of elements.

        cd ~/diskimage-builder/
        bin/disk-image-create -u base -a i386 -o ~/incubator/demo

* Register the bootstrap image with libvirt.
  This defaults to load the file $(cwd)/bootstrap.qcow2, generated above.

        cd ~/incubator/
        bootstrap/configure-bootstrap-vm

* Start the bootstrap node and log in via the console. Get the IP address
  of eth0, you will need it in a minute.

        sudo virsh start bootstrap
        scripts/get-vm-ip bootstrap

  If you downloaded a pre-built bootstrap image, you will need to customize
  it. See footnote [1].

* Copy the demo image into your bootstrap node's devstack/files/ directory.
  It will get automatically loaded into devstack's glance later on.

        scp ~/incubator/demo.qcow2 <bootstrap-IP>:~/devstack/files/

* If desired, customize your bootstrap environment. This is useful if, for
  example, you want to point devstack at a different branch of Nova.
  Do this by editing ~/incubator/localrc within your bootstrap node.

* By default, the FakePowerManager is enabled.
  If you intend to use the VirtualPowerManager, edit ~/incubator/localrc within
  your bootstrap node, uncomment the following section, and edit it to supply
  VirtualPowerManager with proper SSH credentials for the host system.

        BM_POWER_MANAGER=nova.virt.baremetal.virtual_power_driver.VirtualPowerManager
        EXTRA_BAREMETAL_OPTS=( \
        net_config_template=/opt/stack/nova/nova/virt/baremetal/net-static.ubuntu.template \
        virtual_power_ssh_host=192.168.122.1 \
        virtual_power_type=virsh \
        virtual_power_host_user=my_user \
        virtual_power_host_pass=my_pass \
        )

  NOTE: you must have an SSH server installed and running on the host for the
  VirtualPowerDriver to work, with password-based logins enabled.

  The next step will apply that localrc to the bootstrap devstack.

* Setup the baremetal cloud on the bootstrap node. This will run sudo, so it
  will prompt you for a password when it starts. After that, it may take
  quite a while, depending on network speed and hardware.
  Run this in a shell on the bootstrap node.

        ~/incubator/scripts/demo

  When it finishes, you should see a message like the following:

        stack.sh completed in 672 seconds.

* Back on your host system, create some 'baremetal' node(s) out of KVM
  virtual machines. Nova will PXE boot these VMs as though they were physical
  hardware. You can use bm_poseur to automate this, or if you want to create
  the VMs yourself, see footnote [2] for details on their requirements.

        sudo ~/bm_poseur/bm_poseur --vms 1 --arch i686 create-vm

* Get the list of MAC addresses for all the VMs you have created.
  If you used bm_poseur to create the bare metal nodes, you can run this
  on your laptop to get the MACs:

        ~/bm_poseur/bm_poseur get-macs

  If you are testing on real hardware, see footnote [3].

* Inform Nova on the bootstrap node of these resources by running this inside the bootstrap node:

        ~/incubator/scripts/populate-nova-bm-db.sh -i <MAC> add

  If you have multiple VMs created by bm_poseur, you can simplify this process
  by running the output of the following bash script:

        for mac in $(~/bm_poseur/bm_poseur get-macs); do
            echo ~/incubator/scripts/populate-nova-bm-db.sh -i $mac add
        done

* Wait for the following to show up in the n-cpu log on the bootstrap node (screen -x should attach you to the correct screen session):

        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Auditing locally available compute resources
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free ram (MB): 512 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:327
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free disk (GB): 0 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:328
        2013-01-08 16:43:13 DEBUG nova.compute.resource_tracker [-] Hypervisor: free VCPUs: 1 from (pid=24853) _report_hypervisor_resource_view /opt/stack/nova/nova/compute/resource_tracker.py:333
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free ram (MB): 0
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free disk (GB): 0
        2013-01-08 16:43:13 AUDIT nova.compute.resource_tracker [-] Free VCPUS: 1

* Start the process of provisioning a baremetal node in Nova by running
  this inside the bootstrap node:

        source ~/devstack/openrc
        nova boot --flavor 100 --image demo --key_name default bmtest

  If you chose to use VirtualPowerManager, then nova will start the VM.

  If you chose to use the default FakePowerManager, you will need to
  manually start the VM with:

        sudo virsh start baremetal_0

  You can watch its console to observe the PXE boot/deploy process.
  You can also monitor progress in the 'n-cpu' and 'baremetal' screen sessions
  in the bootstrap node. After the deploy is complete, the node will reboot
  into the demo image.

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

  See localrc and scripts/defaults in the incubator tree on your bootstrap node.
  Also see devstack/lib/baremetal for a full list of options that can
  inform Nova of the environment.

