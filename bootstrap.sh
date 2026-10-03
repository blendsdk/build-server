#!/bin/bash
# Fresh-host installer for the build server.
#
# On an empty Ubuntu host this script installs the prerequisites, clones or updates the
# repository, collects the required secrets, creates the host credential and SSH material,
# generates the registry htpasswd, builds the runner image, and starts the fleet.
#
# Usage:
#   curl -fsSL <raw bootstrap.sh url> | bash -s -- [--no-start] [--non-interactive]
#   ... [--ssh | --generate-ssh-key | --token] [--orgs "OrgA OrgB"] [--keep-orgs]
#
# Organizations:
#   bootstrap asks for the organizations to serve and verifies each by minting a registration
#   token (the same permission the fleet needs). Use --orgs "OrgA OrgB" for unattended installs,
#   or --keep-orgs to leave an existing orgs.conf untouched.
#
# Repository access (default --token):
#   --token              clone over HTTPS using ACCESS_TOKEN (default)
#   --ssh                clone over SSH using an existing key (SSH_KEY, default ~/.ssh/id_rsa)
#   --generate-ssh-key   generate SSH_KEY when missing, install the public key on GitHub
#                        (the token needs write:public_key), then clone over SSH
#
# Environment overrides:
#   ACCESS_TOKEN            required: a token that can manage self-hosted runners for every
#                           organization in orgs.conf. Recommended: a classic PAT with the
#                           admin:org scope (Settings > Developer settings > Personal access
#                           tokens > Tokens (classic)); authorize it for each org that uses
#                           SAML SSO. A fine-grained token ("Self-hosted runners: Read and
#                           write") works for a single organization only.
#                           Guide: https://blendsdk.github.io/build-server/guide/github-token
#   REGISTRY_USER           registry user (default: ci)
#   REGISTRY_PASS           registry password (generated and reported when absent)
#   REGISTRY_HTTP_SECRET    registry signing secret (generated when absent)
#   INSTALL_DIR             checkout location (default: $HOME/build-server)
#   REPO_URL                repository to clone (default: the project repository)
#   REPO_SSH_URL            explicit SSH URL when it differs from the REPO_URL derivation
#   BRANCH                  branch to check out (default: main)
#   GIT_AUTH                token (default) or ssh; flags win over the variable
#   SSH_KEY                 SSH key used for the checkout (default: $HOME/.ssh/id_rsa)
#   ORGS                    space- or comma-separated organizations for the fleet
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/blendsdk/build-server.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/build-server}"
REGISTRY_USER="${REGISTRY_USER:-ci}"
GIT_AUTH="${GIT_AUTH:-token}"
GENERATE_SSH_KEY=0
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
REPO_SSH_URL="${REPO_SSH_URL:-}"
ORGS="${ORGS:-}"
KEEP_ORGS=0
START=1
NONINTERACTIVE=0

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [--no-start] [--non-interactive] [--token | --ssh | --generate-ssh-key]
                    [--orgs "OrgA OrgB"] [--keep-orgs]

  --no-start         install and configure only; do not build or start the fleet
  --non-interactive  never prompt; required values must come from the environment
  --token            clone over HTTPS using ACCESS_TOKEN (default)
  --ssh              clone over SSH using an existing key (SSH_KEY)
  --generate-ssh-key generate SSH_KEY when missing, install the public key on GitHub,
                     then clone over SSH
  --orgs "A B"       organizations to serve; each is verified against GitHub
  --keep-orgs        keep the existing orgs.conf and skip the organization prompt
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-start) START=0 ;;
        --non-interactive | --yes) NONINTERACTIVE=1 ;;
        --token) GIT_AUTH=token ;;
        --ssh) GIT_AUTH=ssh ;;
        --generate-ssh-key)
            GIT_AUTH=ssh
            GENERATE_SSH_KEY=1
            ;;
        --orgs)
            [ "$#" -ge 2 ] || die "--orgs requires a value"
            ORGS="$2"
            shift
            ;;
        --keep-orgs) KEEP_ORGS=1 ;;
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

