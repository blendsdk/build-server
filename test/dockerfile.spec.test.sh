#!/bin/bash
# Static specification checks for the runner Dockerfile and packaging hygiene files.
#
# The image must install only packages that exist on Ubuntu 24.04 (the noble time64 renames), and
# it must contain the inner Docker engine used by each runner's private daemon. The ignore files
# must keep deploy-SSH key material out of git and out of Docker build contexts.
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

# git runs in start.sh before the runner registers and backs actions/checkout; openssh-client
# serves the SSH keys staged for private repositories.
for pkg in git openssh-client; do
    grep -Eq "(^|[[:space:]])${pkg}([[:space:]]|$)" "${DOCKERFILE}" ||
        fail "Dockerfile must install ${pkg}"
done

# Node package managers installed globally: pnpm is used by current projects.
grep -Eq "(^|[[:space:]])pnpm([[:space:]]|$)" "${DOCKERFILE}" || fail "Dockerfile must install pnpm globally"
grep -Eq "(^|[[:space:]])lerna([[:space:]]|$)" "${DOCKERFILE}" && fail "lerna must not be installed"

# npm 12 blocks dependency lifecycle scripts unless the package is allowlisted. pnpm's install
# script is what replaces its shebang-less placeholder with the native binary, so Turbo, which
# spawns the binary directly, fails with "Exec format error" when the script is blocked.
grep -Eq 'NPM_CONFIG_ALLOW_SCRIPTS=pnpm|allow-scripts=pnpm' "${DOCKERFILE}" ||
    fail "Dockerfile must allowlist pnpm's install scripts for npm 12"

# The work_queue lock helper was removed from the fleet.
grep -Eq "(^|[[:space:]])work_queue([[:space:]]|$)" "${DOCKERFILE}" && fail "work_queue must not be shipped"

# deploy-SSH key material must never be committed or sent as build context. Every deploy folder
# lives under deploy-ssh/ (enforced separately), so these fixed exclusions cover every key path.
GITIGNORE="${ROOT}/.gitignore"
DOCKERIGNORE="${ROOT}/.dockerignore"

[ -f "${GITIGNORE}" ] || fail ".gitignore is missing"
[ -f "${DOCKERIGNORE}" ] || fail ".dockerignore is missing"

grep -Eq '^[[:space:]]*deploy-ssh/[[:space:]]*$' "${GITIGNORE}" ||
    fail ".gitignore must exclude the deploy-ssh/ directory so keys are never committed"

grep -Eq '^[[:space:]]*deploy-ssh[[:space:]]*$' "${DOCKERIGNORE}" ||
    fail ".dockerignore must exclude deploy-ssh so keys are never sent as build context"

echo "Dockerfile spec tests: PASS"
