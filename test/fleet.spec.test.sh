#!/bin/bash
# Specification tests for the fleet CLI build, update, and lifecycle commands.
#
# Every external command is stubbed on PATH and records its arguments; the tests assert the exact
# sequence and arguments the CLI must produce, plus the staging and version-state rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Build a sandbox root with a stub docker, curl, and a fake home holding SSH material.
new_sandbox() {
    local dir="$1"
    mkdir -p "${dir}/bin" "${dir}/home/.ssh" "${dir}/orgs/beta"
    printf 'FROM scratch\n' > "${dir}/orgs/beta/Dockerfile"
    printf 'ARG RUNNER_VERSION="1.2.3"\n' > "${dir}/Dockerfile"
    printf 'services: {}\n' > "${dir}/docker-compose.yml"
    # shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
    printf '#!/bin/bash\nprintf "docker %%s\\n" "$*" >> "${TRACE}"\ncase "$*" in\n    *"container inspect"*) printf "%%s\\n" "${LEGACY_PROJECT:-}"; exit "${INSPECT_EXIT:-0}" ;;\n    *"image inspect"*) exit "${IMAGE_INSPECT_EXIT:-0}" ;;\nesac\nexit "${DOCKER_EXIT:-0}"\n' \
        > "${dir}/bin/docker"
    # shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
    printf '#!/bin/bash\nprintf "curl %%s\\n" "$*" >> "${TRACE}"\ncase "$*" in\n    *"-X DELETE"*) code="${DELETE_HTTP_CODE:-204}" ;;\n    *) code="${CURL_HTTP_CODE:-200}" ;;\nesac\ncase "$*" in\n    *"-o /dev/null"*) printf "%%s" "${code}" ;;\n    *) printf "%%s\\n%%s" "${CURL_BODY:-}" "${code}" ;;\nesac\nexit "${CURL_EXIT:-0}"\n' \
        > "${dir}/bin/curl"
    chmod +x "${dir}/bin/docker" "${dir}/bin/curl"
    printf 'key' > "${dir}/home/.ssh/id_rsa"
    printf 'pub' > "${dir}/home/.ssh/id_rsa.pub"
    printf 'Host *\n' > "${dir}/home/.ssh/config"
    printf 'Alpha\nBeta context=orgs/beta\n' > "${dir}/orgs.conf"
    cp "${ROOT}/fleet.sh" "${dir}/fleet.sh"
}

run_fleet() {
    local dir="$1"
    shift
    (cd "${dir}" && HOME="${dir}/home" ACCESS_TOKEN=dummy TRACE="${dir}/trace" \
        PATH="${dir}/bin:${PATH}" CURL_BODY="${CURL_BODY:-}" CURL_EXIT="${CURL_EXIT:-0}" \
        CURL_HTTP_CODE="${CURL_HTTP_CODE:-200}" DOCKER_EXIT="${DOCKER_EXIT:-0}" \
        IMAGE_INSPECT_EXIT="${IMAGE_INSPECT_EXIT:-0}" bash fleet.sh "$@")
}

# --- update-runners: default first, version arg everywhere, state written after builds -----
S="${T}/update-runners"
new_sandbox "${S}"
CURL_BODY='{"tag_name":"v9.9.9"}' run_fleet "${S}" update-runners >"${S}/out" 2>&1 ||
    {
        cat "${S}/out" >&2
        fail "update-runners should succeed"
    }
