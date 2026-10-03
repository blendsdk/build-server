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
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
RUNNER_START_SCRIPT="${RUNNER_START_SCRIPT:-/start.sh}"
DOCKERD_STORAGE_DRIVER="${DOCKERD_STORAGE_DRIVER:-}"

# The co-located registry is plain HTTP, so the inner daemon must treat it as insecure unless a
# TLS endpoint replaces it (override INSECURE_REGISTRIES with a space-separated list, or empty).
INSECURE_REGISTRIES="${INSECURE_REGISTRIES-registry:5000}"
DOCKERD_ARGS=()
for registry in ${INSECURE_REGISTRIES}; do
    DOCKERD_ARGS+=(--insecure-registry "${registry}")
done

# Start dockerd in the background, honouring a pinned storage driver when configured.
start_dockerd() {
    local driver_args=()
    if [ -n "${DOCKERD_STORAGE_DRIVER}" ]; then
        driver_args=(--storage-driver "${DOCKERD_STORAGE_DRIVER}")
    fi
    dockerd "${DOCKERD_ARGS[@]}" "${driver_args[@]}" >>"${DOCKERD_LOG}" 2>&1 &
    DOCKERD_PID=$!
}

# Wait until the daemon answers `docker info`.
wait_for_dockerd() {
    for _ in $(seq 1 "${DOCKER_READY_ATTEMPTS}"); do
        docker info >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# True when the daemon can mount a container filesystem. An empty imported image has no /bin/true,
# so a successful mount fails with 127 (exec missing) while a failed mount returns 125.
storage_mounts_work() {
    local image="build-server/storage-selftest:latest" dir tar code
    dir="$(mktemp -d)"
    tar="$(mktemp)"
    tar -C "${dir}" -cf "${tar}" .
    docker import "${tar}" "${image}" >/dev/null 2>&1 || true
    set +e
    docker run --rm "${image}" /bin/true >/dev/null 2>&1
    code=$?
    set -e
    rm -rf "${dir}" "${tar}"
    [ "${code}" -eq 0 ] || [ "${code}" -eq 127 ]
}

echo "Starting Docker daemon..."
start_dockerd
if ! wait_for_dockerd; then
    echo "ERROR: Docker daemon failed to start" >&2
    cat "${DOCKERD_LOG}" >&2 || true
    kill "${DOCKERD_PID}" 2>/dev/null || true
    exit 1
fi

# Some hosts cannot nest the default storage driver inside the runner container. Detect that at
# boot and fall back to vfs (slower, but always works) unless the operator pinned a driver.
if [ -z "${DOCKERD_STORAGE_DRIVER}" ] && ! storage_mounts_work; then
    echo "WARNING: the default storage driver cannot run containers here; falling back to vfs" >&2
    kill "${DOCKERD_PID}" 2>/dev/null || true
    wait "${DOCKERD_PID}" 2>/dev/null || true
    rm -rf "${DOCKER_DATA_ROOT}"
    DOCKERD_STORAGE_DRIVER=vfs
    start_dockerd
    if ! wait_for_dockerd; then
        echo "ERROR: Docker daemon failed to start with the vfs storage driver" >&2
        cat "${DOCKERD_LOG}" >&2 || true
        kill "${DOCKERD_PID}" 2>/dev/null || true
        exit 1
    fi
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