# Convert an HTTPS repository URL to its SSH form.
to_ssh_url() {
    local url="$1" rest host path
    case "${url}" in
        git@*) printf '%s' "${url}" ;;
        https://*)
            rest="${url#https://}"
            rest="${rest%.git}"
            host="${rest%%/*}"
            path="${rest#*/}"
            printf 'git@%s:%s.git' "${host}" "${path}"
            ;;
        *) printf '%s' "${url}" ;;
    esac
}

# API base for the checkout host (github.com or a GitHub Enterprise Server).
api_base_for() {
    local url="$1" rest host
    rest="${url#https://}"
    host="${rest%%/*}"
    if [ "${host}" = "github.com" ]; then
        printf 'https://api.github.com'
    else
        printf 'https://%s/api/v3' "${host}"
    fi
}

# Ensure SSH_KEY exists, generating it when --generate-ssh-key was requested.
ensure_ssh_key() {
    local dir
    dir="$(dirname "${SSH_KEY}")"
    mkdir -p "${dir}"
    chmod 700 "${dir}" 2>/dev/null || true
    if [ ! -f "${SSH_KEY}" ]; then
        [ "${GENERATE_SSH_KEY}" = "1" ] ||
            die "${SSH_KEY} not found; create a key or re-run with --generate-ssh-key"
        say "generating SSH key ${SSH_KEY}"
        ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "build-server@$(hostname)" >/dev/null
    fi
    [ -f "${SSH_KEY}.pub" ] || ssh-keygen -y -f "${SSH_KEY}" >"${SSH_KEY}.pub"
    chmod 600 "${SSH_KEY}"
}

# Install the generated public key on GitHub so the SSH clone can authenticate.
register_ssh_key() {
    local api key title
    api="$(api_base_for "${REPO_URL}")"
    key="$(cat "${SSH_KEY}.pub")"
    title="build-server $(hostname)"
    if curl -fsS -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${api}/user/keys" \
        --data "$(jq -n --arg t "${title}" --arg k "${key}" '{title: $t, key: $k}')" >/dev/null 2>&1; then
        say "installed the SSH public key on GitHub as '${title}'"
    else
        say "could not install the key automatically (the token needs write:public_key)."
        say "Add this public key at https://github.com/settings/keys and re-run:"
        say "  ${key}"
        die "the SSH key is not installed on GitHub"
    fi
}

# Trust the checkout host before the first SSH connection.
prepare_known_hosts() {
    local rest host
    rest="${REPO_URL#https://}"
    host="${rest%%/*}"
    mkdir -p "${HOME}/.ssh"
    if ! grep -qs "${host}" "${HOME}/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan "${host}" >>"${HOME}/.ssh/known_hosts" 2>/dev/null || true
    fi
}

# Verify that the token can manage runners for an organization by minting a registration token
# (the exact permission the fleet needs).
validate_org() {
    local org="$1" response code
    response="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/orgs/${org}/actions/runners/registration-token" || true)"
    code="${response##*$'\n'}"
    case "${code}" in
        201) return 0 ;;
        401) die "ACCESS_TOKEN is invalid or expired (while verifying '${org}')" ;;
        403) die "the token lacks runner admin for '${org}' (classic: admin:org)" ;;
        404) die "organization '${org}' not found or not visible to the token" ;;
        *) die "could not verify organization '${org}' (HTTP ${code})" ;;
    esac
}

