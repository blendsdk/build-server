#!/bin/bash
# Static specification checks for the runner Dockerfile.
#
# The image must install only packages that exist on Ubuntu 24.04 (the noble time64 renames), and
# it must contain the inner Docker engine used by each runner's private daemon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="${ROOT}/Dockerfile"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[ -f "${DOCKERFILE}" ] || fail "Dockerfile is missing"

# Packages that do not exist (or are snap stubs) on Ubuntu 24.04 must not be installed.
for pkg in libgcc1 chromium-browser liblttng-ust1 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libglib2.0-0 libgtk-3-0 upx; do
    if grep -Eq "(^|[[:space:]])${pkg}([[:space:]]|$)" "${DOCKERFILE}"; then
        fail "${pkg} is not available on Ubuntu 24.04 and must not be installed"
    fi
done

# Required replacements, the inner Docker engine, and a current runner version must be present.
grep -Fq 'liblttng-ust1t64' "${DOCKERFILE}" || fail "Dockerfile must install liblttng-ust1t64"
grep -Fq 'upx-ucl' "${DOCKERFILE}" || fail "Dockerfile must install upx-ucl"
grep -Fq 'get.docker.com' "${DOCKERFILE}" || fail "Dockerfile must install the inner Docker engine"
grep -Fq 'RUNNER_VERSION="2.337.0"' "${DOCKERFILE}" || fail "Dockerfile must pin runner 2.337.0"

echo "Dockerfile spec tests: PASS"
