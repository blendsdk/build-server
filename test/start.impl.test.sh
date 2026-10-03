#!/bin/bash
# Implementation tests for start.sh.
#
# Edge cases beyond the specification tests: the production runner directory is used when
# RUNNER_HOME is unset, a malformed registration API response still produces the named error, and
# a failed registration stops the script before the runner is started.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START="${ROOT}/start.sh"
T="$(mktemp -d)"
trap 'pkill -f "${T}/runner/run.sh" 2>/dev/null || true; rm -rf "$T"' EXIT

mkdir -p "${T}/bin" "${T}/runner" "${T}/home"

cat > "${T}/home/.profile" <<'EOF'
nvm() { echo "nvm $*" >> "${TRACE}"; }
EOF

cat > "${T}/bin/git" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "${T}/bin/curl" <<'EOF'
#!/bin/bash
printf '%s' "${CURL_BODY}"
exit 0
EOF

cat > "${T}/runner/config.sh" <<'EOF'
#!/bin/bash
echo "config.sh $*" >> "${TRACE}"
if [ "${1:-}" != "remove" ] && [ "${CONFIG_FAIL:-0}" = "1" ]; then
    exit 1
fi
exit 0
EOF

cat > "${T}/runner/run.sh" <<'EOF'
#!/bin/bash
echo "run.sh" >> "${TRACE}"
sleep "${RUN_SLEEP:-0.2}"
EOF

chmod +x "${T}/bin/"* "${T}/runner/"*

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

export TRACE="${T}/trace"

# RUNNER_HOME unset: the script falls back to the production directory and fails fast when it is
# not present, without touching any runner scripts.
: > "${TRACE}"
set +e
HOME="${T}/home" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":"fake-token"}' PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "start.sh should fail when the default runner directory is absent"
grep -q 'config.sh' "${TRACE}" && fail "config.sh must not run without a runner directory"
echo "PASS: start.sh falls back to the production runner directory and fails fast when absent"

# A malformed API response (for example an HTML error page) must still print the named error.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='<html>service unavailable</html>' PATH="${T}/bin:${PATH}" bash "${START}" >"${T}/out-html" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "start.sh should fail on a malformed API response"
grep -q 'registration token' "${T}/out-html" || fail "named registration-token error missing"
grep -q 'config.sh' "${TRACE}" && fail "config.sh must not run on a malformed API response"
echo "PASS: malformed API response produces the named error"

# A failed registration stops the script before the runner is started.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":"fake-token"}' CONFIG_FAIL=1 PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "start.sh should fail when registration fails"
grep -q 'run.sh' "${TRACE}" && fail "runner must not start after a failed registration"
echo "PASS: failed registration stops before running"

echo "start.sh impl tests: PASS"