[ "$(cat "${S}/.runner-version")" = "9.9.9" ] || fail "pinned version not written"
DEFAULT_LINE="$(grep -n -- '-t runner-image ' "${S}/trace" | head -1 | cut -d: -f1)"
CUSTOM_LINE="$(grep -n -- '-t runner-image-beta ' "${S}/trace" | head -1 | cut -d: -f1)"
UP_LINE="$(grep -n 'up -d' "${S}/trace" | tail -1 | cut -d: -f1)"
[ -n "${DEFAULT_LINE}" ] || fail "default image build missing"
[ -n "${CUSTOM_LINE}" ] || fail "custom image build missing"
[ "${DEFAULT_LINE}" -lt "${CUSTOM_LINE}" ] || fail "default image must build before custom contexts"
[ "$(grep -c -- '--build-arg RUNNER_VERSION=9.9.9' "${S}/trace")" -eq 2 ] || fail "both builds need the version arg"
[ "${CUSTOM_LINE}" -lt "${UP_LINE}" ] || fail "fleet must be recreated after the builds"
grep -q 'Authorization: token dummy' "${S}/trace" || fail "API request must carry the host token"
echo "PASS: update-runners builds default first, pins the version, then recreates"

# --- update <org>: custom context image, only that service recreated -----------------------
S="${T}/update-custom"
new_sandbox "${S}"
run_fleet "${S}" update Beta >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "update Beta should succeed"
}
grep -q -- '-t runner-image-beta ' "${S}/trace" || fail "custom image build missing"
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml up -d --no-deps beta' "${S}/trace" ||
    fail "targeted recreate missing"
[ "$(grep -c ' up ' "${S}/trace")" -eq 1 ] || fail "only one compose up expected"
[ -f "${S}/docker-compose.generated.yml" ] || fail "generate must run before update"
echo "PASS: update <org> rebuilds the custom image and recreates only that runner"

# --- update <org>: default image for orgs without a context --------------------------------
S="${T}/update-default"
new_sandbox "${S}"
run_fleet "${S}" update Alpha >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "update Alpha should succeed"
}
grep -q -- '-t runner-image ' "${S}/trace" || fail "default image build missing"
grep -qF -- 'up -d --no-deps alpha' "${S}/trace" || fail "targeted recreate missing"
grep -q -- '--build-arg RUNNER_VERSION=' "${S}/trace" || fail "resolved version arg missing"
echo "PASS: update <org> uses the default image when no context is configured"

# --- lifecycle flags -----------------------------------------------------------------------
S="${T}/lifecycle"
new_sandbox "${S}"
run_fleet "${S}" up >/dev/null 2>&1 || fail "up should succeed"
run_fleet "${S}" down >/dev/null 2>&1 || fail "down should succeed"
run_fleet "${S}" stop >/dev/null 2>&1 || fail "stop should succeed"
run_fleet "${S}" start >/dev/null 2>&1 || fail "start should succeed"
run_fleet "${S}" restart >/dev/null 2>&1 || fail "restart should succeed"
UP_COMPOSE="$(grep ' up -d$' "${S}/trace" | head -1)"
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml down --remove-orphans' "${S}/trace" ||
    fail "down must remove orphans"
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml stop' "${S}/trace" || fail "stop mapping missing"
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml start' "${S}/trace" || fail "start mapping missing"
case "${UP_COMPOSE}" in
    *remove-orphans*) fail "up must not remove orphans" ;;
esac
[ "$(grep -c 'down --remove-orphans' "${S}/trace")" -eq 2 ] || fail "down and restart must both remove orphans"
echo "PASS: lifecycle commands map correctly and only down/restart remove orphans"

# --- up refuses to start when a runner image has not been built locally ---------------------
S="${T}/missing-image"
new_sandbox "${S}"
set +e
IMAGE_INSPECT_EXIT=1 run_fleet "${S}" up >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "up must fail when a runner image is missing"
grep -qi 'missing' "${S}/out" || fail "missing-image error not shown"
grep -q 'fleet.sh build' "${S}/out" || fail "missing-image error should name the build command"
echo "PASS: up rejects missing local images with guidance"

