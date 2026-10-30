#!/bin/bash
# Runs Julia nightly with its LMDB object cache in a depot that persists across
# jobs and in one that is deleted afterwards (leaking its SysV semaphore set).
set -euo pipefail
echo "agent=$BUILDKITE_AGENT_NAME job=$BUILDKITE_JOB_ID"
cache="$BUILDKITE_PLUGIN_JULIA_CACHE_DIR"
jl="$cache/julia-nightly"
if [ ! -x "$jl/bin/julia" ]; then
    rm -rf "$jl.partial" && mkdir -p "$jl.partial"
    curl -fsSL https://julialangnightlies-s3.julialang.org/bin/macos/aarch64/julia-latest-macos-aarch64.tar.gz |
        tar -xz -C "$jl.partial" --strip-components=1
    mv "$jl.partial" "$jl"
fi
"$jl/bin/julia" --version

run_julia() {  # depot label hold
    local out="$TMPDIR/out-$2.txt"
    echo "--- $2 depot ($1)"
    JULIA_DEPOT_PATH="$1" JULIA_OBJCACHE_LOG="$TMPDIR/objcache-$2.log" HOLD="$3" \
        "$jl/bin/julia" --startup-file=no -e '
            f(x) = x * 2 + 1
            println("f(3) = ", f(3))
            run(ignorestatus(`ipcs -s`))
            sleep(parse(Int, ENV["HOLD"]))' 2>&1 | tee "$out"
    if grep -qi "objcache.*error\|No space left" "$out"; then
        echo "objcache failed"; exit 1
    fi
}

persistent="$cache/objcache-depot"
warm=false; [ -d "$persistent/cache" ] && warm=true
run_julia "$persistent" persistent 20
if $warm && ! grep -Eq "cache hit: +[1-9]" "$TMPDIR/out-persistent.txt"; then
    echo "expected objcache hits in the persistent depot"; exit 1
fi

scratch=$(mktemp -d)
run_julia "$scratch" scratch 0
rm -rf "$scratch"
