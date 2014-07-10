#!/bin/bash
#
# Function definitions for devtest.

function background_build() {
    if [ -z "$PARALLEL_BUILD" ]; then
        $*
    else
        (
            $*
        ) &
        # Write out the pid for waiting later
        bg_pid=$!
        new_pids="$new_pids${new_pids:+ }$bg_pid"
        pid_names[$bg_pid]="$1"
    fi
}

# Shared function for parallel builds
# If we are running in parallel wait on all of the backgrounded tasks and report failures
function wait_for_builds() {
    local new_pids=$*
    set +e
    while true ; do
        local wait_pids=$new_pids
        new_pids=
        echo "Waiting on pids: $wait_pids" >&2
        [ -z "$wait_pids" ]  && break
        for pid in $wait_pids ; do
            if ! ps -p $pid >/dev/null ; then
                wait $pid
                ret=$?
                if [ $ret -ne 0 ] ; then
                    echo "Wait on $pid returned $ret" >&2
                    echo "Image build failure - exiting..." >&2
                    pkill -TERM -P ${wait_pids// /,}
                    echo "Waiting for subprocesses to finish" >&2
                    wait
                    echo "Image build failure from ${pid_names[$pid]} ($ret) - exiting..." >&2
                    exit 1
                fi
            else
                new_pids="$new_pids${new_pids:+ }$pid"
            fi
        done
        echo "Waiting for builds to finish: $(date)" >&2
        sleep 20
    done
    # Just in case - wait for anything that may have been missed
    wait
    set -e
}