# --- generate-first and merged -f flags on every compose command ---------------------------
S="${T}/generate-first"
new_sandbox "${S}"
run_fleet "${S}" up >/dev/null 2>&1
run_fleet "${S}" status >/dev/null 2>&1
while read -r invocation; do
    line="$(sed -n "${invocation}p" "${S}/trace")"
    case "${line}" in
        *'-f docker-compose.yml -f docker-compose.generated.yml'*) ;;
        *) fail "compose invocation missing both -f files: ${line}" ;;
    esac
done < <(grep -n 'docker compose' "${S}/trace" | cut -d: -f1)
[ -f "${S}/docker-compose.generated.yml" ] || fail "generate must run first"
echo "PASS: compose commands use generate-first and both -f files"

# --- build: default, custom staging, and the no-context error ------------------------------
S="${T}/build"
new_sandbox "${S}"
# The production host has the credential files in the repository root; the default build must
# leave them untouched rather than staging them onto themselves.
printf 'token' > "${S}/.npmrc"
printf 'token' > "${S}/.yarnrc"
run_fleet "${S}" build >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "bare build should succeed"
}
grep -q -- '-t runner-image ' "${S}/trace" || fail "default build missing"
[ ! -d "${S}/ssh" ] || fail "default build left staged ssh behind"
[ "$(cat "${S}/.npmrc")" = "token" ] || fail "default build modified the root .npmrc"
[ "$(cat "${S}/.yarnrc")" = "token" ] || fail "default build modified the root .yarnrc"

: > "${S}/trace"
run_fleet "${S}" build Beta >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "custom build should succeed"
}
grep -q -- '-t runner-image-beta' "${S}/trace" || fail "custom image build missing"
grep -q "${S}/.fleet-build/beta" "${S}/trace" || fail "custom build must use the temp staging directory"
[ ! -d "${S}/.fleet-build" ] || fail "custom build left the staging directory behind"

set +e
run_fleet "${S}" build Alpha >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "build for an org without a context should fail"
grep -qi 'context' "${S}/out" || fail "no-context error should mention the context"
echo "PASS: build handles default, custom, and no-context targets"

# --- build failure still cleans staging, including update/update-runners -------------------
S="${T}/build-fail"
new_sandbox "${S}"
set +e
DOCKER_EXIT=7 run_fleet "${S}" build Beta >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failing docker build must fail the command"
[ ! -d "${S}/.fleet-build" ] || fail "staging directory left behind after a failed build"

set +e
DOCKER_EXIT=7 run_fleet "${S}" update Beta >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failing update build must fail the command"
[ ! -d "${S}/.fleet-build" ] || fail "staging directory left behind after a failed update"

set +e
CURL_BODY='{"tag_name":"v9.9.9"}' DOCKER_EXIT=7 run_fleet "${S}" update-runners >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failing update-runners build must fail the command"
[ ! -d "${S}/.fleet-build" ] || fail "staging directory left behind after a failed update-runners"
[ ! -d "${S}/ssh" ] || fail "default staging directory left behind after a failed update-runners"
echo "PASS: failed builds clean their staging directories"

# --- status reports the fleet and the pinned version ---------------------------------------
S="${T}/status"
new_sandbox "${S}"
printf '9.9.9\n' > "${S}/.runner-version"
run_fleet "${S}" status >"${S}/out" 2>&1 || fail "status should succeed"
for expected in "Alpha" "alpha" "beta" "runner-image-beta" "Runner version: 9.9.9"; do
    grep -qF "${expected}" "${S}/out" || fail "status output missing '${expected}'"
done
echo "PASS: status reports the fleet and the pinned version"

# --- status reports the installed host revision ----------------------------------------------
S="${T}/host-version"
new_sandbox "${S}"
printf 'REVISION=abc123\nDATE=2026-10-03T10:00:00Z\n' > "${S}/.build-server-version"
run_fleet "${S}" status >"${S}/out" 2>&1 || fail "status should succeed with a host version"
grep -qF 'Host version: abc123 (2026-10-03T10:00:00Z)' "${S}/out" ||
    fail "status must report the installed revision"
