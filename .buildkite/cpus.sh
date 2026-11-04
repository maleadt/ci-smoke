#!/usr/bin/env bash
# Prints every view of the job's CPU width and fails unless all equal
# EXPECT_CPUS (the step's sched_cpus_limit, or its group's default).
set -u
expect=${EXPECT_CPUS:?}
echo "agent=${BUILDKITE_AGENT_NAME} retry=${BUILDKITE_RETRY_COUNT}"
n_nproc=$(nproc)
mask=$(grep Cpus_allowed_list /proc/self/status | awk '{print $2}')
echo "nproc: ${n_nproc}"
grep Cpus_allowed_list /proc/self/status
cg=$(cut -d: -f3 /proc/self/cgroup)
echo "/proc/self/cgroup: $(cat /proc/self/cgroup)"
if [ -r "/sys/fs/cgroup${cg}/cpuset.cpus" ]; then
    echo "cpuset.cpus (/sys/fs/cgroup${cg}): $(cat /sys/fs/cgroup${cg}/cpuset.cpus)"
    echo "cpuset.cpus.effective: $(cat /sys/fs/cgroup${cg}/cpuset.cpus.effective 2>/dev/null)"
else
    echo "cpuset.cpus: not visible at /sys/fs/cgroup${cg}"
fi
echo "JULIA_CPU_THREADS=${JULIA_CPU_THREADS:-unset} OMP_THREAD_LIMIT=${OMP_THREAD_LIMIT:-unset}"
# Count the CPUs in the mask (e.g. "4-5,20").
count=0
IFS=, read -ra parts <<< "${mask}"
for p in "${parts[@]}"; do
    if [[ $p == *-* ]]; then count=$((count + ${p#*-} - ${p%-*} + 1)); else count=$((count + 1)); fi
done
echo "mask width: ${count}"
dir=$(mktemp -d)
url=https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.10-linux-x86_64.tar.gz
if command -v curl > /dev/null; then curl -fsSL "$url"; else wget -qO- "$url"; fi | tar xz -C "$dir" --strip-components=1
n_julia=$("$dir/bin/julia" --startup-file=no -t auto -e 'print(Threads.nthreads())')
echo "julia -t auto nthreads: ${n_julia}"
echo "julia Sys.CPU_THREADS: $("$dir/bin/julia" --startup-file=no -e 'print(Sys.CPU_THREADS)')"
rm -rf "$dir"
fail=0
for v in "nproc=${n_nproc}" "mask=${count}" "JULIA_CPU_THREADS=${JULIA_CPU_THREADS:-}" "julia=${n_julia}"; do
    if [ "${v#*=}" != "${expect}" ]; then echo "MISMATCH: ${v}, expected ${expect}"; fail=1; fi
done
[ $fail = 0 ] && echo "all CPU views equal ${expect}"
exit $fail
