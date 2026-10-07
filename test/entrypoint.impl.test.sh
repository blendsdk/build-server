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

# The setpriv stub records whether the staged deploy directory already exists at the moment the
# runner would start, so tests can prove staging happens before the runner user is dropped.
cat > "${T}/bin/setpriv" <<'EOF'
#!/bin/bash
echo "setpriv $*" >> "${TRACE}"
if [ -d "${RUNNER_USER_HOME:-/home/docker}/.ssh/deploy.d" ]; then
    echo "deploy.d-present-before-runner" >> "${TRACE}"
else
    echo "deploy.d-absent-before-runner" >> "${TRACE}"
fi
echo "runner-start" >> "${TRACE}"
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

# Create a deploy-ssh source fixture. Modes are permissive (directories 0755, files 0644): the
# chmod stub in this suite is a no-op, so these cases assert warnings and include behavior rather
# than exact modes (the spec suite owns mode exactness).
make_deploy_source() {
    local dir="$1"
    local variant="$2"
    mkdir -p "${dir}/keys"
    case "${variant}" in
        full)
            printf 'Host prod\n  HostName prod.example\n' > "${dir}/config"
            printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' > "${dir}/keys/prod"
            ;;
        keys-only)
            printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' > "${dir}/keys/prod"
            ;;
        *)
            fail "unknown deploy source fixture variant: ${variant}"
            ;;
    esac
    chmod 755 "${dir}" "${dir}/keys"
    find "${dir}" -type f -exec chmod 644 {} +
}

# Create an isolated runner home with a private ~/.ssh directory.
make_runner_home() {
    local home="$1"
    mkdir -p "${home}/.ssh"
    chmod 700 "${home}/.ssh"
}