echo "PASS: status reports the installed host revision"

# --- the Compose project name comes from .env ------------------------------------------------
S="${T}/project-name"
new_sandbox "${S}"
printf 'COMPOSE_PROJECT_NAME=user-proj\n' > "${S}/.env"
run_fleet "${S}" status >/dev/null 2>&1 || fail "status should succeed with a project name"
grep -qF -- '--project-name user-proj' "${S}/trace" ||
    fail "the project name from .env must be used"
echo "PASS: the Compose project name comes from .env"

# --- without .env the login name is the fallback project name --------------------------------
S="${T}/project-fallback"
new_sandbox "${S}"
run_fleet "${S}" status >/dev/null 2>&1 || fail "status should succeed without .env"
grep -qE -- '--project-name [a-z0-9][a-z0-9_-]*' "${S}/trace" ||
    fail "a sanitized login name must be used as the project name"
echo "PASS: the login name is the fallback project name"

# --- legacy containers from older installs are removed before starting -----------------------
S="${T}/legacy-cleanup"
new_sandbox "${S}"
OLD_PROJECT="$(basename "${S}")"
LEGACY_PROJECT="${OLD_PROJECT}" run_fleet "${S}" up >"${S}/out" 2>&1 ||
    fail "up should succeed while cleaning legacy containers"
grep -qF 'docker rm -f alpha_runner_1' "${S}/trace" || fail "legacy runner container must be removed"
grep -qF 'docker rm -f beta_runner_1' "${S}/trace" || fail "every legacy runner container must be removed"
grep -qF "docker rm -f ${OLD_PROJECT}-registry-1" "${S}/trace" ||
    fail "legacy registry container must be removed"
grep -qi 'legacy' "${S}/out" || fail "legacy removals should be reported"
echo "PASS: legacy containers are removed before starting"

# --- containers belonging to another project are never removed -------------------------------
S="${T}/legacy-guard"
new_sandbox "${S}"
LEGACY_PROJECT="someone-else" run_fleet "${S}" up >/dev/null 2>&1 ||
    fail "up should succeed when the inspected containers belong to another project"
grep -q 'docker rm -f' "${S}/trace" && fail "containers of other projects must not be removed"
echo "PASS: containers of other projects are left alone"

# --- down removes this installation's runner registrations -----------------------------------
S="${T}/down-unregister"
new_sandbox "${S}"
: > "${S}/trace"
CURL_BODY='{"total_count":3,"runners":[{"id":11,"name":"Alpha_alpha_runner_1"},{"id":22,"name":"Beta_beta_runner_1"},{"id":33,"name":"Someone_else_runner"}]}' \
    CURL_HTTP_CODE=200 run_fleet "${S}" down >"${S}/out" 2>&1 ||
    fail "down should succeed while removing runner registrations"
grep -qF '/orgs/Alpha/actions/runners?per_page=100' "${S}/trace" ||
    fail "down must list the Alpha runners"
grep -qF '/orgs/Beta/actions/runners?per_page=100' "${S}/trace" ||
    fail "down must list the Beta runners"
grep -F '/orgs/Alpha/actions/runners/11' "${S}/trace" | grep -q -- '-X DELETE' ||
    fail "down must delete the matching Alpha runner"
grep -F '/orgs/Beta/actions/runners/22' "${S}/trace" | grep -q -- '-X DELETE' ||
    fail "down must delete the matching Beta runner"
grep -q 'runners/33' "${S}/trace" && fail "runners with other names must not be deleted"
grep -qF 'removed runner Alpha_alpha_runner_1 from Alpha' "${S}/out" ||
    fail "the removal should be reported"
DOWN_LINE="$(grep -n 'down --remove-orphans' "${S}/trace" | head -1 | cut -d: -f1)"
DELETE_LINE="$(grep -n -- '-X DELETE' "${S}/trace" | head -1 | cut -d: -f1)"
if [ -z "${DOWN_LINE}" ] || [ -z "${DELETE_LINE}" ] || [ "${DOWN_LINE}" -ge "${DELETE_LINE}" ]; then
    fail "runners must be removed after the fleet is stopped"
