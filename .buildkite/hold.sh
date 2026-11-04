#!/usr/bin/env bash
# Runs for HOLD_SECONDS on the first attempt so a scheduler stop interrupts it;
# a retry passes at once.
echo "agent=${BUILDKITE_AGENT_NAME} job=${BUILDKITE_JOB_ID} retry=${BUILDKITE_RETRY_COUNT} uname=$(uname -s)"
if [ "${BUILDKITE_RETRY_COUNT}" = 0 ]; then
    echo "holding for ${HOLD_SECONDS:-900} s at $(date -u +%H:%M:%S)"
    sleep "${HOLD_SECONDS:-900}"
    echo "hold finished without being stopped"
    exit 1
fi
echo "retry: passing"
