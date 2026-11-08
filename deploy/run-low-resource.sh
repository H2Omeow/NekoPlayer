#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 command [arguments...]" >&2
    exit 2
fi

command -v flock >/dev/null 2>&1 || {
    echo "flock is required to prevent concurrent builds." >&2
    exit 1
}
command -v systemd-run >/dev/null 2>&1 || {
    echo "systemd-run is required for hard CPU and memory limits." >&2
    exit 1
}

lock_root=${XDG_RUNTIME_DIR:-/tmp}
exec 9>"$lock_root/nekoplayer-build-$(id -u).lock"
# NEKOPLAYER_LOCK_WAIT=<seconds> queues behind a running build instead of failing.
if [ -n "${NEKOPLAYER_LOCK_WAIT:-}" ]; then
    flock -w "$NEKOPLAYER_LOCK_WAIT" 9
else
    flock -n 9
fi || {
    echo "Another NekoPlayer build is running; refusing a parallel build." >&2
    exit 1
}

export CMAKE_BUILD_PARALLEL_LEVEL=2
export MAKEFLAGS=-j2
export CARGO_BUILD_JOBS=2
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -XX:ActiveProcessorCount=2"
export FLUTTER_TOOL_ARGS="${FLUTTER_TOOL_ARGS:-} --old_gen_heap_size=512"
NEKOPLAYER_REAL_NINJA=$(command -v ninja || true)
if [ -n "$NEKOPLAYER_REAL_NINJA" ]; then
    export NEKOPLAYER_REAL_NINJA
    script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
    export PATH="$script_dir/serial-bin:$PATH"
fi

systemd-run --user --scope --quiet \
    -p CPUQuota=200% -p MemoryMax=1536M -p MemorySwapMax=768M \
    nice -n 15 ionice -c 3 "$@"