fi
echo "PASS: down removes this installation's runner registrations"

# --- API errors are warnings; the fleet is already stopped -----------------------------------
S="${T}/down-unregister-error"
new_sandbox "${S}"
CURL_BODY='{"total_count":0,"runners":[]}' CURL_HTTP_CODE=500 run_fleet "${S}" down >"${S}/out" 2>&1 ||
    fail "down must succeed even when the API call fails"
grep -qi 'WARNING' "${S}/out" || fail "an API failure must be reported as a warning"
grep -q -- '-X DELETE' "${S}/trace" && fail "nothing may be deleted when the list call fails"
echo "PASS: API errors are reported but do not fail down"

# --- down without a token warns and keeps the registrations ----------------------------------
S="${T}/down-no-token"
new_sandbox "${S}"
set +e
(cd "${S}" && HOME="${S}/home" TRACE="${S}/trace" PATH="${S}/bin:${PATH}" \
    CURL_BODY='{"total_count":0,"runners":[]}' CURL_HTTP_CODE=200 bash fleet.sh down) \
    >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -eq 0 ] || fail "down must succeed without a token"
grep -q 'ACCESS_TOKEN' "${S}/out" || fail "the missing token must be named"
grep -q 'actions/runners' "${S}/trace" && fail "no runner API call may happen without a token"
echo "PASS: a missing token warns and keeps the registrations"

# --- error paths leave the pinned version untouched ----------------------------------------
S="${T}/api-fail"
new_sandbox "${S}"
printf '9.9.9\n' > "${S}/.runner-version"
set +e
CURL_EXIT=22 CURL_HTTP_CODE=000 run_fleet "${S}" update-runners >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "API failure should fail update-runners"
[ "$(cat "${S}/.runner-version")" = "9.9.9" ] || fail "API failure must not touch the pinned version"

S="${T}/api-tagless"
new_sandbox "${S}"
printf '9.9.9\n' > "${S}/.runner-version"
set +e
CURL_BODY='{"message":"API rate limit exceeded"}' run_fleet "${S}" update-runners >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a response without tag_name should fail update-runners"
[ "$(cat "${S}/.runner-version")" = "9.9.9" ] || fail "a tagless response must not touch the pinned version"
grep -q 'API rate limit exceeded' "${S}/out" || fail "API error message should be surfaced"

S="${T}/build-fail-state"
new_sandbox "${S}"
printf '9.9.9\n' > "${S}/.runner-version"
set +e
CURL_BODY='{"tag_name":"v8.8.8"}' DOCKER_EXIT=7 run_fleet "${S}" update-runners >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "mid-build failure should fail update-runners"
[ "$(cat "${S}/.runner-version")" = "9.9.9" ] || fail "mid-build failure must not advance the pinned version"

set +e
run_fleet "${S}" frobnicate >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "unknown command should fail"

set +e
run_fleet "${S}" update NoSuchOrg >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "unknown org should fail"
echo "PASS: error paths fail cleanly and preserve state"

# --- clean: confirmation, staging, and installation-scoped pruning --------------------------
S="${T}/clean"
new_sandbox "${S}"
mkdir -p "${S}/.fleet-build/beta" "${S}/ssh"
printf 'junk' > "${S}/.fleet-build/beta/junk"
printf 'junk' > "${S}/ssh/id_rsa"
: > "${S}/trace"
set +e
run_fleet "${S}" clean >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "clean without --yes must fail when non-interactive"
grep -q 'prune' "${S}/trace" && fail "clean without --yes must not touch docker"

