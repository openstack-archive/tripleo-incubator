#!/bin/bash
# Copyright 2014, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Run tripleo undercloud seed in a Docker container using devtest.sh
# $1 = OS to deploy to the undercloud
# $@ = Args to pass to devtest.sh.  --trash-my-machine will be included.

mkdir -p "$HOME/.cache/openstack"
mkdir -p "$HOME/.cache/tripleo-docker/yum"
mkdir -p "$HOME/.cache/tripleo-docker/run"

# If we are not running inside of Docker, put ourselves in a container.
if [[ ! -x /.dockerinit ]]; then
    # set -eu and set -o pipefail are not compatible with sourcing /etc/profile.
    # So we only run those checks outside the docker container, not inside it
    # when this script is effectively /sbin/init.
    set -eu
    set -o pipefail
    # Start with opensuse-13.2 as our container base, as services work in it
    # (with some systemd hacking) and it doesn't have an annoyingly out of 
    # date libvirt/qemu combo.
    image="library/opensuse:13.2"
    if ! which docker &>/dev/null; then
        echo "Please install Docker!"
        exit 1
    fi

    if [[ ! -d /sys/module/openvswitch ]] && ! sudo modprobe openvswitch; then
        echo "Could not install the openvswitch module!"
        exit 1
    fi

    mountdir="$(readlink -f "$0")"
    # This gets us to tripleo-incubator
    mountdir="${mountdir%/scripts/docker_deploy.sh}"
    # This gets us to the parent directory of tripleo-incubator,
    # where presumably the rest of our repos are checked out
    mountdir="${mountdir%/*}"

    declare -a docker_args=(-t -i -v "$mountdir:$mountdir")
    docker_args+=(-v "$HOME/.cache/openstack:/home/$(id -un)/.cache")
    # To let systemd in the container do its thing.
    docker_args+=(-v "/sys/fs/cgroup:/sys/fs/cgroup:ro")
    docker_args+=(-v "$HOME/.cache/tripleo-docker/yum:/var/cache/yum")
    if [[ -f $HOME/.devtestrc ]]; then
        docker_args+=(-v "$HOME/.devtestrc:/home/$(id -un)/.devtestrc")
    fi
    docker_args+=(-e "OUTER_UID=$(id -u)")
    docker_args+=(-e "OUTER_GID=$(id -g)")
    docker_args+=(-e "OUTER_USER=$(id -un)")
    docker_args+=(-e "OUTER_GROUP=$(id -gn)")
    docker_args+=(-e "TRIPLEO_ROOT=$mountdir")
    # Lie here, as systemd 210 does not know about docker.
    docker_args+=(-e "container=lxc")
    [[ -f $HOME/.ssh/id_rsa.pub ]] && docker_args+=(-e "SSH_PUBKEY=$(cat "$HOME/.ssh/id_rsa.pub")")
    bridge="docker0"
    readonly bridge_re='-b=([^ ])'
    readonly bridge_addr_re='inet ([0-9.]+)/'
    # If we told Docker to use a custom bridge, here is where it is at.
    [[ $(ps -C docker -o 'command=') =~ $bridge_re ]] && \
        bridge="${BASH_REMATCH[1]}"
    # Capture the IP of the bridge for later when we are hacking up
    # proxies.
    [[ $(ip -o -4 addr show dev $bridge) =~ $bridge_addr_re ]] && \
        bridge_ip="${BASH_REMATCH[1]}"
    # Make sure the container knows about our proxies, if applicable.
    . "$mountdir/tripleo-incubator/scripts/proxy_lib.sh"
    mangle_proxies "$bridge_ip"
    docker_args+=(-e "MANGLED_PROXIES=$MANGLED_PROXIES" -e "LOCAL_SQUID=$LOCAL_SQUID")
    for proxy in "${!mangled_proxies[@]}"; do
        # pip install randomly fails through the proxy.
        [[ $proxy = https_proxy ]] && continue
        docker_args+=(-e "$proxy=${mangled_proxies[$proxy]}")
        docker_args+=(-e "${proxy^^*}=${mangled_proxies[$proxy]}")
    done

    # since 0.8.1 we need to run in privileged mode so we can change the networking
    docker_args+=("--privileged")
    # Run whatever we specified to run inside a container.
    # We expect to eventually be able to SSH into it to kick things off.
    container=$(docker run -d "${docker_args[@]}" "$image" "$mountdir/tripleo-incubator/scripts/docker_deploy.sh" "$@")
    container_addr=$(gawk 'match($0,/"IPAddress": "([^"]+)"/,ary) { print ary[1] }' < <(docker inspect $container)) 
    echo Container at $container_addr.  Waiting on access (about 15 seconds).
    while ! ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no $container_addr true &>/dev/null; do
	printf '.'
	sleep 1
    done
    echo
    ssh -oUserKnownHostsFile=/dev/null \
	-oStrictHostKeyChecking=no -t \
	$container_addr \
	/usr/bin/run_devtest.sh
    echo "Container still running! To kill it, run:"
    echo "docker kill $container"
    exit
fi
case ${1-''} in
    fedora|opensuse|ubuntu) export NODE_DIST="$1";;
    *) echo "Don't know how to create an undercloud on $1"
        exit 1;;
