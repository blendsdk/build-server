#!/bin/bash
# Specification tests for the container entrypoint.
#
# The entrypoint must start the private Docker daemon, wait for it, and then run the runner as the
# unprivileged "docker" user. When the daemon never becomes ready it must fail fast and must not
# start the runner. When the runner exits, the entrypoint must stop the daemon as root and exit
# with the runner's status. External commands are replaced with PATH stubs so the test never
# touches the host Docker socket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY="${ROOT}/entrypoint.sh"
T="$(mktemp -d)"
trap 'pkill -f "${T}/bin/dockerd" 2>/dev/null || true; rm -rf "$T"' EXIT

mkdir -p "${T}/bin"

# Sandbox root and the real chmod binary. The chmod stub delegates to the real binary only for
# paths under the sandbox so the suite still never touches host paths such as /var/run/docker.sock.
export TEST_SANDBOX="${T}"
REAL_CHMOD="$(command -v chmod)"
export REAL_CHMOD

cat > "${T}/bin/dockerd" <<'EOF'
#!/bin/bash
echo "dockerd-log-marker"
echo "dockerd-start $*" >> "${TRACE}"
trap 'echo "dockerd-stopped" >> "${TRACE}"; exit 0' TERM
while true; do sleep 0.2; done
EOF

cat > "${T}/bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >> "${TRACE}"
case "$1" in
    import) exit 0 ;;
    run) exit "${DOCKER_RUN_EXIT:-0}" ;;
esac
exit "${DOCKER_INFO_EXIT:-0}"
EOF

cat > "${T}/bin/setpriv" <<'EOF'
#!/bin/bash
echo "setpriv $*" >> "${TRACE}"
if [ -d "${RUNNER_USER_HOME:-/home/docker}/.ssh/deploy.d" ]; then
    echo "deploy.d-present-before-runner" >> "${TRACE}"
else
    echo "deploy.d-absent-before-runner" >> "${TRACE}"
fi
echo "runner-start" >> "${TRACE}"
trap 'echo "runner-deregistered" >> "${TRACE}"; exit 143' TERM
for _ in $(seq 1 "${RUNNER_STUB_TICKS:-2}"); do
    sleep 0.1
done
echo "runner-exit" >> "${TRACE}"
exit "${RUNNER_STUB_EXIT:-0}"
EOF

cat > "${T}/bin/chown" <<'EOF'
#!/bin/bash
echo "chown $*" >> "${TRACE}"
exit 0
EOF

cat > "${T}/bin/chmod" <<'EOF'
#!/bin/bash
# Record every chmod call, then delegate to the real binary only when every target path is inside
# the test sandbox. Host paths such as /var/run/docker.sock are recorded and left untouched.
echo "chmod $*" >> "${TRACE}"
mode=""
paths=()
for arg in "$@"; do
    case "$arg" in
        -*) continue ;;
    esac
    if [ -z "${mode}" ]; then
        mode="$arg"
    else
        paths+=("$arg")
    fi
