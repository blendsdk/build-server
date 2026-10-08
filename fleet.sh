#!/bin/bash
# fleet.sh — manage the self-hosted runner fleet from orgs.conf.
#
# The organization file is the source of truth. `generate` renders the runner services into
# docker-compose.generated.yml, which is merged with the static registry base in
# docker-compose.yml. Additional subcommands manage images and the fleet lifecycle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "${ROOT}"

# Host configuration (ACCESS_TOKEN, registry credentials) when present.
if [ -f "${ROOT}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${ROOT}/.env"
    set +a
fi

# Compose project names must start with a letter or number and may contain only lowercase
# letters, numbers, hyphens, and underscores.
compose_project_name() {
    local value
    value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-' | sed 's/^[^a-z0-9]*//')"
    [ -n "${value}" ] || value="build-server"
    printf '%s' "${value}"
}

# The project name prefixes every container so several installations can share one Docker host.
# .env sets it (bootstrap defaults it to the install user); the login name is the fallback.
COMPOSE_PROJECT_NAME="$(compose_project_name "${COMPOSE_PROJECT_NAME:-$(id -un)}")"

ORGS_FILE="${ROOT}/orgs.conf"
GENERATED_FILE="${ROOT}/docker-compose.generated.yml"
RUNNER_VERSION_FILE="${ROOT}/.runner-version"

die() {
    echo "fleet: ERROR: $*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
Usage: fleet.sh <command> [args]

  generate                 Render docker-compose.generated.yml from orgs.conf
  build [org]              Build the default image, or one org's custom image
  up | down | stop | start | restart
                           Manage the fleet
  update <org>             Rebuild one org's image and recreate only its runner
  update-runners           Rebuild every image with the latest Actions runner version
  clean [--yes]            Remove this installation's unused images and the host build cache
  upgrade-all [--yes]      Full teardown, cleanup, rebuild with the latest runner, and restart
  status                   Show the fleet and container state
  check-ssh <org> [args...] Run the deploy SSH connectivity check in one organization's runner
  keygen <org> [name]      Create a deploy key pair for one organization (ed25519; --rsa, --force)
EOF
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

# Parallel arrays describing the organizations, in file order.
ORG_NAMES=()
ORG_SLUGS=()
ORG_URLS=()
ORG_APIS=()
ORG_CONTEXTS=()
ORG_BUILD_TEMP=()
ORG_DEPLOY_SSH=()

declare -A SEEN_NAMES=()
declare -A SEEN_SLUGS=()

# Parse and validate orgs.conf into the parallel arrays. Exits non-zero with a line-numbered
# message on any malformed entry.
parse_config() {
    local lineno=0 line name rest key value slug word deploy_ssh deploy_ssh_set resolved_deploy_ssh
    ORG_NAMES=() ORG_SLUGS=() ORG_URLS=() ORG_APIS=() ORG_CONTEXTS=() ORG_BUILD_TEMP=() ORG_DEPLOY_SSH=()
    SEEN_NAMES=() SEEN_SLUGS=()

    [ -f "${ORGS_FILE}" ] || die "missing configuration file ${ORGS_FILE}"

    while IFS= read -r line || [ -n "${line}" ]; do
        lineno=$((lineno + 1))
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "${line}" ] && continue
        case "${line}" in \#*) continue ;; esac

        read -r name rest <<<"${line}"
        [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || die "orgs.conf:${lineno}: invalid organization name '${name}'"
        [ -z "${SEEN_NAMES[${name}]:-}" ] || die "orgs.conf:${lineno}: duplicate organization '${name}'"
        SEEN_NAMES["${name}"]=1

        slug="$(slugify "${name}")"
        [ -n "${slug}" ] || die "orgs.conf:${lineno}: organization '${name}' has an empty slug"
        [ -z "${SEEN_SLUGS[${slug}]:-}" ] ||
            die "orgs.conf:${lineno}: slug '${slug}' collides with organization '${SEEN_SLUGS[${slug}]}'"
        SEEN_SLUGS["${slug}"]="${name}"

        local url="https://github.com/${name}" context="" build_temp=0 deploy_ssh="" deploy_ssh_set=0
        local words=()
        read -ra words <<<"${rest}"
        local word
        for word in "${words[@]}"; do
            case "${word}" in
                *=*) key="${word%%=*}" value="${word#*=}" ;;
                *) die "orgs.conf:${lineno}: malformed option '${word}'" ;;
            esac
            case "${key}" in
                url)
                    case "${value}" in
                        https://*) ;;
                        *) die "orgs.conf:${lineno}: url must start with https://" ;;
                    esac
                    case "${value}" in
                        *"@"* | *"?"* | *"#"*)
                            die "orgs.conf:${lineno}: url must not contain userinfo, query, or fragment"
                            ;;
                    esac
                    url="${value}"
                    ;;
                context)
                    [ -d "${ROOT}/${value}" ] || die "orgs.conf:${lineno}: context '${value}' does not exist"
                    local resolved
                    resolved="$(realpath "${ROOT}/${value}")"
                    case "${resolved}" in
                        "${ROOT}"/*) ;;
                        *) die "orgs.conf:${lineno}: context '${value}' resolves outside the repository" ;;
                    esac
                    [ -f "${resolved}/Dockerfile" ] || die "orgs.conf:${lineno}: context '${value}' has no Dockerfile"
                    context="${resolved}"
                    ;;
                build_temp)
                    [ "${value}" = "1" ] || die "orgs.conf:${lineno}: build_temp must be 1"
                    build_temp=1
                    ;;
                deploy_ssh)
                    deploy_ssh="${value}"
                    deploy_ssh_set=1
                    ;;
                *) die "orgs.conf:${lineno}: unknown option '${key}'" ;;
            esac
        done

        resolved_deploy_ssh=""
        if [ "${deploy_ssh_set}" = "1" ]; then
            resolved_deploy_ssh="$(validate_deploy_ssh "${lineno}" "${deploy_ssh}")" || exit 1
        fi

        local authority host api
        authority="${url#https://}"
        authority="${authority%%/*}"
        [ -n "${authority}" ] || die "orgs.conf:${lineno}: url host is empty"
        host="${authority,,}"
        host="${host%:443}"
        if [ "${host}" = "github.com" ]; then
            api="https://api.github.com"
        else
            api="https://${authority}/api/v3"
        fi

        ORG_NAMES+=("${name}")
        ORG_SLUGS+=("${slug}")
        ORG_URLS+=("${url}")
        ORG_APIS+=("${api}")
        ORG_CONTEXTS+=("${context}")
        ORG_BUILD_TEMP+=("${build_temp}")
        ORG_DEPLOY_SSH+=("${resolved_deploy_ssh}")
    done <"${ORGS_FILE}"

    [ "${#ORG_NAMES[@]}" -gt 0 ] || die "orgs.conf: no organizations defined"
}

# Validate one deploy_ssh value and print its resolved absolute path.
#
# The value must be a relative path inside deploy-ssh/. Everything else — empty values, absolute
# paths, parent traversal, glob or mount metacharacters, non-directories, the repository root
# itself, paths escaping through a symlink, and bare deploy-ssh (which would expose every
# organization's material) — is refused with a line-numbered orgs.conf error. Missing paths are
# valid here: the commands that start runner containers create them later.
validate_deploy_ssh() {
    local lineno="$1" value="$2" resolved
    [ -n "${value}" ] || die "orgs.conf:${lineno}: deploy_ssh path must not be empty"
    case "${value}" in
        /*) die "orgs.conf:${lineno}: deploy_ssh path must be relative" ;;
    esac
    case "/${value}/" in
        */../*) die "orgs.conf:${lineno}: deploy_ssh path must not contain '..'" ;;
    esac
    case "${value}" in
        *'*'* | *'?'* | *'['* | *':'* | *'$'*)
            die "orgs.conf:${lineno}: deploy_ssh path must not contain '*', '?', '[', ':', or '\$'"
            ;;
    esac
    if [ -e "${ROOT}/${value}" ] && [ ! -d "${ROOT}/${value}" ]; then
        die "orgs.conf:${lineno}: deploy_ssh '${value}' is not a directory"
    fi
    if [ -e "${ROOT}/${value}" ]; then
        resolved="$(realpath "${ROOT}/${value}")"
    else
        resolved="$(realpath -m "${ROOT}/${value}")"
    fi
    [ "${resolved}" != "${ROOT}" ] ||
        die "orgs.conf:${lineno}: deploy_ssh path must not be the repository root"
    case "${resolved}" in
        "${ROOT}"/*) ;;
        *) die "orgs.conf:${lineno}: deploy_ssh '${value}' resolves outside the repository" ;;
    esac
    case "${resolved}" in
        "${ROOT}/deploy-ssh/"*) ;;
        *) die "orgs.conf:${lineno}: deploy_ssh path must be inside 'deploy-ssh/'" ;;
    esac
    # Re-check the canonical path: a symlink target can carry characters the raw value never had,
    # and those characters would flow into the generated Compose file's mount string.
    local resolved_rel="${resolved#"${ROOT}"/}"
    case "${resolved_rel}" in
        *'*'* | *'?'* | *'['* | *':'* | *'$'*)
            die "orgs.conf:${lineno}: deploy_ssh '${value}' resolves to a path with unsupported characters"
            ;;
    esac
    if [[ "${resolved_rel}" =~ [[:cntrl:]] ]]; then
        die "orgs.conf:${lineno}: deploy_ssh '${value}' resolves to a path with unsupported characters"
    fi
    printf '%s' "${resolved}"
}

# Render the runner services atomically into docker-compose.generated.yml.
render_compose() {
    GENERATED_TMP="${GENERATED_FILE}.tmp"
    {
        echo "# Generated by fleet.sh from orgs.conf — do not edit by hand."
        echo "services:"
        local i name slug url api context build_temp deploy_ssh rel volumes_started image
        for i in "${!ORG_NAMES[@]}"; do
            name="${ORG_NAMES[$i]}"
            slug="${ORG_SLUGS[$i]}"
            url="${ORG_URLS[$i]}"
            api="${ORG_APIS[$i]}"
            context="${ORG_CONTEXTS[$i]}"
            build_temp="${ORG_BUILD_TEMP[$i]}"
            deploy_ssh="${ORG_DEPLOY_SSH[$i]}"
            image="runner-image"
            [ -z "${context}" ] || image="runner-image-${slug}"
            cat <<EOF
  ${slug}:
    image: ${image}
    pull_policy: never
    hostname: ${slug}_runner_1
    restart: unless-stopped
    privileged: true
    environment:
      - ORGANIZATION=${name}
      - ACCESS_TOKEN=\${ACCESS_TOKEN}
      - GITHUB_URL=${url}
      - GITHUB_API_URL=${api}
      - REGISTRY_ADDR=\${REGISTRY_ADDR:-registry:5000}
      - REGISTRY_USER=\${REGISTRY_USER:-}
      - REGISTRY_PASS=\${REGISTRY_PASS:-}
      - INSECURE_REGISTRIES=\${INSECURE_REGISTRIES-registry:5000}
      - DOCKERD_STORAGE_DRIVER=\${DOCKERD_STORAGE_DRIVER:-}
EOF
            volumes_started=0
            if [ -n "${deploy_ssh}" ]; then
                rel="${deploy_ssh#"${ROOT}/"}"
                cat <<EOF
    volumes:
      - ./${rel}:/run/deploy-ssh:ro
EOF
                volumes_started=1
            fi
            if [ "${build_temp}" = "1" ]; then
                if [ "${volumes_started}" = "1" ]; then
                    cat <<EOF
      - /tmp:/build-temp
EOF
                else
                    cat <<EOF
    volumes:
      - /tmp:/build-temp
EOF
                fi
            fi
        done
    } >"${GENERATED_TMP}"
    mv "${GENERATED_TMP}" "${GENERATED_FILE}"
    GENERATED_TMP=""
    echo "fleet: generated ${#ORG_NAMES[@]} runner(s): ${ORG_SLUGS[*]}"
}

# Print the starter deploy configuration seeded into a new deploy folder. Every line is a comment:
# the operator uncomments one example and edits it, so an untouched folder never tests a host.
deploy_config_template() {
    cat <<'EOF'
# Deploy SSH configuration for this organization.
#
# This file is copied into the runner at ~/.ssh/deploy.d/config and included automatically;
# do not add an Include line yourself. After editing, run: ./fleet.sh restart
#
# Folder contents:
#   config       this file
#   known_hosts  pinned server host keys (collect with: deploy-ssh-check --learn <host>)
#   keys/        private keys referenced by IdentityFile (create with: ./fleet.sh keygen <org>)
#
# --- Direct target ---------------------------------------------------------------
#
# Host app-prod
#     HostName 192.168.1.1
#     User deploy
#     Port 22
#     IdentityFile ~/.ssh/deploy.d/keys/id_ed25519
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#
# --- Target behind a bastion -----------------------------------------------------
#
# Host app-private
#     HostName 10.20.1.5
#     User deploy
#     IdentityFile ~/.ssh/deploy.d/keys/id_ed25519
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#     ProxyJump deploy@bastion.example.com
#
# The bastion opens a separate SSH session and needs its own Host block (required):
#
# Host bastion.example.com
#     HostName bastion.example.com
#     User deploy
#     IdentityFile ~/.ssh/deploy.d/keys/bastion
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#
# Test from inside the runner:  ./fleet.sh check-ssh <org>
EOF
}

# Create one deploy folder when missing and seed any missing starter files into it: `keys/`, a
# commented `config`, and an empty `known_hosts`. Existing files (and any symlink) are never
# modified or written through, and the creation notice prints only when the folder itself was
# created. Returns non-zero when the path changed since validation, so callers can decide how to
# report that; a starter path that cannot be created is a fatal error.
seed_deploy_folder() {
    local path="$1" rel="$2"
    [ "$(realpath -m "${path}")" = "${path}" ] || return 1
    if [ ! -d "${path}" ]; then
        (umask 077 && mkdir -p "${path}/keys") ||
            die "could not create ${rel}/keys"
        echo "fleet: created ${rel} with starter files (edit config, add a key, then restart the runner to apply)"
    elif [ ! -d "${path}/keys" ]; then
        (umask 077 && mkdir -p "${path}/keys") ||
            die "could not create ${rel}/keys"
    fi
    # Only completely absent paths are seeded: an existing file — or any symlink, even a dangling
    # one — is operator-provided state, and writing through it could create files outside the
    # deploy folder.
    if [ ! -e "${path}/config" ] && [ ! -L "${path}/config" ]; then
        (umask 077 && deploy_config_template >"${path}/config") ||
            die "could not write ${rel}/config"
    fi
    if [ ! -e "${path}/known_hosts" ] && [ ! -L "${path}/known_hosts" ]; then
        (umask 077 && : >"${path}/known_hosts") ||
            die "could not write ${rel}/known_hosts"
    fi
    return 0
}

# Create declared deploy folders that are missing (or repair missing starter files), with
# restricted modes, and print a notice only when a folder itself was created. Only commands that
# start runner containers call this, and only after their confirmation and version fetch where one
# applies; `generate`, `status`, `down`, `stop`, and `clean` must stay side-effect free. Operator
# material is never deleted.
ensure_deploy_dirs() {
    local i path rel
    for i in "${!ORG_NAMES[@]}"; do
        path="${ORG_DEPLOY_SSH[$i]}"
        [ -n "${path}" ] || continue
        rel="${path#"${ROOT}/"}"
        seed_deploy_folder "${path}" "${rel}" ||
            echo "fleet: WARNING: ${rel} changed since validation; skipping deploy folder creation" >&2
    done
}

# Run docker compose against the merged fleet definition under the project name.
compose() {
    docker compose --project-name "${COMPOSE_PROJECT_NAME}" \
        -f docker-compose.yml -f docker-compose.generated.yml "$@"
}

# The runner version a build would use: the pinned state file, else the Dockerfile default.
resolved_version() {
    if [ -s "${RUNNER_VERSION_FILE}" ]; then
        cat "${RUNNER_VERSION_FILE}"
        return
    fi
    awk -F'"' '/^ARG RUNNER_VERSION=/{print $2; exit}' "${ROOT}/Dockerfile"
}

# The installed host revision recorded by bootstrap.sh, or "not recorded" for older installs.
host_version() {
    local revision="" date=""
    if [ -f "${ROOT}/.build-server-version" ]; then
        revision="$(awk -F= '$1 == "REVISION" { print $2; exit }' "${ROOT}/.build-server-version")"
        date="$(awk -F= '$1 == "DATE" { print $2; exit }' "${ROOT}/.build-server-version")"
    fi
    if [ -z "${revision}" ]; then
        printf 'not recorded'
        return
    fi
    printf '%s (%s)' "${revision}" "${date:-unknown}"
}

# Print the configured fleet and the pinned runner version.
print_fleet() {
    printf '%-22s %-26s %-26s %s\n' "SERVICE" "IMAGE" "HOSTNAME" "ORGANIZATION"
    local i name slug image
    for i in "${!ORG_NAMES[@]}"; do
        name="${ORG_NAMES[$i]}"
        slug="${ORG_SLUGS[$i]}"
        image="runner-image"
        [ -z "${ORG_CONTEXTS[$i]}" ] || image="runner-image-${slug}"
        printf '%-22s %-26s %-26s %s\n' "${slug}" "${image}" "${slug}_runner_1" "${name}"
    done
    echo "Runner version: $(resolved_version)"
    echo "Host version: $(host_version)"
}

CRED_FILES=(.npmrc .yarnrc .bunfig.toml config.json)
BUILD_TMP="${ROOT}/.fleet-build"
STAGED_PATHS=()
GENERATED_TMP=""

# Every image this installation builds carries this label with the Compose project name as its
# value. Cleanup uses it to remove only this installation's images, so several installations can
# share one Docker host without deleting each other's images.
FLEET_LABEL="com.build-server.fleet"

# Remove anything staged for a build, on success or failure.
cleanup_staging() {
    local path
    for path in "${STAGED_PATHS[@]}"; do
        rm -rf "${path}"
    done
    STAGED_PATHS=()
    # Remove the staging root when nothing else is left in it.
    rmdir "${BUILD_TMP}" 2>/dev/null || true
}

# Single EXIT trap for both the generated temp file and any staged build files.
cleanup_all() {
    if [ -n "${GENERATED_TMP}" ]; then
        rm -f "${GENERATED_TMP}"
        GENERATED_TMP=""
    fi
    cleanup_staging
}
trap cleanup_all EXIT

# Remove staging leftovers from an interrupted build before staging again. A SIGKILL can leave
# these directories behind; the build no longer stops on them.
clear_staging_leftovers() {
    if [ -e "${BUILD_TMP}" ] || [ -e "${ROOT}/ssh" ]; then
        echo "fleet: removed leftover build staging"
    fi
    rm -rf "${BUILD_TMP}" "${ROOT}/ssh"
}

# Reclaim disk after a successful build: the replaced image is now untagged, and the build cache
# only speeds up the next build. Docker cannot scope the cache to one installation, so this also
# slows the next build of every other Docker project on the host.
prune_after_build() {
    docker image prune -f
    docker builder prune -af
}

# Remove the current runner images of this installation when they predate the fleet label.
# Labeled images are handled by the scoped prune in purge_fleet, and Docker itself refuses to
# remove an image that a container still references.
remove_legacy_fleet_images() {
    local images=("runner-image") i image labels
    for i in "${!ORG_SLUGS[@]}"; do
        [ -z "${ORG_CONTEXTS[$i]}" ] || images+=("runner-image-${ORG_SLUGS[$i]}")
    done
    for image in "${images[@]}"; do
        docker image inspect "${image}" >/dev/null 2>&1 || continue
        labels="$(docker image inspect --format '{{json .Config.Labels}}' "${image}" 2>/dev/null || true)"
        case "${labels}" in
            *"\"${FLEET_LABEL}\":"*) continue ;;
        esac
        if docker image rm "${image}" >/dev/null 2>&1; then
            echo "fleet: removed legacy image ${image}"
        fi
    done
}

# Remove this installation's unused containers, networks, volumes, and images, plus the host
# build cache. Images are matched by the fleet label, so other installations on the same Docker
# host keep their images; the cache purge is host-wide because Docker cannot scope it.
purge_fleet() {
    clear_staging_leftovers
    echo "fleet: cleaning unused resources of project ${COMPOSE_PROJECT_NAME}"
    docker container prune -f --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
    docker network prune -f --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
    docker volume prune -af --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
    docker image prune -f
    docker image prune -af --filter "label=${FLEET_LABEL}=${COMPOSE_PROJECT_NAME}"
    remove_legacy_fleet_images
    echo "fleet: purging the host build cache (shared with other Docker projects)"
    docker builder prune -af
}

# Ask before a destructive cleanup. --yes is required when no terminal is attached, so scripts
# can never destroy resources by accident.
confirm_destructive() {
    local action="$1" assume_yes="${2:-}" what answer
    case "${action}" in
        clean)
            what="removes this installation's unused images, containers, networks, and volumes, plus the host build cache"
            ;;
        upgrade-all)
            what="stops the fleet, removes this installation's unused images and the host build cache, then rebuilds every image with the latest runner and restarts"
            ;;
        *)
            what="removes unused resources"
            ;;
    esac
    [ "${assume_yes}" = "--yes" ] && return 0
    [ -z "${assume_yes}" ] || die "usage: fleet.sh ${action} [--yes]"
    if [ -t 0 ]; then
        read -r -p "fleet: ${action} ${what}; continue? [y/N] " answer
        case "${answer}" in
            y | Y | yes | YES) return 0 ;;
            *)
                echo "fleet: cancelled"
                exit 0
                ;;
        esac
    fi
    die "${action} requires --yes when not attached to a terminal"
}

# Index of an organization by slug, or non-zero when unknown.
org_index_by_slug() {
    local slug="$1" i
    for i in "${!ORG_SLUGS[@]}"; do
        if [ "${ORG_SLUGS[$i]}" = "${slug}" ]; then
            printf '%s' "${i}"
            return 0
        fi
    done
    return 1
}

# Copy SSH material into DIR with restricted modes.
stage_ssh() {
    local dir="$1"
    umask 077
    [ -d "${HOME}/.ssh" ] || return 0
    cp -R "${HOME}/.ssh" "${dir}/ssh"
    chmod -R go-rwx "${dir}/ssh"
}

# Copy the host credential files into DIR. Used for custom-context builds only: the repository
# root already holds these files for the default build.
stage_credentials() {
    local dir="$1" file
    umask 077
    for file in "${CRED_FILES[@]}"; do
        [ -f "${ROOT}/${file}" ] || continue
        cp "${ROOT}/${file}" "${dir}/${file}"
        chmod 0600 "${dir}/${file}"
    done
}

# Build the default runner image from the repository context.
build_default() {
    local version="${1:-$(resolved_version)}"
    clear_staging_leftovers
    stage_ssh "${ROOT}"
    STAGED_PATHS+=("${ROOT}/ssh")
    docker build --build-arg "RUNNER_VERSION=${version}" \
        --label "${FLEET_LABEL}=${COMPOSE_PROJECT_NAME}" -t runner-image "${ROOT}"
    cleanup_staging
}

# Build one organization's custom image from its context, staged in a temporary directory.
build_org() {
    local slug="$1" version="${2:-$(resolved_version)}" index context staging
    index="$(org_index_by_slug "${slug}")" || die "unknown organization '${slug}'"
    context="${ORG_CONTEXTS[$index]}"
    [ -n "${context}" ] ||
        die "organization '${ORG_NAMES[$index]}' has no context=; use 'fleet.sh build' for the default image"
    clear_staging_leftovers
    staging="${BUILD_TMP}/${slug}"
    umask 077
    mkdir -p "${staging}"
    STAGED_PATHS+=("${staging}")
    cp -R "${context}/." "${staging}/"
    stage_ssh "${staging}"
    stage_credentials "${staging}"
    docker build --build-arg "RUNNER_VERSION=${version}" \
        --label "${FLEET_LABEL}=${COMPOSE_PROJECT_NAME}" -t "runner-image-${slug}" "${staging}"
    cleanup_staging
}

# Resolve the latest Actions runner version from GitHub.
fetch_latest_version() {
    local response status payload tag auth=()
    if [ -n "${ACCESS_TOKEN:-}" ]; then
        auth=(-H "Authorization: token ${ACCESS_TOKEN}")
    fi
    response="$(curl -sS "${auth[@]}" -w $'\n%{http_code}' \
        "https://api.github.com/repos/actions/runner/releases/latest" || true)"
    status="${response##*$'\n'}"
    payload="${response%$'\n'*}"
    [ "${status}" = "200" ] ||
        die "runner release API error (HTTP ${status}): $(jq -r '.message // empty' <<<"${payload}" 2>/dev/null || true)"
    tag="$(jq -r '.tag_name // empty' <<<"${payload}" 2>/dev/null || true)"
    [ -n "${tag}" ] ||
        die "runner release API response has no tag_name: $(jq -r '.message // empty' <<<"${payload}" 2>/dev/null || true)"
    tag="${tag#v}"
    [[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected runner version '${tag}'"
    printf '%s' "${tag}"
}

# Rebuild one organization's image and recreate only its runner.
update_org() {
    local slug="$1" index
    index="$(org_index_by_slug "${slug}")" || die "unknown organization '${slug}'"
    if [ -n "${ORG_CONTEXTS[$index]}" ]; then
        build_org "${slug}"
    else
        build_default
    fi
    remove_legacy_containers
    compose up -d --no-deps "${slug}"
}

# Rebuild the default and every custom image with VERSION, then pin the version. The pin is
# written only after every build succeeds, so a failed upgrade keeps the previous version.
rebuild_all() {
    local version="$1" i
    build_default "${version}"
    for i in "${!ORG_NAMES[@]}"; do
        [ -z "${ORG_CONTEXTS[$i]}" ] || build_org "${ORG_SLUGS[$i]}" "${version}"
    done
    printf '%s\n' "${version}" >"${RUNNER_VERSION_FILE}"
}

# Rebuild every image with the latest runner version and recreate the fleet.
update_runners() {
    local version
    version="$(fetch_latest_version)"
    rebuild_all "${version}"
    ensure_deploy_dirs
    compose up -d
}

# Older versions pinned global container names. Remove those leftovers when their Compose project
# label matches the install directory's former project name, so the project-prefixed containers
# can start without name or port conflicts. Containers of other projects are left alone.
remove_legacy_containers() {
    local legacy_project name label slug
    legacy_project="$(compose_project_name "$(basename "${ROOT}")")"
    local names=("${legacy_project}-registry-1" "${legacy_project}_registry_1")
    for slug in "${ORG_SLUGS[@]}"; do
        names+=("${slug}_runner_1")
    done
    for name in "${names[@]}"; do
        label="$(docker container inspect \
            --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
            "${name}" 2>/dev/null || true)"
        [ "${label}" = "${legacy_project}" ] || continue
        docker rm -f "${name}" >/dev/null
        echo "fleet: removed legacy container ${name}"
    done
}

# Remove the GitHub runner registrations that belong to this installation. Registration tokens
# fetched by the runner at start expire after an hour, so stopping the containers is not a
# reliable way to clean up; `down` calls the API directly. Failures are reported but never fail
# the command, because the fleet is already stopped at this point.
unregister_runners() {
    local i org api runner_name page response status payload count id delete_status
    if [ -z "${ACCESS_TOKEN:-}" ]; then
        echo "fleet: WARNING: ACCESS_TOKEN is not set; runner registrations were not removed" >&2
        return 0
    fi
    for i in "${!ORG_NAMES[@]}"; do
        org="${ORG_NAMES[$i]}"
        api="${ORG_APIS[$i]}"
        runner_name="${org}_${ORG_SLUGS[$i]}_runner_1"
        page=1
        while :; do
            response="$(curl -sS \
                -H "Authorization: token ${ACCESS_TOKEN}" \
                -H 'Accept: application/vnd.github+json' \
                -w $'\n%{http_code}' \
                "${api}/orgs/${org}/actions/runners?per_page=100&page=${page}" || true)"
            status="${response##*$'\n'}"
            payload="${response%$'\n'*}"
            if [ "${status}" != "200" ]; then
                echo "fleet: WARNING: could not list runners for ${org} (HTTP ${status}); registrations were not removed" >&2
                break
            fi
            count="$(jq -r '.runners | length' <<<"${payload}" 2>/dev/null || echo 0)"
            while read -r id; do
                [ -n "${id}" ] || continue
                delete_status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
                    -H "Authorization: token ${ACCESS_TOKEN}" \
                    -H 'Accept: application/vnd.github+json' \
                    "${api}/orgs/${org}/actions/runners/${id}" || true)"
                if [ "${delete_status}" = "204" ]; then
                    echo "fleet: removed runner ${runner_name} from ${org}"
                else
                    echo "fleet: WARNING: could not remove runner ${runner_name} from ${org} (HTTP ${delete_status})" >&2
                fi
            done < <(jq -r --arg name "${runner_name}" '.runners[]? | select(.name == $name) | .id' <<<"${payload}" 2>/dev/null || true)
            [ "${count:-0}" -ge 100 ] || break
            page=$((page + 1))
        done
    done
}

# Fail fast with a clear message when a runner image has not been built locally.
require_images() {
    local i slug image
    for i in "${!ORG_NAMES[@]}"; do
        slug="${ORG_SLUGS[$i]}"
        image="runner-image"
        [ -z "${ORG_CONTEXTS[$i]}" ] || image="runner-image-${slug}"
        if ! docker image inspect "${image}" >/dev/null 2>&1; then
            if [ -z "${ORG_CONTEXTS[$i]}" ]; then
                die "image '${image}' is missing; run './fleet.sh build'"
            fi
            die "image '${image}' is missing; run './fleet.sh build ${ORG_NAMES[$i]}'"
        fi
    done
}

COMMAND="${1:-}"

case "${COMMAND}" in
    generate)
        parse_config
        render_compose
        ;;
    build)
        parse_config
        if [ "${#}" -ge 2 ]; then
            build_org "$(slugify "${2}")"
        else
            build_default
        fi
        prune_after_build
        ;;
    update)
        parse_config
        render_compose
        [ "${#}" -ge 2 ] || die "update requires an organization"
        ensure_deploy_dirs
        update_org "$(slugify "${2}")"
        prune_after_build
        ;;
    update-runners)
        parse_config
        render_compose
        update_runners
        prune_after_build
        ;;
    clean)
        parse_config
        confirm_destructive clean "${2:-}"
        purge_fleet
        ;;
    upgrade-all)
        parse_config
        render_compose
        confirm_destructive upgrade-all "${2:-}"
        # Fetch before tearing anything down: an API failure must leave the fleet untouched.
        version="$(fetch_latest_version)"
        remove_legacy_containers
        compose down --remove-orphans
        purge_fleet
        rebuild_all "${version}"
        ensure_deploy_dirs
        compose up -d
        prune_after_build
        echo "fleet: upgrade to runner ${version} complete"
        ;;
    up)
        parse_config
        render_compose
        require_images
        remove_legacy_containers
        ensure_deploy_dirs
        compose up -d
        ;;
    down)
        parse_config
        render_compose
        remove_legacy_containers
        compose down --remove-orphans
        unregister_runners
        purge_fleet
        ;;
    stop)
        parse_config
        render_compose
        compose stop
        ;;
    start)
        parse_config
        render_compose
        ensure_deploy_dirs
        compose start
        ;;
    restart)
        parse_config
        render_compose
        require_images
        remove_legacy_containers
        compose down --remove-orphans
        ensure_deploy_dirs
        compose up -d
        ;;
    status)
        parse_config
        render_compose
        print_fleet
        compose ps
        ;;
    # check-ssh: run the deploy checker in one organization's runner. Extra arguments are forwarded
    # verbatim (as argv, never through a shell) so the checker's own modes — --learn, explicit host
    # lists — work through this short form.
    check-ssh)
        parse_config
        render_compose
        [ "${#}" -ge 2 ] || die "usage: fleet.sh check-ssh <org> [args...]"
        check_ssh_slug="$(slugify "${2}")"
        check_ssh_index="$(org_index_by_slug "${check_ssh_slug}")" ||
            die "unknown organization '${check_ssh_slug}'"
        [ -n "${ORG_DEPLOY_SSH[$check_ssh_index]}" ] ||
            die "organization '${check_ssh_slug}' has no deploy_ssh configured"
        compose exec -u docker "${check_ssh_slug}" deploy-ssh-check "${@:3}"
        ;;
    # Create a deploy key pair for one organization. The folder is seeded like a container-starting
    # command seeds it; an existing pair is protected unless --force is passed. No passphrase is set
    # because the runner has no SSH agent to unlock one.
    keygen)
        parse_config
        shift
        keygen_usage="usage: fleet.sh keygen <org> [name] [--rsa] [--force]"
        keygen_org="" keygen_name="" keygen_rsa=0 keygen_force=0
        for keygen_arg in "$@"; do
            case "${keygen_arg}" in
                --rsa) keygen_rsa=1 ;;
                --force) keygen_force=1 ;;
                -*) die "${keygen_usage}" ;;
                *)
                    if [ -z "${keygen_org}" ]; then
                        keygen_org="${keygen_arg}"
                    elif [ -z "${keygen_name}" ]; then
                        keygen_name="${keygen_arg}"
                    else
                        die "${keygen_usage}"
                    fi
                    ;;
            esac
        done
        [ -n "${keygen_org}" ] || die "${keygen_usage}"
        keygen_slug="$(slugify "${keygen_org}")"
        keygen_index="$(org_index_by_slug "${keygen_slug}")" ||
            die "unknown organization '${keygen_slug}'"
        [ -n "${ORG_DEPLOY_SSH[$keygen_index]}" ] ||
            die "organization '${keygen_slug}' has no deploy_ssh configured"
        [ -n "${keygen_name}" ] || keygen_name="id_ed25519"
        [[ "${keygen_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
            die "invalid key name '${keygen_name}'"
        case "${keygen_name}" in
            *.pub) die "invalid key name '${keygen_name}'" ;;
        esac
        command -v ssh-keygen >/dev/null 2>&1 ||
            die "ssh-keygen is not installed; install openssh-client"
        keygen_path="${ORG_DEPLOY_SSH[$keygen_index]}"
        keygen_rel="${keygen_path#"${ROOT}/"}"
        seed_deploy_folder "${keygen_path}" "${keygen_rel}" ||
            die "${keygen_rel} changed since validation; refusing to write into it"
        if [ -L "${keygen_path}/keys" ]; then
            die "${keygen_rel}/keys is a symlink; refusing to write a key through it"
        fi
        keygen_key="${keygen_path}/keys/${keygen_name}"
        if [ "${keygen_force}" != "1" ]; then
            if [ -e "${keygen_key}" ] || [ -e "${keygen_key}.pub" ]; then
                die "deploy key '${keygen_name}' already exists in ${keygen_rel}/keys; pass --force to overwrite"
            fi
        fi
        if [ "${keygen_force}" = "1" ]; then
            rm -f "${keygen_key}" "${keygen_key}.pub"
        fi
        if [ "${keygen_rsa}" = "1" ]; then
            ssh-keygen -q -t rsa -b 4096 -N '' -C "build-server ${keygen_slug} deploy key" \
                -f "${keygen_key}"
        else
            ssh-keygen -q -t ed25519 -N '' -C "build-server ${keygen_slug} deploy key" \
                -f "${keygen_key}"
        fi
        chmod 600 "${keygen_key}"
        echo "fleet: created ${keygen_rel}/keys/${keygen_name}"
        echo
        echo "Public key (append it to the deploy user's authorized_keys on the target):"
        cat "${keygen_key}.pub"
        echo
        echo "Suggested config entry for ${keygen_rel}/config:"
        echo
        cat <<EOF
Host app-prod
    HostName <target-host>
    User deploy
    IdentityFile ~/.ssh/deploy.d/keys/${keygen_name}
    UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
    StrictHostKeyChecking yes
EOF
        echo
        echo "Next steps:"
        echo "  1. Append the public key to ~/.ssh/authorized_keys on the target."
        echo "  2. Restart the runner to apply the material:  ./fleet.sh restart"
        echo "  3. Verify connectivity from the runner:  ./fleet.sh check-ssh ${keygen_slug}"
        ;;
    "" )
        usage
        exit 1
        ;;
    *)
        usage
        exit 1
        ;;
esac