# Run the entrypoint against a staging fixture and a ready daemon, writing combined output to $3.
# Extra tuning (for example CHMOD_EXIT) is taken from exported variables in the caller's shell.
run_staged_entry() {
    local src="$1"
    local home="$2"
    local out="$3"
    DOCKERD_LOG="${T}/dockerd-impl-staging.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
        DEPLOY_SSH_SOURCE="${src}" RUNNER_USER_HOME="${home}" \
        PATH="${T}/bin:${PATH}" bash "${ENTRY}" >"${out}" 2>&1
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

# Mode-normalization failure warns and continues: a failing chmod must not stop the runner and must
# not change the exit status.
export TRACE="${T}/trace-mode-warn"
: > "${TRACE}"
MODE_SRC="${T}/mode-warn-src"
MODE_HOME="${T}/mode-warn-home"
make_deploy_source "${MODE_SRC}" full
make_runner_home "${MODE_HOME}"
export CHMOD_EXIT=1
set +e
run_staged_entry "${MODE_SRC}" "${MODE_HOME}" "${T}/out-mode-warn"
MODE_CODE=$?
set -e
unset CHMOD_EXIT
[ "${MODE_CODE}" -eq 0 ] || fail "mode-normalization failure must not change the exit status, got ${MODE_CODE}"
grep -qi 'modes were not normalized' "${T}/out-mode-warn" ||
    fail "mode-normalization failure must print a mode warning"
grep -q 'setpriv' "${TRACE}" || fail "runner must still start after a mode-normalization failure"
echo "PASS: mode-normalization failure warns and the runner still starts"

# Ownership failure warns and continues: a failing chown must not stop the runner.
export TRACE="${T}/trace-chown-warn"
: > "${TRACE}"
OWN_SRC="${T}/chown-warn-src"
OWN_HOME="${T}/chown-warn-home"
make_deploy_source "${OWN_SRC}" full
make_runner_home "${OWN_HOME}"
export CHOWN_EXIT=1
set +e
run_staged_entry "${OWN_SRC}" "${OWN_HOME}" "${T}/out-chown-warn"
OWN_CODE=$?
set -e
unset CHOWN_EXIT
[ "${OWN_CODE}" -eq 0 ] || fail "ownership failure must not change the exit status, got ${OWN_CODE}"
grep -qi 'ownership' "${T}/out-chown-warn" ||
    fail "ownership failure must print an ownership warning"
grep -q 'setpriv' "${TRACE}" || fail "runner must still start after an ownership failure"
echo "PASS: ownership failure warns and the runner still starts"

# Keys-only source: a source without config stages the key, prints the success line, and does not
# add an Include line (there is nothing to include).
export TRACE="${T}/trace-impl-keys-only"
: > "${TRACE}"
IMPL_KEYS_SRC="${T}/impl-keys-only-src"
IMPL_KEYS_HOME="${T}/impl-keys-only-home"
make_deploy_source "${IMPL_KEYS_SRC}" keys-only
make_runner_home "${IMPL_KEYS_HOME}"
# Seed a config the way the image does; a keys-only source must leave it byte-identical.
printf 'Host github.com\n    IdentityFile ~/.ssh/id_rsa\n' > "${IMPL_KEYS_HOME}/.ssh/config"
cp "${IMPL_KEYS_HOME}/.ssh/config" "${T}/impl-keys-config.before"
run_staged_entry "${IMPL_KEYS_SRC}" "${IMPL_KEYS_HOME}" "${T}/out-impl-keys-only" || {
    cat "${T}/out-impl-keys-only" >&2
    fail "a keys-only source should exit zero"
}
[ -f "${IMPL_KEYS_HOME}/.ssh/deploy.d/keys/prod" ] ||
    fail "a keys-only source must stage its key"
grep -q "Deploy SSH staged from ${IMPL_KEYS_SRC}" "${T}/out-impl-keys-only" ||
    fail "a keys-only source must print the staging success line"
grep -q 'Include ~/.ssh/deploy.d/config' "${IMPL_KEYS_HOME}/.ssh/config" &&
    fail "a keys-only source must not add the Include line"
cmp -s "${T}/impl-keys-config.before" "${IMPL_KEYS_HOME}/.ssh/config" ||
    fail "a keys-only source must leave an existing ~/.ssh/config untouched"
echo "PASS: a keys-only source stages the key and leaves the config untouched"

# Config-only source: stages the config and wires the Include line without any keys.
export TRACE="${T}/trace-impl-config-only"
: > "${TRACE}"
CONFIG_ONLY_SRC="${T}/impl-config-only-src"
CONFIG_ONLY_HOME="${T}/impl-config-only-home"
mkdir -p "${CONFIG_ONLY_SRC}"
printf 'Host app-prod\n    User deploy\n' > "${CONFIG_ONLY_SRC}/config"
make_runner_home "${CONFIG_ONLY_HOME}"
run_staged_entry "${CONFIG_ONLY_SRC}" "${CONFIG_ONLY_HOME}" "${T}/out-impl-config-only" || {
    cat "${T}/out-impl-config-only" >&2
    fail "a config-only source should exit zero"
}
[ -f "${CONFIG_ONLY_HOME}/.ssh/deploy.d/config" ] ||
    fail "a config-only source must stage its config"
[ "$(head -n1 "${CONFIG_ONLY_HOME}/.ssh/config")" = "Include ~/.ssh/deploy.d/config" ] ||
    fail "a config-only source must wire the Include line"
grep -q "Deploy SSH staged from ${CONFIG_ONLY_SRC}" "${T}/out-impl-config-only" ||
    fail "a config-only source must print the staging success line"
echo "PASS: a config-only source stages the config and wires the Include line"

# Alternated sources across boots: the second boot must reflect source B only (source A's extra
# file is gone) and must not duplicate the Include line.
export TRACE="${T}/trace-impl-alternate"
: > "${TRACE}"
ALT_SRC_A="${T}/impl-alt-src-a"
ALT_SRC_B="${T}/impl-alt-src-b"
ALT_HOME="${T}/impl-alt-home"
make_deploy_source "${ALT_SRC_A}" full
printf 'only-in-a\n' > "${ALT_SRC_A}/only-a"
make_deploy_source "${ALT_SRC_B}" full
printf 'from-b\n' > "${ALT_SRC_B}/marker"
make_runner_home "${ALT_HOME}"
run_staged_entry "${ALT_SRC_A}" "${ALT_HOME}" "${T}/out-alt-1" || {
    cat "${T}/out-alt-1" >&2
    fail "the first alternated boot should exit zero"
}
run_staged_entry "${ALT_SRC_B}" "${ALT_HOME}" "${T}/out-alt-2" || {
    cat "${T}/out-alt-2" >&2
    fail "the second alternated boot should exit zero"
}
ALT_TARGET="${ALT_HOME}/.ssh/deploy.d"
[ ! -e "${ALT_TARGET}/only-a" ] || fail "a file from the earlier source must not survive"
[ "$(cat "${ALT_TARGET}/marker")" = "from-b" ] || fail "deploy.d must reflect the latest source"
[ "$(grep -c 'Include ~/.ssh/deploy.d/config' "${ALT_HOME}/.ssh/config")" -eq 1 ] ||
    fail "the Include line must appear exactly once after alternated boots"
echo "PASS: alternated sources replace the target and keep one Include line"

# Staging runs before the runner user starts: deploy.d must already exist when setpriv runs.
export TRACE="${T}/trace-impl-order"
: > "${TRACE}"
ORDER_SRC="${T}/impl-order-src"
ORDER_HOME="${T}/impl-order-home"
make_deploy_source "${ORDER_SRC}" full
make_runner_home "${ORDER_HOME}"
run_staged_entry "${ORDER_SRC}" "${ORDER_HOME}" "${T}/out-impl-order" || {
    cat "${T}/out-impl-order" >&2
    fail "the ordering boot should exit zero"
}
grep -q 'deploy.d-present-before-runner' "${TRACE}" ||
    fail "deploy.d must exist by the time the runner starts"
grep -q 'deploy.d-absent-before-runner' "${TRACE}" &&
    fail "deploy.d must not be missing when the runner starts"
RUNNER_START_LINE="$(grep -n 'runner-start' "${TRACE}" | tail -1 | cut -d: -f1)"
PRESENT_LINE="$(grep -n 'deploy.d-present-before-runner' "${TRACE}" | tail -1 | cut -d: -f1)"
[ "${PRESENT_LINE}" -lt "${RUNNER_START_LINE}" ] ||
    fail "deploy.d must be staged before runner-start"
echo "PASS: staging completes before the runner user starts"

echo "entrypoint impl tests: PASS"
