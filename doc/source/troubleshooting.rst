Troubleshooting tips
====================

VM won't boot
-------------

Make sure the partition table is correct. See
https://bugs.launchpad.net/nova/+bug/1088652.

Baremetal
---------

If you get a no hosts found error in the schedule/nova logs, check:

::

    mysql nova -e 'select * from compute_nodes;'

After adding a bare metal node, the bare metal backend writes an entry
to the compute nodes table, but it takes about 5 seconds to go from A to
B.

Be sure that the hostname in nova\_bm.bm\_nodes (service\_host) is the
same than the one used by nova. If no value has been specified using the
flag "host=" in nova.conf, the default one is:

::

    python -c "import socket; print socket.getfqdn()"

You can override this value when populating the bm database using the -h
flag:

::

    scripts/populate-nova-bm-db.sh -i "xx:xx:xx:xx:xx:xx" -j "yy:yy:yy:yy:yy:yy" -h "nova_hostname" add


DHCP Server Work Arounds
------------------------

If you don't control the DHCP server on your flat network you will need
to at least have someone put the MAC address of the server your trying
to provision in there DHCP server.

::

    host bm-compute001 {
        hardware ethernet 78:e7:d1:XX:XX:XX ;
        next-server 10.0.1.2 ;
        filename "pxelinux.0";
    }

Write down the MAC address for the IPMI management interface and the NIC
your booting from. You will also need to know the IP address of both.
Most DHCP server won't expire the IP leased to quickly so if your lucky
you will get the same IP each time you reboot. With that information
bare-metal can generate the correct pxelinux.cfg/. (???? Commands to
tell nova?)

In the provisional environment I have there was another problem. The
DHCP Server was already modified to point to a next-server. A quick work
around was to redirect the connections using iptables.

::

    modprobe nf_nat_tftp

    baremetal_installer="<ip address>/<mask>"
    iptables -t nat -A PREROUTING -i eth2  -p udp --dport 69 -j DNAT --to ${baremetal_installer}:69
    iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 10000 -j DNAT --to ${baremetal_installer}:10000
    iptables -A FORWARD -p udp -i eth2 -o eth2 -d  ${baremetal_installer} --dport 69 -j ACCEPT
    iptables -A FORWARD -p tcp -i eth2 -o eth2 -d ${baremetal_installer} --dport 10000 -j ACCEPT
    iptables -t nat -A POSTROUTING -j MASQUERADE

Notice the additional rules for port 10000. It is for the bare-metal
interface (???) You should have matching reverse DNS too. We experienced
problems connecting to port 10000 (????). That may be very unique to my
environment btw.

Image Build Race Condition
--------------------------

Multiple times we experienced a failure to build a good bootable image.
This is because of a race condition hidden in the code currently. Just
remove the failed image and try to build it again.

Once you have a working image check the Nova DB to make sure the it is
not flagged as removed (???)

Virtual Machines
----------------

VM's booting terribly slowly in KVM?
------------------------------------

Check the console, if the slowdown happens right after probing for
consoles - wait 2m or so and you should see a serial console as the next
line output after the vga console. If so you're likely running into
https://bugzilla.redhat.com/show\_bug.cgi?id=750773. Remove the serial
device from your machine definition in libvirt, and it should fix it.