# Ask for (or accept) the organizations and write orgs.conf after validating each one.
configure_orgs() {
    local current org
    if [ "${KEEP_ORGS}" = "1" ]; then
        say "keeping the existing orgs.conf"
        return
    fi

    if [ -z "${ORGS}" ]; then
        if [ "${NONINTERACTIVE}" = "1" ] || [ ! -r /dev/tty ]; then
            die "ORGS is required (space-separated organization names), or pass --keep-orgs"
        fi
        current="$(awk '/^[A-Za-z0-9._-]+/ { printf "%s ", $1 }' orgs.conf 2>/dev/null || true)"
        prompt_var ORGS "Organizations for this build server (space separated; current: ${current:-none})"
        if [ -z "${ORGS}" ]; then
            if grep -q 'Example runner fleet' orgs.conf 2>/dev/null; then
                die "enter at least one organization"
            fi
            say "keeping the existing orgs.conf"
            return
        fi
    fi

    ORGS="${ORGS//,/ }"
    for org in ${ORGS}; do
        [[ "${org}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid organization name '${org}'"
        validate_org "${org}"
        say "verified organization ${org}"
    done

    {
        echo "# Runner fleet — edit and run ./fleet.sh up to apply changes."
        echo "# Format: <name> [url=...] [context=...] [build_temp=1]"
        for org in ${ORGS}; do
            echo "${org}"
        done
    } >orgs.conf
    say "wrote orgs.conf with: ${ORGS}"
}

# True when something is already listening on the given TCP port.
port_in_use() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
}

# Host port for the registry: the configured one when free, otherwise the first free port in
# 5000-5050. An explicitly configured busy port is an error.
choose_registry_port() {
    local port="${REGISTRY_PORT:-5000}" candidate
    if ! port_in_use "${port}"; then
        printf '%s' "${port}"
        return
    fi
    if [ -n "${REGISTRY_PORT:-}" ]; then
        die "REGISTRY_PORT=${REGISTRY_PORT} is already in use"
    fi
    for candidate in $(seq 5001 5050); do
        if ! port_in_use "${candidate}"; then
            say "host port 5000 is busy; using ${candidate} for the registry" >&2
            printf '%s' "${candidate}"
            return
        fi
    done
    die "no free registry port found in 5000-5050"
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
    prompt_var ACCESS_TOKEN "GitHub token with runner admin on every org in orgs.conf (classic PAT with admin:org - see docs/guide/github-token)" secret
fi
[ -n "${ACCESS_TOKEN}" ] || die "ACCESS_TOKEN must not be empty"

if [ -z "${REGISTRY_PASS:-}" ]; then
    REGISTRY_PASS_EXPLICIT=0
    if [ "${NONINTERACTIVE}" = "1" ] || [ ! -r /dev/tty ]; then
        REGISTRY_PASS="$(random_hex 16)"
        GENERATED_REGISTRY_PASS=1
    else
        prompt_var REGISTRY_PASS "Registry password for user ${REGISTRY_USER}" secret
    fi
else
    REGISTRY_PASS_EXPLICIT=1
fi
[ -n "${REGISTRY_PASS}" ] || die "REGISTRY_PASS must not be empty"
REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET:-$(random_hex 32)}"

# --- checkout ------------------------------------------------------------------
if [ "${GIT_AUTH}" = "ssh" ]; then
    ensure_ssh_key
    [ "${GENERATE_SSH_KEY}" = "0" ] || register_ssh_key
    prepare_known_hosts
    ssh_url="${REPO_SSH_URL:-$(to_ssh_url "${REPO_URL}")}"
    if [ -d "${INSTALL_DIR}/.git" ]; then
        say "updating ${INSTALL_DIR} over SSH"
        git -C "${INSTALL_DIR}" remote set-url origin "${ssh_url}"
        git -C "${INSTALL_DIR}" fetch origin "${BRANCH}"
        git -C "${INSTALL_DIR}" checkout "${BRANCH}"
        git -C "${INSTALL_DIR}" merge --ff-only "origin/${BRANCH}"
    else
        say "cloning ${ssh_url} (${BRANCH}) into ${INSTALL_DIR}"
        mkdir -p "$(dirname "${INSTALL_DIR}")"
        git clone --branch "${BRANCH}" "${ssh_url}" "${INSTALL_DIR}"
    fi
else
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
fi
cd "${INSTALL_DIR}"

# --- organizations -----------------------------------------------------------------
configure_orgs

# --- host configuration ---------------------------------------------------------
# Whether this run knows the password that matches the existing htpasswd file.
if [ -s registry/auth/registry.password ] && [ "${REGISTRY_PASS_EXPLICIT}" = "0" ]; then
    REGISTRY_PASS_KNOWN=0
else
    REGISTRY_PASS_KNOWN=1
fi

if [ ! -f .env ]; then
    REGISTRY_PORT_SELECTED="$(choose_registry_port)"
    umask 077
    printf 'ACCESS_TOKEN=%s\nREGISTRY_HTTP_SECRET=%s\nREGISTRY_PORT=%s\nREGISTRY_USER=%s\nREGISTRY_PASS=%s\n' \
        "${ACCESS_TOKEN}" "${REGISTRY_HTTP_SECRET}" "${REGISTRY_PORT_SELECTED}" \
        "${REGISTRY_USER}" "${REGISTRY_PASS}" >.env
    chmod 600 .env
    say "wrote .env"
else
    say ".env already exists; leaving it untouched"
    if ! grep -q '^REGISTRY_PORT=' .env; then
        REGISTRY_PORT_SELECTED="$(choose_registry_port)"
        printf 'REGISTRY_PORT=%s\n' "${REGISTRY_PORT_SELECTED}" >>.env
        say "added REGISTRY_PORT=${REGISTRY_PORT_SELECTED} to .env"
    fi
    if [ "${REGISTRY_PASS_KNOWN}" = "1" ]; then
        if ! grep -q '^REGISTRY_USER=' .env; then
            printf 'REGISTRY_USER=%s\n' "${REGISTRY_USER}" >>.env
            say "added REGISTRY_USER to .env"
        fi
        if ! grep -q '^REGISTRY_PASS=' .env; then
            printf 'REGISTRY_PASS=%s\n' "${REGISTRY_PASS}" >>.env
            say "added REGISTRY_PASS to .env"
        fi
    else
        say "the existing registry password is unknown to this run; set REGISTRY_USER/REGISTRY_PASS in .env if jobs publish images"
    fi
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
if [ ! -s registry/auth/registry.password ] || [ "${REGISTRY_PASS_EXPLICIT}" = "1" ]; then
    htpasswd -Bbn "${REGISTRY_USER}" "${REGISTRY_PASS}" >registry/auth/registry.password
    chmod 600 registry/auth/registry.password
    say "wrote registry/auth/registry.password for user ${REGISTRY_USER}"
fi

if [ "${GENERATED_REGISTRY_PASS:-0}" = "1" ]; then
    say "generated registry password (save it now): user=${REGISTRY_USER} password=${REGISTRY_PASS}"
fi

# --- start ----------------------------------------------------------------------
# Docker group membership only applies to new shell sessions; try `sg` before giving up.
docker_ok() { docker info >/dev/null 2>&1; }
docker_via_sg() {
    command -v sg >/dev/null 2>&1 && sg docker -c "docker info" >/dev/null 2>&1
}

run_fleet() {
    if docker_ok; then
        ./fleet.sh "$@"
    elif docker_via_sg; then
        local quoted="./fleet.sh" arg
        for arg in "$@"; do
            quoted+=" $(printf '%q' "${arg}")"
        done
        sg docker -c "${quoted}"
    else
        return 127
    fi
}

if [ "${START}" = "0" ]; then
    say "setup complete. Start the fleet with: cd ${INSTALL_DIR} && ./fleet.sh build && ./fleet.sh up"
    exit 0
fi

if ! docker_ok && ! docker_via_sg; then
    say "Docker is installed but not accessible in this shell."
    say "Log out and back in, then run: cd ${INSTALL_DIR} && ./fleet.sh build && ./fleet.sh up"
    exit 0
fi

run_fleet build || die "./fleet.sh build failed; see the output above"
while read -r org; do
    [ -n "${org}" ] || continue
    say "building custom image for ${org}"
    run_fleet build "${org}" || die "./fleet.sh build ${org} failed; see the output above"
done < <(awk '/^[A-Za-z0-9._-]+/ { for (i = 2; i <= NF; i++) if ($i ~ /^context=/) print $1 }' orgs.conf)
run_fleet up || die "./fleet.sh up failed; see the output above"

say "fleet started. Check it with: cd ${INSTALL_DIR} && ./fleet.sh status"
