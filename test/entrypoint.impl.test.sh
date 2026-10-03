#!/bin/bash
# Implementation tests for the container entrypoint.
#
# These cover internals and edge cases beyond the specification tests: the readiness wait is
# bounded, a missing dockerd binary fails clearly, and failures while adjusting the socket do not
# prevent the runner from starting.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY="${ROOT}/entrypoint.sh"
T="$(mktemp -d)"
trap 'pkill -f "${T}/bin/dockerd" 2>/dev/null || true; rm -rf "$T"' EXIT

mkdir -p "${T}/bin"

cat > "${T}/bin/dockerd" <<'EOF'
#!/bin/bash
echo "dockerd-start" >> "${TRACE}"
sleep 30
EOF

cat > "${T}/bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >> "${TRACE}"
exit "${DOCKER_INFO_EXIT:-0}"
EOF

cat > "${T}/bin/setpriv" <<'EOF'
#!/bin/bash
echo "setpriv $*" >> "${TRACE}"
exit 0
EOF

cat > "${T}/bin/chown" <<'EOF'
#!/bin/bash
exit "${CHOWN_EXIT:-0}"
EOF

cat > "${T}/bin/chmod" <<'EOF'
#!/bin/bash
exit "${CHMOD_EXIT:-0}"
EOF

chmod +x "${T}/bin/"*

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# The readiness wait performs exactly the configured number of attempts.
export TRACE="${T}/trace-bounded"
: > "${TRACE}"
set +e
DOCKERD_LOG="${T}/bounded.log" DOCKER_READY_ATTEMPTS=2 DOCKER_INFO_EXIT=1 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "entrypoint should fail when the daemon never becomes ready"
ATTEMPTS="$(grep -c '^docker info' "${TRACE}")"
[ "${ATTEMPTS}" -eq 2 ] || fail "expected 2 readiness attempts, got ${ATTEMPTS}"
echo "PASS: readiness wait is bounded by DOCKER_READY_ATTEMPTS"

# A missing dockerd binary produces a clear failure without starting the runner.
export TRACE="${T}/trace-missing"
: > "${TRACE}"
mkdir -p "${T}/bin-no-dockerd"
cp "${T}/bin/docker" "${T}/bin/setpriv" "${T}/bin/chown" "${T}/bin/chmod" "${T}/bin-no-dockerd/"
set +e
DOCKERD_LOG="${T}/missing.log" DOCKER_READY_ATTEMPTS=1 DOCKER_INFO_EXIT=1 \
    PATH="${T}/bin-no-dockerd:${PATH}" bash "${ENTRY}" >"${T}/out-missing" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "entrypoint should fail when dockerd cannot start"
grep -qi 'failed to start' "${T}/out-missing" || fail "failure message missing"
grep -q 'setpriv' "${TRACE}" && fail "runner must not start when dockerd is missing"
echo "PASS: missing dockerd fails clearly"

# Socket adjustment failures are tolerated; the runner still starts.
export TRACE="${T}/trace-tolerant"
: > "${TRACE}"
DOCKERD_LOG="${T}/tolerant.log" DOCKER_READY_ATTEMPTS=2 DOCKER_INFO_EXIT=0 CHOWN_EXIT=1 CHMOD_EXIT=1 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" || fail "entrypoint should tolerate socket adjustment failures"
grep -q 'setpriv' "${TRACE}" || fail "runner should start when only socket adjustment fails"
echo "PASS: socket adjustment failures are tolerated"

echo "entrypoint impl tests: PASS"
