#!/usr/bin/env bash
# Known load for the resource record: two busy CPUs and LOAD_MIB (1024) MiB of
# touched, incompressible memory for LOAD_SECONDS (30).
set -u
secs=${LOAD_SECONDS:-30} mib=${LOAD_MIB:-1024}
echo "uname: $(uname -a)"
echo "load: 2 busy CPUs, ${mib} MiB held, ${secs} s, start $(date -u +%H:%M:%S)"
yes > /dev/null & p1=$!
yes > /dev/null & p2=$!
if command -v perl > /dev/null; then
    perl -e 'my $x = join "", map { chr(int rand 256) } 1..(1<<20); $x x= $ARGV[1]; sleep $ARGV[0]' "${secs}" "${mib}" &
else
    dd if=/dev/zero bs=$((mib * 1048576)) count=1 2>/dev/null | sleep "${secs}" &
fi
sleep 10
ps -axo rss,comm 2>/dev/null | grep -E '[ /](perl|dd)(\.exe)?$' || ps 2>/dev/null | grep -E 'perl|dd'
sleep $((secs - 10))
kill "${p1}" "${p2}" 2>/dev/null
wait
echo "load done $(date -u +%H:%M:%S)"
