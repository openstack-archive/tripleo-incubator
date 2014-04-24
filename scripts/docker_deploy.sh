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

[[ -d $HOME/.cache/openstack ]] && mkdir -p "$HOME/.cache/openstack"
[[ -d $HOME/.cache/tripleo-docker ]] && mkdir -p "$HOME/.cache/tripleo-docker/yum"


# If we are not running inside of Docker, put ourselves in a container.
if [[ ! -x /.dockerinit ]]; then
    # Start with opensuse-13.1 as our container base, as services work in it
    # and it doesn't have an annoyingly out of date libvirt/qemu combo.
    image="mmckeen/opensuse-13-1"
    if ! which docker &>/dev/null; then
        echo "Please install Docker!"
        exit 1
    fi

    [[ -d /sys/module/openvswitch ]] || \
        modprobe ovenvswitch || {
        echo "Could not install the openvswitch module!"
        exit 1
    }

    if [[ $0 = /* ]]; then
        mountdir="$0"
    elif [[ $0 = .*  || $0 = */* ]]; then
        mountdir="$(readlink -f "$PWD/$0")"
    else
        echo "Cannot figure out where we are!"
        exit 1
    fi
    # This gets us to tripleo-incubator
    mountdir="${mountdir%/scripts/docker_deploy.sh}"
    # This gets us to the parent directory of tripleo-incubator,
    # where presumably the rest of our repos are checked out
    mountdir="${mountdir%/*}"

    docker_args=(-t -i -v "$mountdir:$mountdir")
    docker_args+=(-v "$HOME/.cache/openstack:/home/$(id -un)/.cache")
    docker_args+=(-v "$HOME/.cache/tripleo-docker/yum:/var/cache/yum")
    if [[ -f $HOME/.devtestrc ]]; then
        docker_args+=(-v "$HOME/.devtestrc:/home/$(id -un)/.devtestrc")
    fi
    docker_args+=(-e "OUTER_UID=$(id -u)")
    docker_args+=(-e "OUTER_GID=$(id -g)")
    docker_args+=(-e "OUTER_USER=$(id -un)")
    docker_args+=(-e "OUTER_GROUP=$(id -gn)")
    docker_args+=(-e "TRIPLEO_ROOT=$mountdir")
    [[ -f $HOME/.ssh/id_rsa.pub ]] && docker_args+=(-e "SSH_PUBKEY=$(cat "$HOME/.ssh/id_rsa.pub")")
    bridge="docker0"
    bridge_re='-b=([^ ])'
    bridge_addr_re='inet ([0-9.]+)/'
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
    docker run "${docker_args[@]}" "$image" "$mountdir/tripleo-incubator/scripts/docker_deploy.sh" "$@"
    exit $?
fi
case $1 in
    fedora|opensuse|ubuntu) export TRIPLEO_OS_DISTRO="$1";;
    *) echo "Don't know how to create an undercloud on $1"
        exit 1;;
esac
shift
export LANG=en_US.UTF-8
export LIBVIRT_DEFAULT_URI="qemu:///system"
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
chown -R "$OUTER_USER:$OUTER_GROUP" "/home/$OUTER_USER"
mkdir -p /root/.ssh
printf "%s\n" "$SSH_PUBKEY" >> /root/.ssh/authorized_keys

# Make sure our mirror choices get respected by opensuse.
if [[ -f /etc/sysconfig/proxy && $http_proxy ]]; then
    echo 'PROXY_ENABLED=yes'>/etc/sysconfig/proxy
    [[ $HTTP_PROXY ]] && echo "HTTP_PROXY='$HTTP_PROXY'" >>/etc/sysconfig/proxy
    [[ $HTTPS_PROXY ]] && echo "HTTPS_PROXY='$HTTPS_PROXY'" >> /etc/sysconfig/proxy
    [[ $NO_PROXY ]] && echo "NO_PROXY='$NO_PROXY'" >> /etc/sysconfig/proxy
fi

. /etc/profile
# Disable using mirrors if we know we have a local squid.
[[ $LOCAL_SQUID = true ]] && \
    (cd /etc/zypp/repos.d
     echo "Mangling repositories for local squid."
     sed -i -e '/^#baseurl/ s/\#//' -e '/^mirrorlist/ s/^mirror/#mirror/' *.repo)

zypper -n refresh
zypper -n install --no-recommends sudo tmux openssh
ssh-keygen -q -b 1024 -P '' -f /etc/ssh/ssh_host_rsa_key
"$(which sshd)"
sed -i -e '/^Defaults.*(requiretty|visiblepw)/ s/^.*$//' /etc/sudoers
keep_envs=(
    HTTPS_PROXY
    HTTP_PROXY
    LIBVIRT_NIC_DRIVER
    LIBVIRT_DEFAULT_URI
    LOCAL_SQUID
    MANGLED_PROXIES
    NO_PROXY
    PATH
    TRIPLEO_OS_DISTRO
    TRIPLEO_ROOT
    http_proxy
    https_proxy
    no_proxy
)
printf 'Defaults   env_keep += "%s"\n' "${keep_envs[*]}" >/etc/sudoers.d/wheel
echo '%wheel	ALL=(ALL)	NOPASSWD: ALL' >>/etc/sudoers.d/wheel

tmux new-session -s control -n rootshell -d '/bin/bash -i'
tmux set-option set-remain-on-exit on
tmux new-window -n control:usershell -d 'sudo -E -H -u $OUTER_USER -i'
tmux new-window -n control:devtest \
    "sudo -E -H -u $OUTER_USER -- '$TRIPLEO_ROOT/tripleo-incubator/scripts/devtest.sh' --trash-my-machine $@"
tmux attach
