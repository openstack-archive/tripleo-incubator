#/bin/bash

# script to create a Ubuntu bare metal image
# NobodyCam 0.0.0 Pre-alpha
set -o xtrace
# Setup
CURRENT_PATH=${CURRENT_PATH:-`pwd`}
BASE_IMAGE_FILE=${BASE_IMAGE_FILE:-precise-server-cloudimg-amd64-root.tar.gz}
OUTPUT_IMAGE_FILE=${OUTPUT_IMAGE_FILE:-ubuntu_bm_image.img}
KERNEL_VER=${KERNEL_VER:-3.2.0-29-generic}


[ ! -f  $CURRENT_PATH/$BASE_IMAGE_FILE ] && \
   echo "Fetching Base Image" && \
   wget http://cloud-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-root.tar.gz

# TODO: this really should rename the old file
[ -f  $CURRENT_PATH/$OUTPUT_IMAGE_FILE ] && \
   echo "Old Image file Found REMOVING" && \
   rm -f $CURRENT_PATH/$OUTPUT_IMAGE_FILE

# Create the file that will be our image
# TODO: allow control of image size too
dd if=/dev/zero of=$CURRENT_PATH/$OUTPUT_IMAGE_FILE bs=1M count=0 seek=1024

# Format the image
# TODO: allow control of fs type
mkfs -F -t ext4 $CURRENT_PATH/$OUTPUT_IMAGE_FILE

TMP_BUILD_DIR=`mktemp -t -d image.XXXXXXXX`
[ $? -ne 0 ] && \
    echo "Failed to create tmp directory" && \
    exit 1

# mount the image file
sudo mount -o loop $CURRENT_PATH/$OUTPUT_IMAGE_FILE $TMP_BUILD_DIR
[ $? -ne 0 ] && \
    echo "Failed to mount image" && \
    exit 1

# Extract the base image
sudo tar -C $TMP_BUILD_DIR -xzf $CURRENT_PATH/$BASE_IMAGE_FILE

# Configure Image
# Setup resolv.conf so we can chroot to install some packages
[ -L $TMP_BUILD_DIR/etc/resolv.conf ] && \
    sudo unlink $TMP_BUILD_DIR/etc/resolv.conf

[ -f $TMP_BUILD_DIR/etc/resolv.conf ] && \
    sudo rm -f $TMP_BUILD_DIR/etc/resolv.conf

# Recreate resolv.conf
sudo echo nameserver 8.8.8.8 > $TMP_BUILD_DIR/etc/resolv.conf

# now chroot and install what we need (it is ok to Ignore errors here)
sudo chroot $TMP_BUILD_DIR apt-get -y install linux-image-$KERNEL_VER vlan open-iscsi

# Now some quick hacks to prevent 4 minutes of pause while booting
[ -f $TMP_BUILD_DIR/etc/init/cloud-init-nonet.conf ] && \
    sudo rm -f $TMP_BUILD_DIR/etc/init/cloud-init-nonet.conf && \

# Now Recreate the file we just removed
cat << _EOF_ > $TMP_BUILD_DIR/etc/init/cloud-init-nonet.conf
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

# One more hack
[ -f $TMP_BUILD_DIR/etc/init/failsafe.conf ] && \
    sudo rm -f $TMP_BUILD_DIR/etc/init/failsafe.conf

# Now Recreate the file we just removed
cat << _EOF_ > $TMP_BUILD_DIR/etc/init/failsafe.conf
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
# Now remove the resolv.conf we created above
sudo rm -f $TMP_BUILD_DIR/etc/resolv.conf
# The we need to recreate it as a link
ln -sf ../run/resolvconf/resolv.conf $TMP_BUILD_DIR/etc/resolv.conf

# oh ya don't want to forget to unmount the image
sudo umount $TMP_BUILD_DIR

echo "Image file $CURRENT_PATH/$OUTPUT_IMAGE_FILE created..."

