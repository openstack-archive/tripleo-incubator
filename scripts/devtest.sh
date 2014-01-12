#!/bin/bash
#
# Demo script for Tripleo - the dev/test story.
# This can be run for CI purposes, by passing --trash-my-machine to it.
# Without that parameter, the script is a no-op.
set -eu
set -o pipefail
SCRIPT_NAME=$(basename $0)
SCRIPT_HOME=$(dirname $0)

function show_options () {
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Test the core TripleO story."
    echo
    echo "Options:"
    echo "    --trash-my-machine -- make nontrivial destructive changes to the machine."
    echo "                          For details read the source."
    echo "    -c                 -- re-use existing source/images if they exist."
    echo
    echo "Note that this script just chains devtest_setup, devtest_seed, devtest_ramdisk"
    echo "devtest_undercloud, devtest_overcloud, devtest_end. If you want to run less"
    echo "than all of them just source each step in order after sourcing ~/.devtestrc."
    echo
    exit $1
}

CONTINUE=
USE_CACHE=0

TEMP=`getopt -o h,c -l trash-my-machine -n $SCRIPT_NAME -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        --trash-my-machine) CONTINUE=--trash-my-machine; shift 1;;
        -c) USE_CACHE=1; shift 1;;
        -h) show_options 0;;
        --) shift ; break ;;
        *) echo "Error: unsupported option $1." ; exit 1 ;;
    esac
done

if [ -z "$CONTINUE" ]; then
    echo "Not running - this script is destructive and requires --trash-my-machine to run." >&2
    exit 1
fi

export USE_CACHE

# Source environment variables from .devtestrc, allowing defaults to be setup
# specific to users environments
if [ -e ~/.devtestrc ] ; then
    echo "sourcing ~/.devtestrc"
    source ~/.devtestrc
fi

### --include
## devtest
## =======

## (There are detailed instructions available below, the overview and
## configuration sections provide background information).

## Overview:
## * Define a VM that is your seed node
## * Define N VMs to pretend to be your cluster
## * Create a seed VM
## * Create an undercloud
## * Create an overcloud
## * Deploy a sample workload in the overcloud
## * Add environment variables to be included to ~/.devtestrc, e.g. http_proxy
## * Go to town testing deployments on them.
## * For troubleshooting see :doc:`troubleshooting`
## * For generic deployment information see :doc:`deploying`

## This document is extracted from devtest.sh, our automated bring-up story for
## CI/experimentation.

## Next Steps:
## -----------
## 
## #. :doc:`devtest_variables`
## 
## #. :doc:`devtest_setup`
## 
## #. :doc:`devtest_testenv`
## 
## #. :doc:`devtest_ramdisk`
## 
## #. :doc:`devtest_seed`
## 
## #. :doc:`devtest_undercloud`
## 
## #. :doc:`devtest_overcloud`
## 
## #. :doc:`devtest_end`

### --end

#FIXME: This is a little weird. Perhaps we should identify whatever state we're
#      accumulating and store it in files or something, rather than using
#      source?
source devtest_setup.sh $CONTINUE
source devtest_variables.sh
source devtest_testenv.sh $TE_DATAFILE
devtest_ramdisk.sh
source devtest_seed.sh
source devtest_undercloud.sh
source devtest_overcloud.sh
source devtest_end.sh

### --include

## .. rubric:: Footnotes
## .. [#f3] Setting Up Squid Proxy
## 
##    * Install squid proxy
##      ::
##          apt-get install squid
## 
##    * Set `/etc/squid3/squid.conf` to the following
##      ::
## 
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
## 
### --end
