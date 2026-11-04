#!/usr/bin/env bash
# A known load for checking the resource record: two busy CPUs and ~1.5 GiB of
# touched, incompressible memory for LOAD_SECONDS.
set -u
secs=${LOAD_SECONDS:-30}
echo "uname: $(uname -a)"
yes > /dev/null & p1=$!
yes > /dev/null & p2=$!
if command -v perl > /dev/null; then
    echo "holding memory with perl"
    perl -e 'my $x = join "", map { chr(int rand 256) } 1..(1<<20); $x x= 1536; sleep $ARGV[0]' "${secs}" &
else
    # Linux and FreeBSD fill a read buffer from /dev/zero page by page.
    echo "holding memory with dd"
    dd if=/dev/zero bs=1610612736 count=1 2>/dev/null | sleep "${secs}" &
fi
sleep 10
ps -axo rss,comm 2>/dev/null | grep -E '[ /](perl|dd)(\.exe)?$' || ps 2>/dev/null
sleep $((secs - 10))
kill "${p1}" "${p2}" 2>/dev/null
wait
echo "load done"
