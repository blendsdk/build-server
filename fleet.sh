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
  status                   Show the fleet and container state
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

declare -A SEEN_NAMES=()
declare -A SEEN_SLUGS=()

# Parse and validate orgs.conf into the parallel arrays. Exits non-zero with a line-numbered
# message on any malformed entry.
parse_config() {
    local lineno=0 line name rest key value slug word
    ORG_NAMES=() ORG_SLUGS=() ORG_URLS=() ORG_APIS=() ORG_CONTEXTS=() ORG_BUILD_TEMP=()
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

        local url="https://github.com/${name}" context="" build_temp=0
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
                *) die "orgs.conf:${lineno}: unknown option '${key}'" ;;
            esac
        done

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
    done <"${ORGS_FILE}"

    [ "${#ORG_NAMES[@]}" -gt 0 ] || die "orgs.conf: no organizations defined"
}

# Render the runner services atomically into docker-compose.generated.yml.
render_compose() {
    GENERATED_TMP="${GENERATED_FILE}.tmp"
    {
        echo "# Generated by fleet.sh from orgs.conf — do not edit by hand."
        echo "services:"
        local i name slug url api context build_temp image
        for i in "${!ORG_NAMES[@]}"; do
            name="${ORG_NAMES[$i]}"
            slug="${ORG_SLUGS[$i]}"
            url="${ORG_URLS[$i]}"
            api="${ORG_APIS[$i]}"
            context="${ORG_CONTEXTS[$i]}"
            build_temp="${ORG_BUILD_TEMP[$i]}"
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
            if [ "${build_temp}" = "1" ]; then
                cat <<EOF
    volumes:
      - /tmp:/build-temp
EOF
            fi
        done
    } >"${GENERATED_TMP}"
    mv "${GENERATED_TMP}" "${GENERATED_FILE}"
    GENERATED_TMP=""
    echo "fleet: generated ${#ORG_NAMES[@]} runner(s): ${ORG_SLUGS[*]}"
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
    [ ! -e "${ROOT}/ssh" ] || die "${ROOT}/ssh already exists; remove the leftover staging directory"
    stage_ssh "${ROOT}"
    STAGED_PATHS+=("${ROOT}/ssh")
    docker build --build-arg "RUNNER_VERSION=${version}" -t runner-image "${ROOT}"
    cleanup_staging
}

# Build one organization's custom image from its context, staged in a temporary directory.
build_org() {
    local slug="$1" version="${2:-$(resolved_version)}" index context staging
    index="$(org_index_by_slug "${slug}")" || die "unknown organization '${slug}'"
    context="${ORG_CONTEXTS[$index]}"
    [ -n "${context}" ] ||
        die "organization '${ORG_NAMES[$index]}' has no context=; use 'fleet.sh build' for the default image"
    staging="${BUILD_TMP}/${slug}"
    [ ! -e "${staging}" ] || die "${staging} already exists; remove the leftover staging directory"
    umask 077
    mkdir -p "${staging}"
    STAGED_PATHS+=("${staging}")
    cp -R "${context}/." "${staging}/"
    stage_ssh "${staging}"
    stage_credentials "${staging}"
    docker build --build-arg "RUNNER_VERSION=${version}" -t "runner-image-${slug}" "${staging}"
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

# Rebuild every image with the latest runner version and recreate the fleet.
update_runners() {
    local version i
    version="$(fetch_latest_version)"
    build_default "${version}"
    for i in "${!ORG_NAMES[@]}"; do
        [ -z "${ORG_CONTEXTS[$i]}" ] || build_org "${ORG_SLUGS[$i]}" "${version}"
    done
    printf '%s\n' "${version}" >"${RUNNER_VERSION_FILE}"
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
        ;;
    update)
        parse_config
        render_compose
        [ "${#}" -ge 2 ] || die "update requires an organization"
        update_org "$(slugify "${2}")"
        ;;
    update-runners)
        parse_config
        render_compose
        update_runners
        ;;
    up)
        parse_config
        render_compose
        require_images
        remove_legacy_containers
        compose up -d
        ;;
    down)
        parse_config
        render_compose
        remove_legacy_containers
        compose down --remove-orphans
        ;;
    stop)
        parse_config
        render_compose
        compose stop
        ;;
    start)
        parse_config
        render_compose
        compose start
        ;;
    restart)
        parse_config
        render_compose
        require_images
        remove_legacy_containers
        compose down --remove-orphans
        compose up -d
        ;;
    status)
        parse_config
        render_compose
        print_fleet
        compose ps
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
