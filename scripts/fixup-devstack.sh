#!/bin/bash

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# load defaults and functions
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/functions

# fix mysql issues - adds user_quotas table - not sure what uses it.
# TODO: remove after NTT patch lands upstream
# TODO: skip this block if it's already done
sql=<<EOL
GRANT ALL PRIVILEGES ON nova_bm.* TO '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';
EOL

## XXX: In theory this is not needed anymore. It may 
MYSQL=$(which mysql)
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -e "$sql"
$MYSQL -u$MYSQL_USER -p$MYSQL_PASSWORD -v -v -f nova_bm < $(dirname $0)/init_nova_bm_db.sql

# The baremetal migrations fail if the nova quota table doesn't already exist.
$BM_SCRIPT_PATH/$BM_SCRIPT db sync

# restart dnsmasq
sudo pkill dnsmasq || true
sudo mkdir -p /tftpboot/pxelinux.cfg
sudo cp /usr/lib/syslinux/pxelinux.0 /tftpboot/
sudo chown -R stack:libvirtd /tftpboot
sudo dnsmasq --conf-file= --port=0 --enable-tftp --tftp-root=/tftpboot --dhcp-boot=pxelinux.0 --bind-interfaces --pid-file=/var/run/dnsmasq.pid --interface=$DNSMASQ_IFACE --dhcp-range=$DNSMASQ_RANGE

# make sure deploy server is running
[ $(pgrep -f "$BM_HELPER") ] || $BM_SCRIPT_PATH/$BM_HELPER &
