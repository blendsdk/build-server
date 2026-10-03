#!/bin/bash
# Specification tests for the runner entrypoint start.sh.
#
# start.sh registers a persistent runner for its organization and runs it. The tests replace the
# external commands (git, curl, config.sh, run.sh, nvm) with stubs and assert:
#   - a missing registration token fails before any registration happens;
#   - a valid token registers with --replace and then runs the runner;
#   - SIGTERM deregisters the runner before the private daemon is stopped.
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
echo "git $*" >> "${TRACE}"
exit 0
EOF

cat > "${T}/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "${TRACE}"
printf '%s' "${CURL_BODY}"
exit 0
EOF

cat > "${T}/bin/docker" <<'EOF'
#!/bin/bash
printf 'docker %s\n' "$*" >> "${TRACE}"
exit 0
EOF

cat > "${T}/runner/config.sh" <<'EOF'
#!/bin/bash
echo "config.sh $*" >> "${TRACE}"
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
: > "${TRACE}"

# No registration token: fail before any registration.
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":null}' PATH="${T}/bin:${PATH}" bash "${START}" >"${T}/out-null" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "start.sh should exit non-zero when the token is null"
grep -qi 'registration token' "${T}/out-null" || fail "error should name the registration token"
grep -q 'config.sh' "${TRACE}" && fail "config.sh must not run with an invalid token"
echo "PASS: start.sh fails before registration when the token is missing"

# Valid token: register with --replace, then run.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":"fake-token"}' PATH="${T}/bin:${PATH}" bash "${START}" >"${T}/out-valid" 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "start.sh should exit zero after a normal run"
REG_LINE="$(grep -- '--replace' "${TRACE}" | tail -1)"
[ -n "${REG_LINE}" ] || fail "registration must use --replace"
for arg in '--unattended' '--url https://github.com/TestOrg' '--token fake-token' '--name TestOrg_testhost'; do
    case "${REG_LINE}" in
        *"${arg}"*) ;;
        *) fail "registration line is missing ${arg}" ;;
    esac
done
grep -q 'run.sh' "${TRACE}" || fail "runner was not started"
grep -q -- 'user.email TestOrg_testhost@users.noreply.github.com' "${TRACE}" ||
    fail "default runner email domain wrong"
grep -q 'docker login' "${TRACE}" && fail "must not log in without registry credentials"
echo "PASS: start.sh registers with --replace and runs"

# The inner daemon is logged in to the co-located registry so jobs can push images.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    REGISTRY_ADDR=registry:5000 REGISTRY_USER=ci REGISTRY_PASS=secret \
    CURL_BODY='{"token":"fake-token"}' PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "start.sh should exit zero with registry credentials"
grep -q 'docker login registry:5000 -u ci --password-stdin' "${TRACE}" ||
    fail "the inner daemon must log in to the co-located registry"
echo "PASS: the inner daemon logs in to the co-located registry"

# A custom email domain is used verbatim.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    RUNNER_EMAIL_DOMAIN=example.org CURL_BODY='{"token":"fake-token"}' \
    PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "start.sh should exit zero with a custom email domain"
grep -q -- 'user.email TestOrg_testhost@example.org' "${TRACE}" || fail "custom email domain not used"
echo "PASS: custom runner email domain"

# Default GitHub endpoints are used when the URL variables are unset.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":"fake-token"}' PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "start.sh should exit zero with default URLs"
grep -q 'https://api.github.com/orgs/TestOrg/actions/runners/registration-token' "${TRACE}" ||
    fail "default registration API endpoint missing"
grep -q -- '--url https://github.com/TestOrg' "${TRACE}" || fail "default registration URL missing"
echo "PASS: default GitHub endpoints"

# Custom GitHub Enterprise endpoints are used for the API and the registration URL.
: > "${TRACE}"
set +e
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    GITHUB_URL=https://ghe.example.com/TestOrg GITHUB_API_URL=https://ghe.example.com/api/v3 \
    CURL_BODY='{"token":"fake-token"}' PATH="${T}/bin:${PATH}" bash "${START}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "start.sh should exit zero with custom URLs"
grep -q 'https://ghe.example.com/api/v3/orgs/TestOrg/actions/runners/registration-token' "${TRACE}" ||
    fail "custom registration API endpoint missing"
grep -q -- '--url https://ghe.example.com/TestOrg' "${TRACE}" || fail "custom registration URL missing"
echo "PASS: custom GitHub Enterprise endpoints"

# SIGTERM: deregister the runner and exit 143. The entrypoint supervisor stops the daemon after
# this process exits (covered by the entrypoint spec tests).
: > "${TRACE}"
HOME="${T}/home" RUNNER_HOME="${T}/runner" HOSTNAME=testhost ORGANIZATION=TestOrg ACCESS_TOKEN=tok \
    CURL_BODY='{"token":"fake-token"}' RUN_SLEEP=30 \
    PATH="${T}/bin:${PATH}" bash "${START}" >"${T}/out-term" 2>&1 &
RUNNER_PID=$!
sleep 1
kill -TERM "${RUNNER_PID}"
set +e
wait "${RUNNER_PID}"
CODE=$?
set -e
[ "${CODE}" -eq 143 ] || fail "SIGTERM should exit with 143, got ${CODE}"
REGISTER_LINE="$(grep -n -- '--replace' "${TRACE}" | tail -1 | cut -d: -f1)"
REMOVE_LINE="$(grep -n 'config.sh remove' "${TRACE}" | tail -1 | cut -d: -f1)"
[ -n "${REGISTER_LINE}" ] || fail "runner was never registered"
[ -n "${REMOVE_LINE}" ] || fail "cleanup did not deregister the runner"
[ "${REGISTER_LINE}" -lt "${REMOVE_LINE}" ] || fail "runner was not deregistered after registration"
echo "PASS: SIGTERM deregisters the runner and exits 143"

echo "start.sh spec tests: PASS"
