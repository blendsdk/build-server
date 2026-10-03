#!/bin/bash
# Fresh-host installer for the build server.
#
# On an empty Ubuntu host this script installs the prerequisites, clones or updates the
# repository, collects the required secrets, creates the host credential and SSH material,
# generates the registry htpasswd, builds the runner image, and starts the fleet.
#
# Usage:
#   curl -fsSL <raw bootstrap.sh url> | bash -s -- [--no-start] [--non-interactive]
#
# Environment overrides:
#   ACCESS_TOKEN            required GitHub token with runner admin on every org in orgs.conf
#   REGISTRY_USER           registry user (default: ci)
#   REGISTRY_PASS           registry password (generated and reported when absent)
#   REGISTRY_HTTP_SECRET    registry signing secret (generated when absent)
#   INSTALL_DIR             checkout location (default: $HOME/build-server)
#   REPO_URL                repository to clone (default: the project repository)
#   BRANCH                  branch to check out (default: v1-rebuild)
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/blendsdk/build-server.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/build-server}"
REGISTRY_USER="${REGISTRY_USER:-ci}"
START=1
NONINTERACTIVE=0

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [--no-start] [--non-interactive]

  --no-start         install and configure only; do not build or start the fleet
  --non-interactive  never prompt; required values must come from the environment
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-start) START=0 ;;
        --non-interactive | --yes) NONINTERACTIVE=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "bootstrap: unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

say() { printf 'bootstrap: %s\n' "$*"; }
die() {
    printf 'bootstrap: ERROR: %s\n' "$*" >&2
    exit 1
}

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || die "sudo is required to install packages"
    SUDO=(sudo)
fi

# Install a command's package when the command is missing.
install_pkg() {
    local cmd="$1" pkg="$2"
    command -v "${cmd}" >/dev/null 2>&1 && return 0
    say "installing ${pkg}"
    "${SUDO[@]}" apt-get update -y
    "${SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkg}"
}

random_hex() { od -An -tx1 -N "$1" /dev/urandom | tr -d ' \n'; }

# Read a value from the terminal when interactive; fail otherwise.
prompt_var() {
    local name="$1" text="$2" secret="${3:-}" value
    [ "${NONINTERACTIVE}" = "1" ] && die "${name} is required; set it in the environment"
    [ -r /dev/tty ] || die "${name} is required and no terminal is available; set it in the environment"
    if [ "${secret}" = "secret" ]; then
        IFS= read -r -s -p "${text}: " value </dev/tty
        printf '\n' >/dev/tty
    else
        IFS= read -r -p "${text}: " value </dev/tty
    fi
    printf -v "${name}" '%s' "${value}"
}

# --- prerequisites -----------------------------------------------------------
install_pkg git git
install_pkg curl curl
install_pkg jq jq
install_pkg shellcheck shellcheck
install_pkg ssh-keygen openssh-client
install_pkg htpasswd apache2-utils

if ! command -v docker >/dev/null 2>&1; then
    say "installing Docker"
    curl -fsSL https://get.docker.com | "${SUDO[@]}" bash
    "${SUDO[@]}" systemctl enable --now docker >/dev/null 2>&1 || true
fi

# --- secrets -----------------------------------------------------------------
if [ -z "${ACCESS_TOKEN:-}" ]; then
    prompt_var ACCESS_TOKEN "GitHub token with runner admin on every org in orgs.conf" secret
fi
[ -n "${ACCESS_TOKEN}" ] || die "ACCESS_TOKEN must not be empty"

if [ -z "${REGISTRY_PASS:-}" ]; then
    if [ "${NONINTERACTIVE}" = "1" ] || [ ! -r /dev/tty ]; then
        REGISTRY_PASS="$(random_hex 16)"
        GENERATED_REGISTRY_PASS=1
    else
        prompt_var REGISTRY_PASS "Registry password for user ${REGISTRY_USER}" secret
    fi
fi
[ -n "${REGISTRY_PASS}" ] || die "REGISTRY_PASS must not be empty"
REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET:-$(random_hex 32)}"