run_fleet "${S}" clean --yes >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "clean --yes should succeed"
}
[ ! -d "${S}/.fleet-build" ] || fail "clean must remove the staging directory"
[ ! -d "${S}/ssh" ] || fail "clean must remove leftover ssh staging"
grep -qF 'container prune -f --filter label=com.docker.compose.project=' "${S}/trace" ||
    fail "clean must prune this project's stopped containers"
grep -qF 'network prune -f --filter label=com.docker.compose.project=' "${S}/trace" ||
    fail "clean must prune this project's networks"
grep -qF 'volume prune -af --filter label=com.docker.compose.project=' "${S}/trace" ||
    fail "clean must prune this project's volumes"
grep -qF 'image prune -f' "${S}/trace" || fail "clean must remove dangling images"
grep -qF 'image prune -af --filter label=com.build-server.fleet=' "${S}/trace" ||
    fail "clean must remove this installation's unused images"
grep -qF 'image rm runner-image' "${S}/trace" || fail "clean must remove legacy unlabeled runner images"
grep -qF 'builder prune -af' "${S}/trace" || fail "clean must purge the build cache"
echo "PASS: clean confirms, clears staging, and prunes this installation's resources"

# --- down: stop, unregister, then clean unused resources in that order ----------------------
S="${T}/down-cleanup"
new_sandbox "${S}"
: > "${S}/trace"
CURL_BODY='{"total_count":1,"runners":[{"id":11,"name":"Alpha_alpha_runner_1"}]}' CURL_HTTP_CODE=200 \
    run_fleet "${S}" down >"${S}/out" 2>&1 || fail "down should succeed with cleanup"
DOWN_LINE="$(grep -n 'down --remove-orphans' "${S}/trace" | head -1 | cut -d: -f1)"
DELETE_LINE="$(grep -n -- '-X DELETE' "${S}/trace" | head -1 | cut -d: -f1)"
CACHE_LINE="$(grep -n 'builder prune -af' "${S}/trace" | head -1 | cut -d: -f1)"
IMAGE_LINE="$(grep -n 'image prune -af --filter label=com.build-server.fleet=' "${S}/trace" | head -1 | cut -d: -f1)"
[ -n "${CACHE_LINE}" ] || fail "down must purge the build cache"
[ -n "${IMAGE_LINE}" ] || fail "down must remove this installation's unused images"
[ "${DOWN_LINE}" -lt "${CACHE_LINE}" ] || fail "cleanup must run after the fleet is stopped"
[ "${DELETE_LINE}" -lt "${IMAGE_LINE}" ] || fail "image cleanup must run after unregistration"
echo "PASS: down stops, unregisters, then cleans unused resources"

# --- restart must not run the destructive cleanup -------------------------------------------
S="${T}/restart-keeps"
new_sandbox "${S}"
: > "${S}/trace"
run_fleet "${S}" restart >/dev/null 2>&1 || fail "restart should succeed"
grep -q 'builder prune' "${S}/trace" && fail "restart must not purge the build cache"
grep -q 'image rm' "${S}/trace" && fail "restart must not remove runner images"
echo "PASS: restart leaves images and the build cache in place"

# --- build clears staging leftovers from an interrupted run ---------------------------------
S="${T}/build-leftovers"
new_sandbox "${S}"
mkdir -p "${S}/.fleet-build/beta" "${S}/ssh"
printf 'junk' > "${S}/.fleet-build/beta/junk"
: > "${S}/trace"
run_fleet "${S}" build Beta >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "build must clear leftover staging instead of failing"
}
grep -q -- '-t runner-image-beta' "${S}/trace" || fail "custom image build missing after leftover cleanup"
[ ! -d "${S}/.fleet-build" ] || fail "staging directory left behind"
[ ! -d "${S}/ssh" ] || fail "ssh staging left behind"
echo "PASS: build clears leftover staging before building"

