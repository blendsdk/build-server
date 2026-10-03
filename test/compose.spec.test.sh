#!/bin/bash
# Specification tests for the generated runner fleet compose model.
#
# Generates the runner services from the committed orgs.conf, merges them with the static registry
# base, normalizes the result with `docker compose config`, and asserts the required properties per
# service so a mutation cannot be masked by a file-global count.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[ -f "${ROOT}/docker-compose.yml" ] || fail "docker-compose.yml (registry base) is missing"
[ -f "${ROOT}/orgs.conf" ] || fail "orgs.conf is missing"

ACCESS_TOKEN=dummy bash fleet.sh generate >"${T}/generate.out" 2>&1 ||
    {
        cat "${T}/generate.out" >&2
        fail "fleet.sh generate failed"
    }
ACCESS_TOKEN=dummy-token REGISTRY_HTTP_SECRET=dummy-secret \
    docker compose -f docker-compose.yml -f docker-compose.generated.yml config --format json \
    >"${T}/model.json" 2>"${T}/config.err" ||
    {
        cat "${T}/config.err" >&2
        fail "merged compose model is invalid"
    }
MODEL="${T}/model.json"
RUNNER_FILTER='[.services | to_entries[] | select(.value.image | startswith("runner-image"))]'

# The model is exactly the registry plus one runner service per organization.
ORG_COUNT="$(awk '/^[A-Za-z0-9._-]+/ { count++ } END { print count + 0 }' orgs.conf)"
EXPECTED_SERVICES="$(
    { echo "registry"; awk '/^[A-Za-z0-9._-]+/ { slug=tolower($1); gsub(/[^a-z0-9]/, "", slug); print slug }' orgs.conf; } | sort | paste -sd, -
)"
SERVICES="$(jq -r '.services | keys | sort | join(",")' "${MODEL}")"
[ "${SERVICES}" = "${EXPECTED_SERVICES}" ] || fail "unexpected service set: ${SERVICES}"

# One privileged runner per organization; no other service is privileged.
RUNNER_COUNT="$(jq "${RUNNER_FILTER} | length" "${MODEL}")"
[ "${RUNNER_COUNT}" -eq "${ORG_COUNT}" ] || fail "expected ${ORG_COUNT} runner services, got ${RUNNER_COUNT}"
UNPRIVILEGED="$(jq "${RUNNER_FILTER} | map(select(.value.privileged != true)) | length" "${MODEL}")"
[ "${UNPRIVILEGED}" -eq 0 ] || fail "every runner service must be privileged"
OTHER_PRIVILEGED="$(jq '[.services | to_entries[] | select((.value.image | startswith("runner-image")) | not) | select(.value.privileged == true)] | length' "${MODEL}")"
[ "${OTHER_PRIVILEGED}" -eq 0 ] || fail "only runner services may be privileged"

# Runner images are built locally; Compose must never pull them from a registry.
PULL_POLICY="$(jq '[.services | to_entries[] | select(.value.image | startswith("runner-image")) | select(.value.pull_policy != "never")] | length' "${MODEL}")"
[ "${PULL_POLICY}" -eq 0 ] || fail "runner services must declare pull_policy: never"

# Organization to hostname mapping is slug-derived and matches orgs.conf.
EXPECTED_MAPPING="$(
    awk '/^[A-Za-z0-9._-]+/ { slug=tolower($1); gsub(/[^a-z0-9]/, "", slug); print $1 "=" slug "_runner_1" }' orgs.conf | sort
)"
MAPPING="$(jq -r "${RUNNER_FILTER} | map(\"\(.value.environment.ORGANIZATION)=\(.value.hostname)\") | sort | join(\"\n\")" "${MODEL}")"
[ "${MAPPING}" = "${EXPECTED_MAPPING}" ] || fail "organization mapping mismatch: ${MAPPING}"

# Containers must derive their names from the Compose project; pinning a global container name
# would make two installations on one host collide.
NAMED="$(jq '[.services[] | select(.container_name != null)] | length' "${MODEL}")"
[ "${NAMED}" -eq 0 ] || fail "no service may pin a global container name"

