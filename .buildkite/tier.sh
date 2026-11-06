#!/usr/bin/env bash
# The claims the scheduler picks the cache pool from, and the cache it gave the job.
echo "tier: source=${BUILDKITE_SOURCE:-} branch=${BUILDKITE_BRANCH:-} tag=${BUILDKITE_TAG:-} pr=${BUILDKITE_PULL_REQUEST:-} agent=${BUILDKITE_AGENT_NAME:-} retry=${BUILDKITE_RETRY_COUNT:-}"
echo "tier: cache=${BUILDKITE_PLUGIN_JULIA_CACHE_DIR:-} build_path=${BUILDKITE_BUILD_PATH:-}"
