Each directory here is a flavour of image. We have two flavours today, demo and
bootstrap.

To make a new flavour, just make a directory with the name you want, and create
hook directories below it. e.g
mkdir -p $MYFLAVOUR/{pre-install.d,install.d}

The bootstrap flavour is used when creating a single-image VM for provisioning
a new bare-metal cloud.

The demo flavour is used for the images we create to run in demo mode - on VM's
or various test gear our developers have.
