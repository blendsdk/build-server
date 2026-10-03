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
    printf '#!/bin/bash\nprintf "docker %%s\\n" "$*" >> "${TRACE}"\nexit "${DOCKER_EXIT:-0}"\n' \
        > "${dir}/bin/docker"
    # shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
    printf '#!/bin/bash\nprintf "curl %%s\\n" "$*" >> "${TRACE}"\nprintf "%%s" "${CURL_BODY:-}"\nprintf "\\n%%s" "${CURL_HTTP_CODE:-200}"\nexit "${CURL_EXIT:-0}"\n' \
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
        CURL_HTTP_CODE="${CURL_HTTP_CODE:-200}" DOCKER_EXIT="${DOCKER_EXIT:-0}" bash fleet.sh "$@")
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
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml up -d --no-deps beta_1' "${S}/trace" ||
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
grep -qF -- 'up -d --no-deps alpha_1' "${S}/trace" || fail "targeted recreate missing"
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
done < <(grep -n 'compose' "${S}/trace" | cut -d: -f1)
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
for expected in "Alpha" "alpha_1" "beta_1" "runner-image-beta" "Runner version: 9.9.9"; do
    grep -qF "${expected}" "${S}/out" || fail "status output missing '${expected}'"
done
echo "PASS: status reports the fleet and the pinned version"

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

echo "fleet spec tests: PASS"
