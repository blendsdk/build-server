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

cat > "${T}/bin/dockerd" <<'EOF'
#!/bin/bash
echo "dockerd-log-marker"
echo "dockerd-start" >> "${TRACE}"
trap 'echo "dockerd-stopped" >> "${TRACE}"; exit 0' TERM
while true; do sleep 0.2; done
EOF

cat > "${T}/bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >> "${TRACE}"
exit "${DOCKER_INFO_EXIT:-0}"
EOF

cat > "${T}/bin/setpriv" <<'EOF'
#!/bin/bash
echo "setpriv $*" >> "${TRACE}"
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
exit 0
EOF

cat > "${T}/bin/chmod" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "${T}/bin/"*

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Ready daemon: start dockerd, drop privileges to run the runner, then stop the daemon.
export TRACE="${T}/trace-ready"
: > "${TRACE}"
DOCKERD_LOG="${T}/dockerd-ready.log" DOCKER_READY_ATTEMPTS=3 DOCKER_INFO_EXIT=0 \
    PATH="${T}/bin:${PATH}" bash "${ENTRY}" || fail "entrypoint exited non-zero with a ready daemon"
grep -q 'dockerd-start' "${TRACE}" || fail "dockerd was not started"
grep -q 'setpriv --reuid=docker --regid=docker --init-groups' "${TRACE}" ||
    fail "runner was not dropped to the docker user"
grep -q 'HOME=/home/docker' "${TRACE}" || fail "runner HOME was not set"
grep -q 'DOCKERD_PID=' "${TRACE}" && fail "daemon PID must not be needed by the runner"
grep -q 'dockerd-stopped' "${TRACE}" || fail "daemon was not stopped after the runner exited"
RUNNER_EXIT_LINE="$(grep -n 'runner-exit' "${TRACE}" | tail -1 | cut -d: -f1)"
STOP_LINE="$(grep -n 'dockerd-stopped' "${TRACE}" | tail -1 | cut -d: -f1)"
[ "${RUNNER_EXIT_LINE}" -lt "${STOP_LINE}" ] || fail "daemon stopped before the runner exited"
echo "PASS: entrypoint starts the daemon, runs the runner, and stops the daemon"

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

echo "entrypoint spec tests: PASS"
