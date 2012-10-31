#!/bin/bash

set -e

# script to create a Ubuntu bare metal image
# NobodyCam 0.0.0 Pre-alpha
# Others 0.1.0 Beta
#
# This builds an image in /tmp, and moves it into $IMG_PATH upon success.

# load defaults and functions
source $(dirname $0)/img-defaults
# defaults shouldn't be needed now as create-baremetal-image has strictly no
# dependencies on the running/runnable environment, but for migration purposes
# keep it for a
# few days.
source $(dirname $0)/defaults
source $(dirname $0)/common-functions
source $(dirname $0)/img-functions
set -o xtrace

# Ensure we have sudo before we do long running things that will bore the user.
# Also, great band.
sudo echo

BASE_DIR=$(dirname $0)

mk_build_dir
ensure_base_available

# Create the file that will be our image
dd if=/dev/zero of=$TMP_IMAGE_PATH bs=1M count=0 seek=$(( ${IMAGE_SIZE} * 1024 ))

mkfs -F -t $FS_TYPE $TMP_IMAGE_PATH

mount_tmp_image $TMP_IMAGE_PATH

create_base

# Run pre-install scripts. These do things that prepare the chroot for package installs
run_d_in_target pre-install

# Call install scripts to pull in the software we need
run_d_in_target install

# Now some quick hacks to prevent 4 minutes of pause while booting
if [ -f $TMP_BUILD_DIR/mnt/etc/init/cloud-init-nonet.conf ] ; then
    sudo rm -f $TMP_BUILD_DIR/mnt/etc/init/cloud-init-nonet.conf

# Now Recreate the file we just removed
sudo dd of=$TMP_BUILD_DIR/mnt/etc/init/cloud-init-nonet.conf << _EOF_ 
# cloud-init-no-net
start on mounted MOUNTPOINT=/ and stopped cloud-init-local
stop on static-network-up
task

console output

script
   # /run/network/static-network-up-emitted is written by
   # upstart (via /etc/network/if-up.d/upstart). its presense would
   # indicate that static-network-up has already fired.
	EMITTED="/run/network/static-network-up-emitted"
   [ -e "$EMITTED" -o -e "/var/$EMITTED" ] && exit 0

   [ -f /var/lib/cloud/instance/obj.pkl ] && exit 0

   start networking >/dev/null

   short=1; long=5;
   sleep ${short}
   echo $UPSTART_JOB "waiting ${long} seconds for a network device."
   sleep ${long}
   echo $UPSTART_JOB "gave up waiting for a network device."
   : > /var/lib/cloud/data/no-net
end script
# EOF
_EOF_
fi

# One more hack
if [ -f $TMP_BUILD_DIR/mnt/etc/init/failsafe.conf ] ; then
    sudo rm -f $TMP_BUILD_DIR/mnt/etc/init/failsafe.conf
fi

# Now Recreate the file we just removed
sudo dd of=$TMP_BUILD_DIR/mnt/etc/init/failsafe.conf << _EOF_ 
# failsafe

description "Failsafe Boot Delay"
author "Clint Byrum <clint@ubuntu.com>"

start on filesystem and net-device-up IFACE=lo
stop on static-network-up or starting rc-sysinit

emits failsafe-boot

console output

script
	# Determine if plymouth is available
	if [ -x /bin/plymouth ] && /bin/plymouth --ping ; then
		PLYMOUTH=/bin/plymouth
	else
		PLYMOUTH=":"
	fi

    # The point here is to wait for 2 minutes before forcibly booting 
    # the system. Anything that is in an "or" condition with 'started 
    # failsafe' in rc-sysinit deserves consideration for mentioning in
    # these messages. currently only static-network-up counts for that.

	sleep 2

    # Plymouth errors should not stop the script because we *must* reach
    # the end of this script to avoid letting the system spin forever
    # waiting on it to start.
	$PLYMOUTH message --text="Waiting for network configuration..." || :
	sleep 1

	$PLYMOUTH message --text="Waiting up to 5 more seconds for network configuration..." || :
	sleep 1
	$PLYMOUTH message --text="Booting system without full network configuration..." || :

    # give user 1 second to see this message since plymouth will go
    # away as soon as failsafe starts.
	sleep 1
    exec initctl emit --no-wait failsafe-boot
end script

post-start exec	logger -t 'failsafe' -p daemon.warning "Failsafe of 120 seconds reached."
_EOF_

# that should do it for the hacks
finalise_base

# name the file by the kernel it contained, if no name specified
BM_RUN_KERNEL=$(basename `ls -1 $TMP_BUILD_DIR/mnt/boot/vmlinuz*generic | sort -n | tail -1`)
IMAGE_KERNEL_VER=${BM_RUN_KERNEL##vmlinuz-}
BM_IMAGE=${BM_IMAGE:-bm-node-image.$IMAGE_KERNEL_VER.img}

# clean up
# --------
unmount_image

save_image $IMG_PATH/$BM_IMAGE
