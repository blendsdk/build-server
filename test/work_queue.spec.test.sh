#!/bin/bash
# Specification tests for the work_queue lock utility.
#
# These tests treat work_queue as a black box and assert the documented behavior:
# queue acquires the lock when it is free and blocks while it is held; clear releases it;
# an unknown command fails. The lock lives under ${HOME}/.wqcache.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WQ="${ROOT}/work_queue"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="${T}/home"
mkdir -p "${HOME}"
LOCK="${HOME}/.wqcache/demo"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# The lock is free: queue acquires it immediately.
HOME="${HOME}" bash "${WQ}" queue demo
[ -f "${LOCK}" ] || fail "queue did not create the lock file"
echo "PASS: queue acquires a free lock"

# While the lock is held by the test, a second queue must block.
HOME="${HOME}" bash "${WQ}" queue demo &
BLOCKED_PID=$!
sleep 1
kill -0 "${BLOCKED_PID}" 2>/dev/null || fail "second queue did not block while the lock was held"
echo "PASS: queue blocks while the lock is held"

# Clearing the lock releases the blocked queue, which then acquires the lock.
HOME="${HOME}" bash "${WQ}" clear demo
[ ! -f "${LOCK}" ] || fail "clear did not remove the lock file"
for _ in $(seq 1 15); do
    [ -f "${LOCK}" ] && break
    sleep 1
done
[ -f "${LOCK}" ] || fail "blocked queue never acquired the released lock"
wait "${BLOCKED_PID}" || fail "blocked queue exited non-zero after acquiring the lock"
echo "PASS: clear releases a blocked queue"

# Clearing an absent lock is harmless.
HOME="${HOME}" bash "${WQ}" clear demo
HOME="${HOME}" bash "${WQ}" clear demo
echo "PASS: clear is idempotent"

# Unknown commands fail.
set +e
HOME="${HOME}" bash "${WQ}" bogus demo >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "unknown command should exit non-zero"
echo "PASS: unknown command exits non-zero"

echo "work_queue spec tests: PASS"