# --- checkout ------------------------------------------------------------------
if [ -d "${INSTALL_DIR}/.git" ]; then
    say "updating ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" -c "http.extraHeader=AUTHORIZATION: bearer ${ACCESS_TOKEN}" \
        fetch origin "${BRANCH}"
    git -C "${INSTALL_DIR}" checkout "${BRANCH}"
    git -C "${INSTALL_DIR}" -c "http.extraHeader=AUTHORIZATION: bearer ${ACCESS_TOKEN}" \
        merge --ff-only "origin/${BRANCH}"
else
    say "cloning ${REPO_URL} (${BRANCH}) into ${INSTALL_DIR}"
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git -c "http.extraHeader=AUTHORIZATION: bearer ${ACCESS_TOKEN}" \
        clone --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" remote set-url origin "${REPO_URL}"
fi
cd "${INSTALL_DIR}"

# --- host configuration ---------------------------------------------------------
if [ ! -f .env ]; then
    umask 077
    printf 'ACCESS_TOKEN=%s\nREGISTRY_HTTP_SECRET=%s\n' \
        "${ACCESS_TOKEN}" "${REGISTRY_HTTP_SECRET}" >.env
    chmod 600 .env
    say "wrote .env"
else
    say ".env already exists; leaving it untouched"
fi

for file in .npmrc .yarnrc .bunfig.toml; do
    if [ ! -e "${file}" ]; then
        : >"${file}"
        say "created empty ${file} (add your package registry settings)"
    fi
done
if [ ! -e config.json ]; then
    printf '{}\n' >config.json
    say "created empty config.json (add your Docker registry auth)"
fi

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh" 2>/dev/null || true
if [ ! -f "${HOME}/.ssh/id_rsa" ]; then
    ssh-keygen -t ed25519 -N "" -f "${HOME}/.ssh/id_rsa" -C "build-server@$(hostname)" >/dev/null
    say "generated a deploy key: ${HOME}/.ssh/id_rsa (add the .pub where needed)"
fi
if [ ! -f "${HOME}/.ssh/id_rsa.pub" ]; then
    ssh-keygen -y -f "${HOME}/.ssh/id_rsa" >"${HOME}/.ssh/id_rsa.pub"
fi
if [ ! -f "${HOME}/.ssh/config" ]; then
    : >"${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/config"
fi

mkdir -p registry/auth registry/data
if [ ! -s registry/auth/registry.password ]; then
    htpasswd -Bbn "${REGISTRY_USER}" "${REGISTRY_PASS}" >registry/auth/registry.password
    chmod 600 registry/auth/registry.password
    say "wrote registry/auth/registry.password for user ${REGISTRY_USER}"
fi

if [ "${GENERATED_REGISTRY_PASS:-0}" = "1" ]; then
    say "generated registry password (save it now): user=${REGISTRY_USER} password=${REGISTRY_PASS}"
fi

# --- start ----------------------------------------------------------------------
# Docker group membership only applies to new shell sessions; try `sg` before giving up.
run_fleet() {
    if docker info >/dev/null 2>&1; then
        ./fleet.sh "$@"
    elif command -v sg >/dev/null 2>&1 && sg docker -c "docker info" >/dev/null 2>&1; then
        local quoted="./fleet.sh" arg
        for arg in "$@"; do
            quoted+=" $(printf '%q' "${arg}")"
        done
        sg docker -c "${quoted}"
    else
        return 1
    fi
}

if [ "${START}" = "0" ]; then
    say "setup complete. Start the fleet with: cd ${INSTALL_DIR} && ./fleet.sh build && ./fleet.sh up"
    exit 0
fi

if ! run_fleet build || ! run_fleet up; then
    say "Docker is installed but not accessible in this shell."
    say "Log out and back in, then run: cd ${INSTALL_DIR} && ./fleet.sh build && ./fleet.sh up"
    exit 0
fi

say "fleet started. Check it with: cd ${INSTALL_DIR} && ./fleet.sh status"
