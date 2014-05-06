export TRIPLEO_ROOT=$HOME/w
export http_proxy=http://16.27.53.8:3128/
export https_proxy=http://16.27.53.8:3128/
export no_proxy=$no_proxy,16.27.53.8                   # Don't use squid to talk to the pypi mirror

# export DIB_COMMON_ELEMENTS="stackuser pypi-openstack"

# For the local mirror, offline mode.
export DIB_COMMON_ELEMENTS="stackuser pypi"
export PYPI_MIRROR_URL=http://16.27.53.8/pypi/latest      # point this at the pypi mirror.
export DIB_NO_PYPI_PIP=1

export OVERCLOUD_CONTROL_DIB_EXTRA_ARGS='apt-sources dpkg rabbitmq-server openjdk-7-jre logstash'
export OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS='apt-sources dpkg openjdk-7-jre logstash elasticsearch'
export DIB_APT_SOURCES='my_sources.list'
export DIB_ADD_APT_KEYS='my_apt_keys'

export NODE_CPU=1 NODE_MEM=$((6*1024)) NODE_DISK=20 NODE_ARCH=amd64
export OVERCLOUD_COMPUTESCALE=1

# Drop into a (prompt-less) bash on an error.
export break=after-error

# Make "sudo service ..." work.
unset UPSTART_SESSION       # Some desktops might complain about "no such job: libvirt-bin" or similar

# Clone our local git copies. Make devtest.sh prefer your local repositories. You'll still need to have stuff checked in to them!
for n in $(find $TRIPLEO_ROOT -maxdepth 2 -name .git -print0 | xargs -0 dirname | sort); do
  [ "hp-nova" = $(basename "$n") ] && continue

  # bn=${$(basename "$n")//[^A-Za-z0-9_]/_}
  nn=$(basename "$n")      # work around older bash
  bn=${nn//[^A-Za-z0-9_]/_}

  printf "%-30s" "$bn"
  export DIB_REPOTYPE_"$bn"=git

  export DIB_REPOLOCATION_"$bn"="$n"
  unset branch
  if branch=$(cd "$n" && git symbolic-ref --short -q HEAD); then
        export DIB_REPOREF_"$bn"="$branch"
  else
        unset DIB_REPOREF_"$bn"
  fi

  pushd -q "${n}"
  if git rev-parse master > /dev/null 2>&1; then
    eval echo -n \"\${DIB_REPOLOCATION_"$bn"}\"
    eval echo \" \${DIB_REPOREF_"$bn"}\"

    if [ "$(git rev-parse master)" != "$(git rev-parse HEAD)" ]; then
      IFS=$'\n';
      for f in $(git log master.. --oneline); do
        printf '  \e[1;31m%-60s \e[1;34m%s\e[m\n' "${f}" "$(git show $(echo $f | cut -d" " -f1) | awk '/Change-Id/ {print "http://review.openstack.org/r/" $2}')";
      done
    fi
  fi
  popd -q
done

#(
#  cd ~/.cache/tripleo
#  for nn in diskimage-builder \
#            tripleo-heat-templates \
#            tripleo-image-elements \
#            tripleo-incubator; do
#    cd $nn
#    bn=${nn//[^A-Za-z0-9_]/_}
#    export BRANCH=DIB_REPOREF_$bn
#    if [ "$(git rev-parse --abbrev-ref HEAD)" != "${(P)BRANCH}" ]; then
#      git clean -f -d
#      git checkout ${(P)BRANCH}
#    fi
#    printf "%-30s" "$nn"
#    git fetch
#    git reset --hard origin/${(P)BRANCH}
#    cd ..
#  done
#)