# --- builds label their images and purge after success, not after failure -------------------
S="${T}/build-prune"
new_sandbox "${S}"
: > "${S}/trace"
run_fleet "${S}" build >/dev/null 2>&1 || fail "build should succeed"
grep -qF -- '--label com.build-server.fleet=' "${S}/trace" ||
    fail "fleet images must carry the installation label"
grep -qF 'image prune -f' "${S}/trace" || fail "build must remove dangling images"
grep -qF 'builder prune -af' "${S}/trace" || fail "build must purge the build cache"
echo "PASS: successful builds label images and purge leftovers"

S="${T}/build-prune-fail"
new_sandbox "${S}"
: > "${S}/trace"
set +e
DOCKER_EXIT=7 run_fleet "${S}" build >/dev/null 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failing build must fail the command"
grep -q 'builder prune' "${S}/trace" && fail "a failed build must not purge the build cache"
echo "PASS: failed builds leave the build cache in place"

# --- upgrade-all: fetch, teardown, cleanup, rebuild, and restart ----------------------------
S="${T}/upgrade-all"
new_sandbox "${S}"
printf 'COMPOSE_PROJECT_NAME=upgrade-proj\n' > "${S}/.env"
cp "${S}/orgs.conf" "${S}/orgs.conf.before"
: > "${S}/trace"
set +e
run_fleet "${S}" upgrade-all >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "upgrade-all without --yes must fail when non-interactive"
grep -q 'tag_name' "${S}/trace" && fail "upgrade-all without --yes must not call the GitHub API"

: > "${S}/trace"
CURL_BODY='{"tag_name":"v9.9.9"}' run_fleet "${S}" upgrade-all --yes >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "upgrade-all --yes should succeed"
}
[ "$(cat "${S}/.runner-version")" = "9.9.9" ] || fail "upgrade-all must pin the fetched version"
cmp -s "${S}/orgs.conf" "${S}/orgs.conf.before" || fail "upgrade-all must preserve orgs.conf"
FETCH_LINE="$(grep -n 'actions/runner/releases/latest' "${S}/trace" | head -1 | cut -d: -f1)"
DOWN_LINE="$(grep -n 'down --remove-orphans' "${S}/trace" | head -1 | cut -d: -f1)"
CACHE_LINE="$(grep -n 'builder prune -af' "${S}/trace" | head -1 | cut -d: -f1)"
DEFAULT_LINE="$(grep -n -- '-t runner-image ' "${S}/trace" | head -1 | cut -d: -f1)"
CUSTOM_LINE="$(grep -n -- '-t runner-image-beta ' "${S}/trace" | head -1 | cut -d: -f1)"
UP_LINE="$(grep -n 'up -d' "${S}/trace" | tail -1 | cut -d: -f1)"
[ -n "${FETCH_LINE}" ] || fail "upgrade-all must fetch the latest runner version"
[ -n "${DOWN_LINE}" ] || fail "upgrade-all must stop the fleet"
[ -n "${CACHE_LINE}" ] || fail "upgrade-all must clean the build cache"
[ -n "${DEFAULT_LINE}" ] || fail "upgrade-all must rebuild the default image"
[ -n "${CUSTOM_LINE}" ] || fail "upgrade-all must rebuild custom images"
[ "${FETCH_LINE}" -lt "${DOWN_LINE}" ] ||
    fail "the version must be fetched before the teardown so an API failure changes nothing"
[ "${DOWN_LINE}" -lt "${CACHE_LINE}" ] || fail "cleanup must run after the teardown"
[ "${CACHE_LINE}" -lt "${DEFAULT_LINE}" ] || fail "images must be rebuilt after the cleanup"
[ "${DEFAULT_LINE}" -lt "${CUSTOM_LINE}" ] || fail "the default image must build first"
[ "${CUSTOM_LINE}" -lt "${UP_LINE}" ] || fail "the fleet must start after the rebuilds"
[ "$(grep -c -- '--build-arg RUNNER_VERSION=9.9.9' "${S}/trace")" -eq 2 ] ||
    fail "every upgrade-all build must use the fetched version"