# No host Docker socket and no host network mode.
jq -e '[.. | strings | select(test("docker.sock"))] | length == 0' "${MODEL}" >/dev/null ||
    fail "host Docker socket must not be mounted"
jq -e '[.services[] | select(.network_mode == "host")] | length == 0' "${MODEL}" >/dev/null ||
    fail "host network mode must not be used"

# The registry secret is resolved from the environment and reaches only the registry.
REG_SECRET="$(jq -r '.services.registry.environment.REGISTRY_HTTP_SECRET' "${MODEL}")"
[ "${REG_SECRET}" = "dummy-secret" ] || fail "registry secret was not resolved from the environment"
OTHER_SECRETS="$(jq '[.services | to_entries[] | select(.key != "registry") | select(.value.environment.REGISTRY_HTTP_SECRET != null)] | length' "${MODEL}")"
[ "${OTHER_SECRETS}" -eq 0 ] || fail "only the registry service may receive REGISTRY_HTTP_SECRET"

# Runner services receive the co-located registry address and credentials for docker push.
REGISTRY_USER=dummy-user REGISTRY_PASS=dummy-pass REGISTRY_ADDR=registry:5000 \
    DOCKERD_STORAGE_DRIVER=vfs \
    ACCESS_TOKEN=dummy-token REGISTRY_HTTP_SECRET=dummy-secret \
    docker compose -f docker-compose.yml -f docker-compose.generated.yml config --format json \
    >"${T}/model-registry.json" 2>"${T}/config-registry.err" ||
    {
        cat "${T}/config-registry.err" >&2
        fail "compose model with registry credentials is invalid"
    }
REGISTRY_MODEL="${T}/model-registry.json"
[ "$(jq -r '.services.acmetools.environment.REGISTRY_ADDR' "${REGISTRY_MODEL}")" = "registry:5000" ] ||
    fail "REGISTRY_ADDR was not injected into runner services"
[ "$(jq -r '.services.acmetools.environment.REGISTRY_USER' "${REGISTRY_MODEL}")" = "dummy-user" ] ||
    fail "REGISTRY_USER was not injected into runner services"
[ "$(jq -r '.services.acmetools.environment.REGISTRY_PASS' "${REGISTRY_MODEL}")" = "dummy-pass" ] ||
    fail "REGISTRY_PASS was not injected into runner services"
[ "$(jq -r '.services.acmetools.environment.INSECURE_REGISTRIES' "${REGISTRY_MODEL}")" = "registry:5000" ] ||
    fail "INSECURE_REGISTRIES default missing from runner services"
[ "$(jq -r '.services.acmetools.environment.DOCKERD_STORAGE_DRIVER' "${REGISTRY_MODEL}")" = "vfs" ] ||
    fail "DOCKERD_STORAGE_DRIVER override was not injected"

# The registry host port is configurable; runners use registry:5000 regardless.
DEFAULT_PORT="$(jq -r '.services.registry.ports[0].published' "${MODEL}")"
[ "${DEFAULT_PORT}" = "5000" ] || fail "default registry host port must be 5000"
REGISTRY_PORT=5050 ACCESS_TOKEN=dummy-token REGISTRY_HTTP_SECRET=dummy-secret \
    docker compose -f docker-compose.yml -f docker-compose.generated.yml config --format json \
    >"${T}/model-port.json" 2>"${T}/config-port.err" ||
    {
        cat "${T}/config-port.err" >&2
        fail "compose model with a REGISTRY_PORT override is invalid"
    }
CUSTOM_PORT="$(jq -r '.services.registry.ports[0].published' "${T}/model-port.json")"
[ "${CUSTOM_PORT}" = "5050" ] || fail "REGISTRY_PORT override was not applied (got ${CUSTOM_PORT})"

# Exactly one organization opts into the host /tmp mount.
BUILD_TEMP_COUNT="$(jq '[.services | to_entries[] | select([.value.volumes[]?.target] | index("/build-temp"))] | length' "${MODEL}")"
[ "${BUILD_TEMP_COUNT}" -eq 1 ] || fail "exactly one service must mount /build-temp, got ${BUILD_TEMP_COUNT}"

echo "compose spec tests: PASS"
