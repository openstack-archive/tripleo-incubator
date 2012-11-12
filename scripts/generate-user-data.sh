#!/bin/bash

# build a cloud-init user-data script from a template,
# based upon the settings in localrc.

set -e
set -o xtrace

source $(dirname $0)/../localrc
set -u

output=$(dirname $0)/user-data.sh

cat > $output <<-EOF
#!/bin/bash

# this is a generated user-data script to be supplied at first boot of a bm instance:
#   nova boot --user-data=scripts/user-data.sh --image=...

# If something goes wrong bail, don't continue to the end
set -e
set -o xtrace

# salt config
sed -i "s/^#master: salt$/master: $SALT_MASTER/g" /etc/salt/minion
service salt-minion restart
EOF