grep -q -- '-X DELETE' "${S}/trace" && fail "upgrade-all must not remove runner registrations"
echo "PASS: upgrade-all fetches, tears down, cleans, rebuilds, and restarts"

# --- up/start create declared deploy-ssh folders (0700) and print a notice -------------------
# ST-11: a missing deploy folder must be created before the runner containers start, with a
# notice, and the lifecycle command must still run. Removing the folder again must make the next
# container-starting command recreate it.
S="${T}/deploy-ssh-create"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
: > "${S}/trace"
run_fleet "${S}" up >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "up should create the missing deploy-ssh folder and continue"
}
[ -d "${S}/deploy-ssh/alpha" ] || fail "up must create deploy-ssh/alpha"
[ -d "${S}/deploy-ssh/alpha/keys" ] || fail "up must create deploy-ssh/alpha/keys"
[ "$(stat -c '%a' "${S}/deploy-ssh/alpha")" = "700" ] || fail "deploy-ssh/alpha must be 0700"
[ "$(stat -c '%a' "${S}/deploy-ssh/alpha/keys")" = "700" ] ||
    fail "deploy-ssh/alpha/keys must be 0700"
grep -q 'created deploy-ssh/alpha' "${S}/out" || fail "up must announce the created deploy folder"
grep -q 'up -d' "${S}/trace" || fail "up must still start the fleet after creating the folder"

rm -rf "${S}/deploy-ssh/alpha"
: > "${S}/trace"
run_fleet "${S}" start >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "start should recreate the missing deploy-ssh folder and continue"
}
[ -d "${S}/deploy-ssh/alpha" ] || fail "start must recreate deploy-ssh/alpha"
[ -d "${S}/deploy-ssh/alpha/keys" ] || fail "start must recreate deploy-ssh/alpha/keys"
[ "$(stat -c '%a' "${S}/deploy-ssh/alpha")" = "700" ] ||
    fail "recreated deploy-ssh/alpha must be 0700"
[ "$(stat -c '%a' "${S}/deploy-ssh/alpha/keys")" = "700" ] ||
    fail "recreated deploy-ssh/alpha/keys must be 0700"
grep -q 'created deploy-ssh/alpha' "${S}/out" ||
    fail "start must announce the recreated deploy folder"
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml start' "${S}/trace" ||
    fail "start must still start the fleet after creating the folder"
echo "PASS: up and start create deploy-ssh folders with 0700 and a notice"

# --- generate and status never create deploy-ssh folders -------------------------------------
# ST-12: side-effect-free commands must not create declared deploy folders.
S="${T}/deploy-ssh-readonly"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
set +e
run_fleet "${S}" generate >"${S}/out" 2>&1
run_fleet "${S}" status >"${S}/out" 2>&1
set -e
[ ! -e "${S}/deploy-ssh/alpha" ] || fail "generate/status must not create deploy-ssh/alpha"
echo "PASS: generate and status never create deploy-ssh folders"

# --- down never deletes deploy-ssh folders or their contents ---------------------------------
# ST-13: teardown must leave declared deploy folders untouched.
S="${T}/deploy-ssh-preserve"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
mkdir -p "${S}/deploy-ssh/alpha"
printf 'secret\n' > "${S}/deploy-ssh/alpha/keep.txt"
set +e
CURL_BODY='{"total_count":0,"runners":[]}' CURL_HTTP_CODE=200 run_fleet "${S}" down >"${S}/out" 2>&1
set -e
[ -d "${S}/deploy-ssh/alpha" ] || fail "down must not delete deploy-ssh/alpha"
[ "$(cat "${S}/deploy-ssh/alpha/keep.txt")" = "secret" ] ||
    fail "down must not delete files inside deploy-ssh/alpha"
echo "PASS: down preserves deploy-ssh folders and their contents"

echo "fleet spec tests: PASS"
