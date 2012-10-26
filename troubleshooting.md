Troubleshooting tips
====================

Baremetal
---------

If you get a no hosts found error in the schedule/nova logs, check:

    mysql nova -e 'select * from compute_nodes;'

After adding a bare metal node, the bare metal backend writes an entry to the
compute nodes table, but it takes about 5 seconds to go from A to B.


