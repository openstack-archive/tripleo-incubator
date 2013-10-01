write-tripleorc

## #. If you need to recover the environment, you can source tripleorc.
## 

echo "devtest.sh completed." #nodocs
echo source tripleorc to restore all values #nodocs
echo "" #nodocs

## The End!
## 
## 
## .. rubric:: Footnotes
## 
## .. [#f1] Customize a downloaded seed image.
## 
##    If you downloaded your seed VM image, you may need to configure it.
##    Setup a network proxy, if you have one (e.g. 192.168.2.1 port 8080)
##    ::
## 
##         # Run within the image!
##         echo << EOF >> ~/.profile
##         export no_proxy=192.0.2.1
##         export http_proxy=http://192.168.2.1:8080/
##         EOF
## 
##    Add an ~/.ssh/authorized_keys file. The image rejects password authentication
##    for security, so you will need to ssh out from the VM console. Even if you
##    don't copy your authorized_keys in, you will still need to ensure that
##    /home/stack/.ssh/authorized_keys on your seed node has some kind of
##    public SSH key in it, or the openstack configuration scripts will error.
## 
##    You can log into the console using the username 'stack' password 'stack'.
## 
## .. [#f2] Requirements for the "baremetal node" VMs
## 
##    If you don't use create-nodes, but want to create your own VMs, here are some
##    suggestions for what they should look like.
## 
##    * each VM should have 1 NIC
##    * eth0 should be on brbm
##    * record the MAC addresses for the NIC of each VM.
##    * give each VM no less than 2GB of disk, and ideally give them
##      more than NODE_DISK, which defaults to 20GB
##    * 1GB RAM is probably enough (512MB is not enough to run an all-in-one
##      OpenStack), and 768M isn't enough to do repeated deploys with.
##    * if using KVM, specify that you will install the virtual machine via PXE.
##      This will avoid KVM prompting for a disk image or installation media.
## 
## .. [#f3] Setting Up Squid Proxy
## 
##    * Install squid proxy
##      ::
##          apt-get install squid
## 
##    * Set `/etc/squid3/squid.conf` to the following
##      ::
## 
##          acl manager proto cache_object
##          acl localhost src 127.0.0.1/32 ::1
##          acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
##          acl localnet src 10.0.0.0/8 # RFC1918 possible internal network
##          acl localnet src 172.16.0.0/12  # RFC1918 possible internal network
##          acl localnet src 192.168.0.0/16 # RFC1918 possible internal network
##          acl SSL_ports port 443
##          acl Safe_ports port 80      # http
##          acl Safe_ports port 21      # ftp
##          acl Safe_ports port 443     # https
##          acl Safe_ports port 70      # gopher
##          acl Safe_ports port 210     # wais
##          acl Safe_ports port 1025-65535  # unregistered ports
##          acl Safe_ports port 280     # http-mgmt
##          acl Safe_ports port 488     # gss-http
##          acl Safe_ports port 591     # filemaker
##          acl Safe_ports port 777     # multiling http
##          acl CONNECT method CONNECT
##          http_access allow manager localhost
##          http_access deny manager
##          http_access deny !Safe_ports
##          http_access deny CONNECT !SSL_ports
##          http_access allow localnet
##          http_access allow localhost
##          http_access deny all
##          http_port 3128
##          cache_dir aufs /var/spool/squid3 5000 24 256
##          maximum_object_size 1024 MB
##          coredump_dir /var/spool/squid3
##          refresh_pattern ^ftp:       1440    20% 10080
##          refresh_pattern ^gopher:    1440    0%  1440
##          refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
##          refresh_pattern (Release|Packages(.gz)*)$      0       20%     2880
##          refresh_pattern .       0   20% 4320
##          refresh_all_ims on
## 
##    * Restart squid
##      ::
##          sudo service squid3 restart
## 
##    * Set http_proxy environment variable
##      ::
##          http_proxy=http://your_ip_or_localhost:3128/
##
## .. [#f4] Notes when using real bare metal
##
##    If you want to use real bare metal see the following.
##
##    * When calling setup-baremetal you can set MACS, PM_IPS, PM_USERS,
##      and PM_PASSWORDS parameters which should all be space delemited lists
##      that correspond to the MAC addresses and power management commands
##      your real baremetal machines require. See scripts/setup-baremetal
##      for details.
##
##    * If you see over-mtu packets getting dropped when iscsi data is copied
##      over the control plane you may need to increase the MTU on your brbm
##      interfaces. Symptoms that this might be the cause include:
##
##        iscsid: log shows repeated connection failed errors (and reconnects)
##        dmesg shows:
##            openvswitch: vnet1: dropped over-mtu packet: 1502 > 1500
## 
### --end
