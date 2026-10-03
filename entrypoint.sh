#!/bin/bash
# Container entrypoint: start a private Docker daemon, run the Actions runner as the unprivileged
# "docker" user, and stop the daemon when the runner exits.
#
# The daemon lives inside this container, so Docker commands issued by jobs resolve file paths in
# the container's own filesystem instead of the host's. The entrypoint stays as PID 1 so it can
# stop the root-owned daemon after the unprivileged runner exits; it forwards INT/TERM so the
# runner deregisters before the daemon is stopped.
set -euo pipefail

# Overridable for tests; the defaults are the production paths.
DOCKERD_LOG="${DOCKERD_LOG:-/var/log/dockerd.log}"
DOCKER_READY_ATTEMPTS="${DOCKER_READY_ATTEMPTS:-60}"
RUNNER_START_SCRIPT="${RUNNER_START_SCRIPT:-/start.sh}"

# The co-located registry is plain HTTP, so the inner daemon must treat it as insecure unless a
# TLS endpoint replaces it (override INSECURE_REGISTRIES with a space-separated list, or empty).
INSECURE_REGISTRIES="${INSECURE_REGISTRIES-registry:5000}"
DOCKERD_ARGS=()
for registry in ${INSECURE_REGISTRIES}; do
    DOCKERD_ARGS+=(--insecure-registry "${registry}")
done

echo "Starting Docker daemon..."
dockerd "${DOCKERD_ARGS[@]}" >>"${DOCKERD_LOG}" 2>&1 &
DOCKERD_PID=$!

READY=0
for _ in $(seq 1 "${DOCKER_READY_ATTEMPTS}"); do
    if docker info >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [ "${READY}" -ne 1 ]; then
    echo "ERROR: Docker daemon failed to start" >&2
    cat "${DOCKERD_LOG}" >&2 || true
    kill "${DOCKERD_PID}" 2>/dev/null || true
    exit 1
fi

# The runner user needs access to the daemon socket.
chown root:docker /var/run/docker.sock 2>/dev/null || true
chmod 660 /var/run/docker.sock 2>/dev/null || true

# The stop helpers are invoked from the signal traps below, not from the main flow.
# shellcheck disable=SC2317
stop_runner() {
    if [ -n "${RUNNER_PID:-}" ]; then
        kill "${RUNNER_PID}" 2>/dev/null || true
        wait "${RUNNER_PID}" 2>/dev/null || true
    fi
}

# shellcheck disable=SC2317
stop_daemon() {
    kill "${DOCKERD_PID}" 2>/dev/null || true
    wait "${DOCKERD_PID}" 2>/dev/null || true
}

trap 'stop_runner; stop_daemon; exit 130' INT
trap 'stop_runner; stop_daemon; exit 143' TERM

setpriv --reuid=docker --regid=docker --init-groups \
    env HOME=/home/docker "${RUNNER_START_SCRIPT}" &
RUNNER_PID=$!

set +e
wait "${RUNNER_PID}"
RUNNER_STATUS=$?
set -e

stop_daemon
exit "${RUNNER_STATUS}"
