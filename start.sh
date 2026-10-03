#!/bin/bash
# Register this container as a persistent GitHub Actions runner, run it, and deregister on shutdown.
#
# The runner is registered once per container lifetime with --replace, so a container that is
# restarted reuses its registration name without leaving duplicates behind.
set -euo pipefail

# shellcheck source=/dev/null
source ~/.profile

: "${ORGANIZATION:?ORGANIZATION is required}"
: "${ACCESS_TOKEN:?ACCESS_TOKEN is required}"

# GitHub.com defaults; the fleet generator sets these for GitHub Enterprise organizations.
GITHUB_URL="${GITHUB_URL:-https://github.com/${ORGANIZATION}}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# Domain for the runner's git identity email; override for your own domain.
RUNNER_EMAIL_DOMAIN="${RUNNER_EMAIL_DOMAIN:-users.noreply.github.com}"

LABEL="${ORGANIZATION}_${HOSTNAME}"

git config --global user.email "${LABEL}@${RUNNER_EMAIL_DOMAIN}"
git config --global user.name "${LABEL}"

cd "${RUNNER_HOME:-/home/docker/actions-runner}" || exit 1

# Registration tokens are short-lived, so fetch a fresh one for this container lifetime. The
# "|| true" keeps a malformed API response from aborting before the named error below is printed.
REG_TOKEN="$(curl -sX POST \
    -H "Authorization: token ${ACCESS_TOKEN}" \
    "${GITHUB_API_URL}/orgs/${ORGANIZATION}/actions/runners/registration-token" | jq .token --raw-output || true)"

if [ -z "${REG_TOKEN}" ] || [ "${REG_TOKEN}" = "null" ]; then
    echo "ERROR: failed to obtain a registration token for ${ORGANIZATION}" >&2
    exit 1
fi

# A previous registration with this name may still exist; remove it before registering again.
./config.sh remove --unattended --token "${REG_TOKEN}" --name "${LABEL}" || true

cleanup() {
    echo "Removing runner ${LABEL}..."
    ./config.sh remove --unattended --token "${REG_TOKEN}" --name "${LABEL}" || true
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

nvm install --lts

# Authenticate the inner daemon to the co-located registry so jobs can push images without an
# extra login step. Credentials come from the generated service environment.
if [ -n "${REGISTRY_ADDR:-}" ] && [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASS:-}" ]; then
    if echo "${REGISTRY_PASS}" | docker login "${REGISTRY_ADDR}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1; then
        echo "Logged in to ${REGISTRY_ADDR}"
    else
        echo "WARNING: could not log in to ${REGISTRY_ADDR}" >&2
    fi
fi

./config.sh --replace --unattended --url "${GITHUB_URL}" \
    --token "${REG_TOKEN}" --name "${LABEL}"

./run.sh &
wait $!
