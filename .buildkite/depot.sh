#!/bin/bash
# Where Julia looks for artifacts in this job, and what the pool's depot holds.
set -euo pipefail
echo "agent: ${BUILDKITE_AGENT_NAME}"
echo "JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH:-}"
depot="${JULIA_DEPOT_PATH%%:*}"
echo "pool depot artifacts: $(ls "${depot}/artifacts" 2>/dev/null | tr '\n' ' ')"
echo "/artifact-store/artifacts: $(ls /artifact-store/artifacts 2>/dev/null | tr '\n' ' ')"
