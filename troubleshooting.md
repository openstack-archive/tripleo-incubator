Troubleshooting tips
====================

Baremetal
---------

If you get a no hosts found error in the schedule/nova logs, check:

    mysql nova -e 'select * from compute_nodes;'

After adding a bare metal node, the bare metal backend writes an entry to the
compute nodes table, but it takes about 5 seconds to go from A to B.


Be sure that the hostname in nova_bm.bm_nodes (service_host) is the same than
the one used by nova. If no value has been specified using the flag "host=" in 
nova.conf, the default one is:
    python -c "import socket; print socket.getfqdn()"

You can override this value when populating the bm database using the -h flag:
    scripts/populate-nova-bm-db.sh -i "xx:xx:xx:xx:xx:xx" -j "yy:yy:yy:yy:yy:yy" -h "nova_hostname" add
        