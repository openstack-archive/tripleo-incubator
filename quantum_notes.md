The following notes have already been incorporated into the baremetal-quantum-dhcp
branches of devstack and nova, and this (quantum-dhcp) branch of incubator.
Most of the differences are contained in incubator/localrc and devstack/lib/quantum.
There are also several patches to Nova.

These notes are preserved in a single place just for clarity.
You do not need to follow these instructions.

----------------------------------

After starting devstack, fixup your quantum networking.
You want a provider network, connected through to eth1, with ip addresses on the bridge.

/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini should already have the following two lines, but check just in case:
   network_vlan_ranges=ctlplane
   bridge_mappings=ctlplane:br-ctlplane

you will need to add a port to the bridge
   sudo ovs-vsctl add-port br-ctlplane eth1

and move ip addresses to it
   sudo ip addr del 192.0.2.1/24 dev eth1
   sudo ip addr del 192.0.2.33/29 dev eth1
   sudo ip addr add 192.0.2.33/29 dev br-ctlplane
   sudo ip addr add 192.0.2.1/24 dev br-ctlplane

you need to replace the private network definition
   export OS_USERNAME=admin
   quantum net-list
then
   quantum net-show <uuid>
of the existing 192.0.2.33 network and get the tenant id, then delete and recreate it
   quantum net-delete <uuid>
   quantum net-create ctlplane --tenant-id <uuid> --provider:network_type flat --provider:physical_network ctlplane
   quantum subnet-create  --ip-version 4 --allocation-pool start=192.0.2.34,end=192.0.2.38 --gateway=192.0.2.33 <new-uuid> 192.0.2.32/29
   sudo ifconfig br-ctlplane up

then kill and restart q-svc and q-agt and q-dhcp, bm-helper's dnsmasq:
 - in screen -x stack ctrl-c and restart them
 - for bm-helper, run this by hand after killing the old dnsmasq
dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --dhcp-range=192.0.2.65,192.0.2.69,29 --interface=br-ctlplane


