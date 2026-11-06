#!/bin/bash
# Report the Buildkite agent token every visible process holds (prefix and
# length only), and fail if a cluster token (bkct_...) is readable anywhere:
# in a process's environment or command line, or in a file under the job's dirs.
set -u
fail=0
seen_jat=0
cluster='bkct_[A-Za-z0-9._-]{40,}'

report() {  # where value
    echo "$1: BUILDKITE_AGENT_TOKEN prefix=${2:0:6} length=${#2}"
    case "$2" in
        bkjat_*) seen_jat=1 ;;
        *) echo "FAIL: not a job acquisition token"; fail=1 ;;
    esac
}

scan_files() {  # dirs...
    for dir in "$@"; do
        [ -e "$dir" ] || continue
        echo "--- scanning $dir"
        if grep -r -l -a -E -s "$cluster" "$dir" 2>/dev/null | grep . ; then
            echo "FAIL: cluster token in files under $dir"; fail=1
        fi
    done
}

echo "agent=$BUILDKITE_AGENT_NAME os=$(uname -s) user=$(id -un 2>/dev/null)"
if [ -n "${BUILDKITE_AGENT_TOKEN:-}" ]; then
    echo "FAIL: the job's own environment has BUILDKITE_AGENT_TOKEN"; fail=1
fi
env | grep -q -E "$cluster" && { echo "FAIL: cluster token in the job's environment"; fail=1; }

case "$(uname -s)" in
Linux)
    n=0
    for dir in /proc/[0-9]*; do
        pid=${dir#/proc/}
        n=$((n + 1))
        token=$(tr '\0' '\n' < "$dir/environ" 2>/dev/null | sed -n 's/^BUILDKITE_AGENT_TOKEN=//p')
        [ -n "$token" ] && report "pid $pid ($(cat "$dir/comm" 2>/dev/null))" "$token"
        if cat "$dir/environ" "$dir/cmdline" 2>/dev/null | grep -q -a -E "$cluster"; then
            echo "FAIL: cluster token in pid $pid"; fail=1
        fi
    done
    echo "checked $n processes"
    scan_files /cache /persist /tmp /hooks /sharedcache /root /etc /usr/local /opt "$PWD"
    ;;
Darwin)
    python3 - "$cluster" <<'PY'
import ctypes, ctypes.util, re, sys
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
cluster = re.compile(sys.argv[1].encode())
n = libc.proc_listallpids(None, 0)
pids = (ctypes.c_int * (2 * n))()
n = libc.proc_listallpids(pids, ctypes.sizeof(pids))
readable = 0
bad = False
seen = False
for pid in pids[:n]:
    mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t(0)
    if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0 or size.value == 0:
        continue
    buf = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
        continue
    readable += 1
    data = buf.raw[:size.value]
    for m in re.finditer(rb"BUILDKITE_AGENT_TOKEN=([^\0]*)", data):
        token = m.group(1).decode(errors="replace")
        print(f"pid {pid}: BUILDKITE_AGENT_TOKEN prefix={token[:6]} length={len(token)}")
        if token.startswith("bkjat_"):
            seen = True
        else:
            print("FAIL: not a job acquisition token")
            bad = True
    if cluster.search(data):
        print(f"FAIL: cluster token in pid {pid}")
        bad = True
print(f"checked {readable} of {n} processes")
sys.exit(1 if bad else 0 if seen else 3)
PY
    case $? in
        0) seen_jat=1 ;;
        3) ;;
        *) fail=1 ;;
    esac
    for secret in /Users/tim/Julia/tools/ci/julia/sba-jat/agent/secrets/buildkite-agent-token \
                  /Users/tim/Julia/tools/ci/julia/sandboxed-buildkite-agent/agent/secrets/buildkite-agent-token; do
        if cat "$secret" >/dev/null 2>&1; then
            echo "FAIL: $secret is readable"; fail=1
        else
            echo "$secret: not readable"
        fi
    done
    scan_files "$BUILDKITE_PLUGIN_JULIA_CACHE_DIR" "$HOME" "$TMPDIR" "${BUILDKITE_HOOKS_PATH:-}" \
        "${BUILDKITE_BIN_PATH:-}" /private/tmp/bk-ci-smoke "$PWD"
    ;;
FreeBSD)
    # The agent is started by root, so only root can read its environment;
    # use sudo when the job has it (it then sees everything in the guest).
    as=""
    sudo -n true 2>/dev/null && as="sudo -n" && echo "using sudo"
    n=0
    for pid in $(ps -ax -o pid=); do
        n=$((n + 1))
        out=$($as procstat -e "$pid" 2>/dev/null; $as procstat -c "$pid" 2>/dev/null)
        token=$(printf '%s\n' "$out" | grep -o 'BUILDKITE_AGENT_TOKEN=[^ ]*' | head -n1)
        [ -n "$token" ] && report "pid $pid" "${token#BUILDKITE_AGENT_TOKEN=}"
        if printf '%s\n' "$out" | grep -q -E "$cluster"; then
            echo "FAIL: cluster token in pid $pid"; fail=1
        fi
    done
    echo "checked $n processes"
    scan_files /cache /tmp /var/tmp /var/run /usr/local/etc /usr/local/bin "$HOME" "$PWD"
    ;;
MINGW*|MSYS*|CYGWIN*)
    params='HKLM\SYSTEM\CurrentControlSet\Services\buildkite-agent-acquire-job\Parameters'
    token=$(MSYS_NO_PATHCONV=1 reg query "$params" /v AppEnvironmentExtra 2>/dev/null |
        grep -o 'BUILDKITE_AGENT_TOKEN=[^\\ ]*' | head -n1)
    [ -n "$token" ] && report "agent service environment" "${token#BUILDKITE_AGENT_TOKEN=}"
    if MSYS_NO_PATHCONV=1 reg query 'HKLM\SYSTEM\CurrentControlSet\Services' /s /f bkct_ /d 2>/dev/null | grep -q -E "$cluster"; then
        echo "FAIL: cluster token in the services registry"; fail=1
    fi
    if powershell.exe -NoProfile -Command 'Get-CimInstance Win32_Process | ForEach-Object { $_.CommandLine }' 2>/dev/null | grep -q -E "$cluster"; then
        echo "FAIL: cluster token in a command line"; fail=1
    fi
    scan_files /c/buildkite-agent /c/cache "$HOME" /c/Windows/Temp "$PWD"
    ;;
esac

[ "$seen_jat" = 1 ] || { echo "FAIL: no process with a job acquisition token found"; fail=1; }
[ "$fail" = 0 ] && echo "PASS: no cluster token readable, agent holds a job acquisition token"
exit "$fail"