done
for path in "${paths[@]}"; do
    case "$path" in
        "${TEST_SANDBOX}"/*) ;;
        *) exit 0 ;;
    esac
done
exec "${REAL_CHMOD:-/usr/bin/chmod}" "$@"
EOF

chmod +x "${T}/bin/"*

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Create a deploy-ssh source fixture. Modes are deliberately permissive (directories 0755, files
# 0644) so that a staging implementation must normalize them to 0700/0600 to pass.
make_deploy_source() {
    local dir="$1"
    local variant="$2"
    mkdir -p "${dir}/keys"
    case "${variant}" in
        full)
            printf 'Host prod\n  HostName prod.example\n' > "${dir}/config"
            printf 'prod.example ssh-ed25519 AAAAKEY\n' > "${dir}/known_hosts"
            printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' > "${dir}/keys/prod"
            ;;
        keys-only)
            printf 'prod.example ssh-ed25519 AAAAKEY\n' > "${dir}/known_hosts"
            printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' > "${dir}/keys/prod"
            ;;
        *)
            fail "unknown deploy source fixture variant: ${variant}"
            ;;
    esac
    chmod 755 "${dir}" "${dir}/keys"
    find "${dir}" -type f -exec chmod 644 {} +
}

# Create a runner home sandbox with an empty, owner-only ~/.ssh.
make_runner_home() {
    local home="$1"
    mkdir -p "${home}/.ssh"
    chmod 700 "${home}/.ssh"
}

# Run the entrypoint with deploy-ssh staging overrides and a ready daemon, recording the trace in
# $TRACE and combined output in $3. Returns the entrypoint's exit status.
run_staged_entry() {
    local src="$1"
    local home="$2"
    local out="$3"
    DOCKERD_LOG="${T}/dockerd-staging.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
        DEPLOY_SSH_SOURCE="${src}" RUNNER_USER_HOME="${home}" \
        PATH="${T}/bin:${PATH}" bash "${ENTRY}" >"${out}" 2>&1
}

# Ready daemon: start dockerd, drop privileges to run the runner, then stop the daemon.
export TRACE="${T}/trace-ready"
: > "${TRACE}"
DOCKERD_LOG="${T}/dockerd-ready.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" || fail "entrypoint exited non-zero with a ready daemon"
grep -q 'dockerd-start' "${TRACE}" || fail "dockerd was not started"
grep -q -- '--insecure-registry registry:5000' "${TRACE}" ||
    fail "the co-located registry must be marked insecure by default"
grep -q 'setpriv --reuid=docker --regid=docker --init-groups' "${TRACE}" ||
    fail "runner was not dropped to the docker user"
grep -q 'HOME=/home/docker' "${TRACE}" || fail "runner HOME was not set"
grep -q 'DOCKERD_PID=' "${TRACE}" && fail "daemon PID must not be needed by the runner"
grep -q 'dockerd-stopped' "${TRACE}" || fail "daemon was not stopped after the runner exited"
RUNNER_EXIT_LINE="$(grep -n 'runner-exit' "${TRACE}" | tail -1 | cut -d: -f1)"
STOP_LINE="$(grep -n 'dockerd-stopped' "${TRACE}" | tail -1 | cut -d: -f1)"
[ "${RUNNER_EXIT_LINE}" -lt "${STOP_LINE}" ] || fail "daemon stopped before the runner exited"
echo "PASS: entrypoint starts the daemon, runs the runner, and stops the daemon"

# Custom insecure registries are passed through to the daemon.
export TRACE="${T}/trace-insecure"
: > "${TRACE}"
DOCKERD_LOG="${T}/dockerd-insecure.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
    INSECURE_REGISTRIES="reg-a.example:5000 reg-b.example:5000" \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" || fail "entrypoint exited non-zero with custom registries"
grep -q -- '--insecure-registry reg-a.example:5000' "${TRACE}" || fail "first custom registry missing"
grep -q -- '--insecure-registry reg-b.example:5000' "${TRACE}" || fail "second custom registry missing"
grep -q -- '--insecure-registry registry:5000' "${TRACE}" && fail "default registry must be replaced by the override"
echo "PASS: custom insecure registries are passed to the daemon"

# When the default storage driver cannot run containers, restart with vfs on a fresh data root.
export TRACE="${T}/trace-fallback"
: > "${TRACE}"
mkdir -p "${T}/docker-data"
echo "stale" > "${T}/docker-data/stale"
DOCKERD_LOG="${T}/dockerd-fallback.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
    DOCKER_RUN_EXIT=125 DOCKER_DATA_ROOT="${T}/docker-data" \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" >"${T}/out-fallback" 2>&1 ||
    {
        cat "${T}/out-fallback" >&2
        fail "entrypoint should recover with the vfs fallback"
    }
[ "$(grep -c 'dockerd-start' "${TRACE}")" -eq 2 ] || fail "daemon must be restarted exactly once"
grep -q -- '--storage-driver vfs' "${TRACE}" || fail "fallback must use the vfs driver"
grep -qi 'falling back to vfs' "${T}/out-fallback" || fail "the fallback should be reported"
[ ! -e "${T}/docker-data/stale" ] || fail "the old data root must be cleared before the fallback"
echo "PASS: the entrypoint falls back to vfs when container mounts are unsupported"

# The runner's exit status is propagated by the supervisor.
export TRACE="${T}/trace-status"
: > "${TRACE}"
set +e
DOCKERD_LOG="${T}/dockerd-status.log" DOCKER_READY_ATTEMPTS=2 DOCKER_INFO_EXIT=0 RUNNER_STUB_EXIT=7 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 7 ] || fail "entrypoint should propagate the runner status, got ${CODE}"
echo "PASS: entrypoint propagates the runner exit status"

# SIGTERM: the entrypoint forwards the signal, the runner deregisters first, the daemon stops
# after the runner, and the entrypoint exits 143.
export TRACE="${T}/trace-signal"
: > "${TRACE}"
DOCKERD_LOG="${T}/dockerd-signal.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 RUNNER_STUB_TICKS=300 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" >/dev/null 2>&1 &
ENTRY_PID=$!
sleep 1
kill -TERM "${ENTRY_PID}"
set +e
wait "${ENTRY_PID}"
CODE=$?
set -e
[ "${CODE}" -eq 143 ] || fail "entrypoint should exit 143 on SIGTERM, got ${CODE}"
grep -q 'runner-deregistered' "${TRACE}" || fail "runner did not deregister on SIGTERM"
DEREG_LINE="$(grep -n 'runner-deregistered' "${TRACE}" | tail -1 | cut -d: -f1)"
STOP_LINE="$(grep -n 'dockerd-stopped' "${TRACE}" | tail -1 | cut -d: -f1)"
[ -n "${STOP_LINE}" ] || fail "daemon was not stopped on SIGTERM"
[ "${DEREG_LINE}" -lt "${STOP_LINE}" ] || fail "daemon stopped before the runner deregistered"
echo "PASS: SIGTERM deregisters the runner before stopping the daemon"

# Unavailable daemon: the entrypoint must exit non-zero, print the daemon log, and never start
# the runner.
export TRACE="${T}/trace-unready"
: > "${TRACE}"
set +e
DOCKERD_LOG="${T}/dockerd-unready.log" DOCKER_READY_ATTEMPTS=2 DOCKER_INFO_EXIT=1 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" >"${T}/out-unready" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "entrypoint should exit non-zero when the daemon never becomes ready"
grep -q 'setpriv' "${TRACE}" && fail "runner must not start without a working daemon"
grep -qi 'failed to start' "${T}/out-unready" || fail "failure message missing"
grep -q 'dockerd-log-marker' "${T}/out-unready" || fail "daemon log was not surfaced"
echo "PASS: entrypoint fails fast and surfaces the daemon log"

# --- deploy-ssh staging ----------------------------------------------------------------------
# ST-14: a deploy-ssh source mount is materialized into ~/.ssh/deploy.d with normalized modes and
# ownership, and a success line is printed.
export TRACE="${T}/trace-stage"
: > "${TRACE}"
STAGE_SRC="${T}/stage-src"
STAGE_HOME="${T}/stage-home"
make_deploy_source "${STAGE_SRC}" full
make_runner_home "${STAGE_HOME}"
run_staged_entry "${STAGE_SRC}" "${STAGE_HOME}" "${T}/out-stage" || {
    cat "${T}/out-stage" >&2
    fail "ST-14: entrypoint should exit zero while staging deploy SSH"
}
STAGE_TARGET="${STAGE_HOME}/.ssh/deploy.d"
[ -f "${STAGE_TARGET}/config" ] || fail "ST-14: staged config is missing"
[ -f "${STAGE_TARGET}/known_hosts" ] || fail "ST-14: staged known_hosts is missing"
[ -f "${STAGE_TARGET}/keys/prod" ] || fail "ST-14: staged keys/prod is missing"
[ "$(stat -c '%a' "${STAGE_TARGET}/config")" = "600" ] || fail "ST-14: config must be exactly 0600"
[ "$(stat -c '%a' "${STAGE_TARGET}/known_hosts")" = "600" ] ||
    fail "ST-14: known_hosts must be exactly 0600"
[ "$(stat -c '%a' "${STAGE_TARGET}/keys/prod")" = "600" ] ||
    fail "ST-14: keys/prod must be exactly 0600"
[ "$(stat -c '%a' "${STAGE_TARGET}")" = "700" ] || fail "ST-14: deploy.d must be exactly 0700"
[ "$(stat -c '%a' "${STAGE_TARGET}/keys")" = "700" ] ||
    fail "ST-14: the keys directory must be exactly 0700"
grep -q -- "chown -R docker:docker ${STAGE_TARGET}" "${TRACE}" ||
    fail "ST-14: staging must chown -R docker:docker the target"
grep -q "Deploy SSH staged from ${STAGE_SRC}" "${T}/out-stage" ||
    fail "ST-14: the staging success line is missing"
echo "PASS: ST-14 stages deploy SSH with normalized modes and ownership"

# ST-15: when the source contains a config file, ~/.ssh/config gets the Include line as its first
# line, and a second boot against the same home does not duplicate it.
export TRACE="${T}/trace-include"
: > "${TRACE}"
INCLUDE_SRC="${T}/include-src"
INCLUDE_HOME="${T}/include-home"
make_deploy_source "${INCLUDE_SRC}" full
make_runner_home "${INCLUDE_HOME}"
run_staged_entry "${INCLUDE_SRC}" "${INCLUDE_HOME}" "${T}/out-include-1" || {
    cat "${T}/out-include-1" >&2
    fail "ST-15: the first staging boot should exit zero"
}
INCLUDE_CONFIG="${INCLUDE_HOME}/.ssh/config"
[ -f "${INCLUDE_CONFIG}" ] || fail "ST-15: ~/.ssh/config was not created"
[ "$(head -n1 "${INCLUDE_CONFIG}")" = "Include ~/.ssh/deploy.d/config" ] ||
    fail "ST-15: the Include line must be the first line of ~/.ssh/config"
export TRACE="${T}/trace-include-2"
: > "${TRACE}"
run_staged_entry "${INCLUDE_SRC}" "${INCLUDE_HOME}" "${T}/out-include-2" || {
    cat "${T}/out-include-2" >&2
    fail "ST-15: the second staging boot should exit zero"
}
[ "$(grep -c 'Include ~/.ssh/deploy.d/config' "${INCLUDE_CONFIG}")" -eq 1 ] ||
    fail "ST-15: the Include line must appear exactly once after repeated boots"
echo "PASS: ST-15 prepends the deploy Include line exactly once across boots"

# ST-16: a keys-only source adds no Include line to ~/.ssh/config (negative).
export TRACE="${T}/trace-keys-only"
: > "${TRACE}"
KEYS_SRC="${T}/keys-only-src"
KEYS_HOME="${T}/keys-only-home"
make_deploy_source "${KEYS_SRC}" keys-only
make_runner_home "${KEYS_HOME}"
run_staged_entry "${KEYS_SRC}" "${KEYS_HOME}" "${T}/out-keys-only" || {
    cat "${T}/out-keys-only" >&2
    fail "ST-16: a keys-only source should exit zero"
}
if [ -f "${KEYS_HOME}/.ssh/config" ]; then
    grep -q 'Include ~/.ssh/deploy.d/config' "${KEYS_HOME}/.ssh/config" &&
        fail "ST-16: a keys-only source must not add the Include line"
fi
echo "PASS: ST-16 a keys-only source adds no Include line"

# ST-17: without a source directory staging is a no-op and the runner still starts (negative).
export TRACE="${T}/trace-no-source"
: > "${TRACE}"
NO_SRC_HOME="${T}/no-source-home"
make_runner_home "${NO_SRC_HOME}"
run_staged_entry "${T}/missing-deploy-source" "${NO_SRC_HOME}" "${T}/out-no-source" || {
    cat "${T}/out-no-source" >&2
    fail "ST-17: a missing source must not fail the entrypoint"
}
[ ! -e "${NO_SRC_HOME}/.ssh/deploy.d" ] ||
    fail "ST-17: no source directory must not create ~/.ssh/deploy.d"
grep -q 'setpriv' "${TRACE}" || fail "ST-17: the runner must still start without a source"
echo "PASS: ST-17 a missing deploy source is a no-op and the runner starts"

# ST-18: a staging failure warns, keeps the runner starting, and leaves the exit status unchanged.
export TRACE="${T}/trace-stage-fail"
: > "${TRACE}"
FAIL_SRC="${T}/stage-fail-src"
FAIL_HOME="${T}/stage-fail-home"
make_deploy_source "${FAIL_SRC}" full
make_runner_home "${FAIL_HOME}"
# An unwritable ~/.ssh makes removing/creating deploy.d fail.
chmod 500 "${FAIL_HOME}/.ssh"
set +e
run_staged_entry "${FAIL_SRC}" "${FAIL_HOME}" "${T}/out-stage-fail"
STAGE_FAIL_CODE=$?
set -e
chmod 700 "${FAIL_HOME}/.ssh"
[ "${STAGE_FAIL_CODE}" -eq 0 ] ||
    fail "ST-18: staging failure must not change the exit status, got ${STAGE_FAIL_CODE}"
grep -qi 'warning' "${T}/out-stage-fail" ||
    fail "ST-18: a staging failure must print a warning"
grep -q 'setpriv' "${TRACE}" || fail "ST-18: the runner must still start after a staging failure"
echo "PASS: ST-18 a staging failure warns and the runner still starts"

# ST-19: the target is a fresh copy each boot; a stale file from a previous boot is removed.
export TRACE="${T}/trace-stale"
: > "${TRACE}"
STALE_SRC="${T}/stale-src"
STALE_HOME="${T}/stale-home"
make_deploy_source "${STALE_SRC}" full
make_runner_home "${STALE_HOME}"
mkdir -p "${STALE_HOME}/.ssh/deploy.d"
printf 'stale\n' > "${STALE_HOME}/.ssh/deploy.d/stale"
run_staged_entry "${STALE_SRC}" "${STALE_HOME}" "${T}/out-stale" || {
    cat "${T}/out-stale" >&2
    fail "ST-19: staging over a stale target should exit zero"
}
[ ! -e "${STALE_HOME}/.ssh/deploy.d/stale" ] ||
    fail "ST-19: a stale file must not survive a fresh staged copy"
[ -f "${STALE_HOME}/.ssh/deploy.d/config" ] ||
    fail "ST-19: the fresh copy must still be staged"
echo "PASS: ST-19 staging replaces the target with a fresh copy"

echo "entrypoint spec tests: PASS"