esac
shift
if [[ ${1-''} = --no-devtest ]]; then
    SKIP_DEVTEST=true
    shift
fi
# We are in the container now.  Set up the env we want.
export LANG=en_US.UTF-8

# Make sure the UID/GID of the user we run things as is the same inside the
# container as outside.  This lets docker volumes actually work instead of
# being a nuisance.
if grep -q "$OUTER_USER" /etc/passwd; then
    find /var /home -xdev -user "$OUTER_USER" -exec chown "$OUTER_UID" '{}' ';'
    usermod -o -u "$OUTER_UID" "$OUTER_USER"
else
    useradd -o -U -u "$OUTER_UID" \
        -d "/home/$OUTER_USER" -m \
        -s /bin/bash \
        "$OUTER_USER"
fi
if grep -q "$OUTER_GROUP" /etc/group; then
    find /var /home -xdev -group "$OUTER_GROUP" -exec chown "$OUTER_UID:$OUTER_GID" '{}' ';'
    groupmod -o -g "$OUTER_GID" "$OUTER_GROUP"
    usermod -g "$OUTER_GID" "$OUTER_GROUP"
    usermod -a -G wheel "$OUTER_GROUP"
    usermod -a -G wheel root
fi

# Arrange to be able to SSH in as ourselves.
mkdir -p "/home/$OUTER_USER/.ssh"
printf "%s\n" "$SSH_PUBKEY" >> "/home/$OUTER_USER/.ssh/authorized_keys"
chown -R "$OUTER_USER:$OUTER_GROUP" "/home/$OUTER_USER"

# Make sure our mirror choices get respected by opensuse.
if [[ -f /etc/sysconfig/proxy && ${http_proxy-''} ]]; then
    echo 'PROXY_ENABLED=yes'>/etc/sysconfig/proxy
    [[ ${HTTP_PROXY-''} ]] && echo "HTTP_PROXY='$HTTP_PROXY'" >>/etc/sysconfig/proxy
    [[ ${HTTPS_PROXY-''} ]] && echo "HTTPS_PROXY='$HTTPS_PROXY'" >> /etc/sysconfig/proxy
    [[ ${NO_PROXY-''} ]] && echo "NO_PROXY='$NO_PROXY'" >> /etc/sysconfig/proxy
fi

. /etc/profile
# Disable using mirrors if we know we have a local squid.
[[ $LOCAL_SQUID = true ]] && \
    (cd /etc/zypp/repos.d
     echo "Mangling repositories for local squid."
     sed -i -e '/^#baseurl/ s/\#//' -e '/^mirrorlist/ s/^mirror/#mirror/' *.repo)

# Pull in the bare minimum we need to get the party started.
zypper -n --gpg-auto-import-keys refresh
zypper -n install --no-recommends sudo tmux openssh iproute2
ssh-keygen -q -b 1024 -P '' -f /etc/ssh/ssh_host_rsa_key
sed -i -e '/^Defaults.*(requiretty|visiblepw)/ s/^.*$//' /etc/sudoers
declare -a keep_envs=(
    HTTPS_PROXY
    HTTP_PROXY
    LIBVIRT_NIC_DRIVER
    LIBVIRT_DEFAULT_URI
    LIBVIRT_DISK_BUS_TYPE
    LOCAL_SQUID
    MANGLED_PROXIES
    NO_PROXY
    NODE_DIST
    SKIP_DEVTEST
    TRIPLEO_ROOT
    http_proxy
    https_proxy
    no_proxy
)
printf 'Defaults   env_keep += "%s"\n' "${keep_envs[*]}" >/etc/sudoers.d/wheel
echo '%wheel	ALL=(ALL)	NOPASSWD: ALL' >>/etc/sudoers.d/wheel

# Prepare login environment
for var in "${keep_envs[@]}"; do
    echo "export $var='${!var}'" >>/etc/profile.d/tripleoenv.sh
done

# Arrange for tmux to do The Right Thing once we can ssh into the node.
cat >/usr/bin/run_devtest.sh <<EOF
#!/bin/bash
. /etc/profile
tmux new-session -s control -n rootshell -d 'sudo -i'
tmux set-option set-remain-on-exit on
tmux new-window -n control:usershell -d '/bin/bash -i'
[[ \$SKIP_DEVTEST ]] || tmux new-window -n control:devtest \
    "'$TRIPLEO_ROOT/tripleo-incubator/scripts/devtest.sh' --trash-my-machine $@"
tmux a
EOF
chmod 755 /usr/bin/run_devtest.sh

# Arrange for systemd to run properly inside the container.
ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -s -t /etc/systemd/system/multi-user.target.wants /usr/lib/systemd/system/sshd.service
sed 's/^OOM/#OOM/' < /usr/lib/systemd/system/dbus.service > /etc/systemd/system/dbus.service
for unit in dev-mqueue.mount dev-hugepages.mount systemd-remount-fs.service \
    sys-kernel-config.mount sys-kernel-debug.mount sys-fs-fuse-connections.mount \
    console-getty.service getty@.service display-manager.service systemd-login.service; do
    ln -sf /dev/null "/etc/systemd/system/$unit"
done
# Clear out the last journal logs
(cd /run; rm -rf * || :)
exec /usr/lib/systemd/systemd
