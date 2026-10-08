#!/bin/bash
# Implementation tests for fleet.sh.
#
# Covers internals the specification tests do not pin: byte-identical idempotence, the atomic
# temp file, preservation of the previous output when generation fails, whitespace/comment
# handling in orgs.conf, and the deploy_ssh folder lifecycle (auto-creation on the remaining
# container-starting commands, idempotent rendering, preservation of operator material, starter
# file seeding, and real-ssh-keygen key generation).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

new_sandbox() {
    local dir="$1"
    mkdir -p "${dir}"
    cp "${ROOT}/fleet.sh" "${dir}/fleet.sh"
    printf 'services: {}\n' > "${dir}/docker-compose.yml"
}

run_generate() {
    local dir="$1"
    (cd "${dir}" && ACCESS_TOKEN=dummy bash fleet.sh generate)
}

# Add stub docker and curl binaries on PATH for a sandbox. Every invocation is appended to the
# sandbox trace; the stubs default to success, so lifecycle commands run without a Docker host.
stub_tools() {
    local dir="$1"
    mkdir -p "${dir}/bin" "${dir}/home"
    # shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
    printf '#!/bin/bash\nprintf "docker %%s\\n" "$*" >> "${TRACE}"\ncase "$*" in\n    *"container inspect"*) printf "%%s\\n" "${LEGACY_PROJECT:-}"; exit "${INSPECT_EXIT:-0}" ;;\n    *"image inspect"*) exit "${IMAGE_INSPECT_EXIT:-0}" ;;\nesac\nexit "${DOCKER_EXIT:-0}"\n' \
        > "${dir}/bin/docker"
    # shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
    printf '#!/bin/bash\nprintf "curl %%s\\n" "$*" >> "${TRACE}"\ncase "$*" in\n    *"-X DELETE"*) code="${DELETE_HTTP_CODE:-204}" ;;\n    *) code="${CURL_HTTP_CODE:-200}" ;;\nesac\ncase "$*" in\n    *"-o /dev/null"*) printf "%%s" "${code}" ;;\n    *) printf "%%s\\n%%s" "${CURL_BODY:-}" "${code}" ;;\nesac\nexit "${CURL_EXIT:-0}"\n' \
        > "${dir}/bin/curl"
    chmod +x "${dir}/bin/docker" "${dir}/bin/curl"
}

# Run a fleet command in a sandbox with the stub tools, an isolated HOME (so no real SSH material
# is ever staged), and a deterministic token and trace file.
run_fleet() {
    local dir="$1"
    shift
    (cd "${dir}" && HOME="${dir}/home" ACCESS_TOKEN=dummy TRACE="${dir}/trace" \
        PATH="${dir}/bin:${PATH}" CURL_BODY="${CURL_BODY:-}" CURL_EXIT="${CURL_EXIT:-0}" \
        CURL_HTTP_CODE="${CURL_HTTP_CODE:-200}" DOCKER_EXIT="${DOCKER_EXIT:-0}" \
        IMAGE_INSPECT_EXIT="${IMAGE_INSPECT_EXIT:-0}" bash fleet.sh "$@")
}

# Assert that a declared deploy folder was auto-created with restricted modes.
assert_deploy_created() {
    local dir="$1"
    [ -d "${dir}/deploy-ssh/alpha" ] || fail "deploy-ssh/alpha was not created"
    [ -d "${dir}/deploy-ssh/alpha/keys" ] || fail "deploy-ssh/alpha/keys was not created"
    [ "$(stat -c '%a' "${dir}/deploy-ssh/alpha")" = "700" ] || fail "deploy-ssh/alpha must be 0700"
    [ "$(stat -c '%a' "${dir}/deploy-ssh/alpha/keys")" = "700" ] ||
        fail "deploy-ssh/alpha/keys must be 0700"
}

# --- Idempotence: same input renders byte-identical output --------------------------------
S="${T}/idem"
new_sandbox "${S}"
printf 'Alpha\nBeta build_temp=1\n' > "${S}/orgs.conf"
run_generate "${S}" >/dev/null
FIRST="$(sha256sum "${S}/docker-compose.generated.yml" | cut -d' ' -f1)"
run_generate "${S}" >/dev/null
SECOND="$(sha256sum "${S}/docker-compose.generated.yml" | cut -d' ' -f1)"
[ "${FIRST}" = "${SECOND}" ] || fail "generation is not byte-identical"
echo "PASS: generation is idempotent"

# --- Atomic write: no temp file remains after success --------------------------------------
[ -z "$(find "${S}" -maxdepth 1 -name '*.tmp' -print -quit)" ] || fail "temp file left behind"
echo "PASS: no temp file remains after generation"

# --- Parse failure preserves the previous output -------------------------------------------
cp "${S}/docker-compose.generated.yml" "${S}/before.yml"
printf 'Broken line here\n' > "${S}/orgs.conf"
if run_generate "${S}" >/dev/null 2>&1; then
    fail "invalid config should fail"
fi
cmp -s "${S}/before.yml" "${S}/docker-compose.generated.yml" || fail "previous output was modified on failure"
echo "PASS: parse failure preserves the previous output"

# --- Render failure cleans the temp file and preserves the previous output ------------------
S="${T}/renderfail"
new_sandbox "${S}"
printf 'Alpha\n' > "${S}/orgs.conf"
run_generate "${S}" >/dev/null
cp "${S}/docker-compose.generated.yml" "${S}/before.yml"
mkdir -p "${S}/bin"
printf '#!/bin/bash\nexit 1\n' > "${S}/bin/mv"
chmod +x "${S}/bin/mv"
if (cd "${S}" && PATH="${S}/bin:${PATH}" ACCESS_TOKEN=dummy bash fleet.sh generate) >/dev/null 2>&1; then
    fail "render failure should fail the command"
fi
[ -z "$(find "${S}" -maxdepth 1 -name '*.tmp' -print -quit)" ] || fail "temp file left behind after a failed render"
cmp -s "${S}/before.yml" "${S}/docker-compose.generated.yml" || fail "previous output was modified by a failed render"
echo "PASS: render failure cleans up and preserves the previous output"

# --- Whitespace and comments ----------------------------------------------------------------
S="${T}/format"
new_sandbox "${S}"
cat > "${S}/orgs.conf" <<'EOF'
   # indented comment
Alpha   

Beta
EOF
run_generate "${S}" >/dev/null
grep -q '^  alpha:$' "${S}/docker-compose.generated.yml" || fail "Alpha service missing"
grep -q '^  beta:$' "${S}/docker-compose.generated.yml" || fail "Beta service missing"
echo "PASS: whitespace and full-line comments are handled"

# --- status prints the fleet and compose state ----------------------------------------------
S="${T}/status"
new_sandbox "${S}"
printf 'Alpha\n' > "${S}/orgs.conf"
mkdir -p "${S}/bin"
cat > "${S}/bin/docker" <<'EOF'
#!/bin/bash
printf 'docker %s\n' "$*" >> "${TRACE}"
case "$*" in
    *" ps"*) echo "alpha-container running" ;;
esac
exit 0
EOF
chmod +x "${S}/bin/docker"
: > "${S}/trace"
(cd "${S}" && ACCESS_TOKEN=dummy PATH="${S}/bin:${PATH}" TRACE="${S}/trace" bash fleet.sh status) >"${S}/out" 2>&1 ||
    fail "status should succeed with a stubbed docker"
for expected in "Alpha" "alpha" "alpha_runner_1" "runner-image" "Runner version:" "alpha-container"; do
    grep -qF "${expected}" "${S}/out" || fail "status output missing '${expected}'"
done
grep -qF -- '-f docker-compose.yml -f docker-compose.generated.yml ps' "${S}/trace" ||
    fail "status must query the merged compose model"
echo "PASS: status prints the fleet and compose state"

# --- Invocation from another working directory ----------------------------------------------
S="${T}/cwd"
new_sandbox "${S}"
printf 'Alpha\n' > "${S}/orgs.conf"
(cd "${T}" && ACCESS_TOKEN=dummy bash "${S}/fleet.sh" generate) >/dev/null 2>&1 ||
    fail "generate should work from another working directory"
[ -f "${S}/docker-compose.generated.yml" ] || fail "generated file not written in the script root"
echo "PASS: fleet.sh runs from any working directory"

# --- Staged files use restricted modes ------------------------------------------------------
S="${T}/modes"
new_sandbox "${S}"
printf 'Alpha\nBeta context=orgs/beta\n' > "${S}/orgs.conf"
mkdir -p "${S}/orgs/beta" "${S}/home/.ssh" "${S}/bin"
printf 'FROM scratch\n' > "${S}/orgs/beta/Dockerfile"
printf 'ARG RUNNER_VERSION="1.2.3"\n' > "${S}/Dockerfile"
printf 'key' > "${S}/home/.ssh/id_rsa"
printf 'token' > "${S}/.npmrc"
cat > "${S}/bin/docker" <<'EOF'
#!/bin/bash
context="${@: -1}"
{
    printf 'staging-root %s\n' "$(stat -c '%a' "$(dirname "${context}")" 2>/dev/null)"
    printf 'ssh-dir %s\n' "$(stat -c '%a' "${context}/ssh" 2>/dev/null)"
    printf 'ssh-key %s\n' "$(stat -c '%a' "${context}/ssh/id_rsa" 2>/dev/null)"
    printf 'npmrc %s\n' "$(stat -c '%a' "${context}/.npmrc" 2>/dev/null)"
} >> "${TRACE}"
exit 0
EOF
chmod +x "${S}/bin/docker"
: > "${S}/trace"
(cd "${S}" && HOME="${S}/home" ACCESS_TOKEN=dummy TRACE="${S}/trace" PATH="${S}/bin:${PATH}" bash fleet.sh build Beta) >/dev/null 2>&1 ||
    fail "custom build should succeed"
grep -q '^staging-root 700$' "${S}/trace" || fail "staging root must be 0700"
grep -q '^ssh-dir 700$' "${S}/trace" || fail "staged ssh directory must be 0700"
grep -q '^ssh-key 600$' "${S}/trace" || fail "staged ssh key must be 0600"
grep -q '^npmrc 600$' "${S}/trace" || fail "staged credentials must be 0600"
for leaked in ssh .npmrc .yarnrc .bunfig.toml config.json; do
    [ ! -e "${S}/orgs/beta/${leaked}" ] || fail "credential material leaked into the context: ${leaked}"
done
echo "PASS: staged files use restricted modes and never touch the context"

# --- Version precedence: state file over Dockerfile ARG -------------------------------------
S="${T}/precedence"
new_sandbox "${S}"
printf 'Alpha\n' > "${S}/orgs.conf"
printf 'ARG RUNNER_VERSION="1.2.3"\n' > "${S}/Dockerfile"
mkdir -p "${S}/home/.ssh" "${S}/bin"
printf 'key' > "${S}/home/.ssh/id_rsa"
# shellcheck disable=SC2016  # the placeholder text must stay literal in the generated stub
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${TRACE}"\nexit 0\n' > "${S}/bin/docker"
chmod +x "${S}/bin/docker"
printf '5.5.5\n' > "${S}/.runner-version"
: > "${S}/trace"
(cd "${S}" && HOME="${S}/home" ACCESS_TOKEN=dummy TRACE="${S}/trace" PATH="${S}/bin:${PATH}" bash fleet.sh build) >/dev/null 2>&1 ||
    fail "build with a pinned version should succeed"
grep -q -- '--build-arg RUNNER_VERSION=5.5.5' "${S}/trace" || fail "state file version must win"
rm "${S}/.runner-version"
: > "${S}/trace"
(cd "${S}" && HOME="${S}/home" ACCESS_TOKEN=dummy TRACE="${S}/trace" PATH="${S}/bin:${PATH}" bash fleet.sh build) >/dev/null 2>&1 ||
    fail "build without a pinned version should succeed"
grep -q -- '--build-arg RUNNER_VERSION=1.2.3' "${S}/trace" || fail "Dockerfile ARG fallback missing"
echo "PASS: version precedence is state file then Dockerfile"

# --- deploy_ssh: restart creates a missing declared folder ----------------------------------
# The remaining container-starting commands must create a missing declared folder (with keys/) at
# 0700 before starting runners, like up/start. `restart` also requires the runner image to exist.
S="${T}/autocreate-restart"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" restart >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "restart should create the deploy folder and continue"
}
assert_deploy_created "${S}"
echo "PASS: restart creates missing deploy-ssh folders with 0700"

# --- deploy_ssh: update <org> creates a missing declared folder -----------------------------
S="${T}/autocreate-update"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" update Alpha >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "update should create the deploy folder and continue"
}
assert_deploy_created "${S}"
echo "PASS: update <org> creates missing deploy-ssh folders with 0700"

# --- deploy_ssh: update-runners creates a missing declared folder ---------------------------
S="${T}/autocreate-update-runners"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
CURL_BODY='{"tag_name":"v9.9.9"}' run_fleet "${S}" update-runners >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "update-runners should create the deploy folder and continue"
}
assert_deploy_created "${S}"
echo "PASS: update-runners creates missing deploy-ssh folders with 0700"

# --- deploy_ssh: upgrade-all creates a missing declared folder -------------------------------
S="${T}/autocreate-upgrade-all"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
CURL_BODY='{"tag_name":"v9.9.9"}' run_fleet "${S}" upgrade-all --yes >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "upgrade-all should create the deploy folder and continue"
}
assert_deploy_created "${S}"
echo "PASS: upgrade-all creates missing deploy-ssh folders with 0700"

# --- deploy_ssh: the creation notice is silent when nothing was created -----------------------
# Running a container-starting command again, or repairing only a missing keys/ directory, must
# not announce a folder creation: the notice marks folder creation only.
S="${T}/autocreate-notice"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" up >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "up should create the deploy folder and continue"
}
grep -q 'created deploy-ssh/alpha' "${S}/out" || fail "the first up must announce the created folder"

run_fleet "${S}" up >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "a second up should succeed"
}
grep -q 'created deploy-ssh/alpha' "${S}/out" && fail "an existing folder must not be announced again"

rm -rf "${S}/deploy-ssh/alpha/keys"
run_fleet "${S}" up >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "up with only keys/ missing should succeed"
}
[ -d "${S}/deploy-ssh/alpha/keys" ] || fail "up must restore a missing keys/ directory"
grep -q 'created deploy-ssh/alpha' "${S}/out" &&
    fail "a keys-only repair must not print the folder-creation notice"
echo "PASS: the creation notice appears only when the folder itself is created"

# --- deploy_ssh: rendering stays byte-identical across runs ----------------------------------
S="${T}/deploy-idem"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\nBeta build_temp=1\n' > "${S}/orgs.conf"
run_generate "${S}" >/dev/null
FIRST="$(sha256sum "${S}/docker-compose.generated.yml" | cut -d' ' -f1)"
run_generate "${S}" >/dev/null
SECOND="$(sha256sum "${S}/docker-compose.generated.yml" | cut -d' ' -f1)"
[ "${FIRST}" = "${SECOND}" ] || fail "deploy_ssh rendering is not byte-identical"
echo "PASS: deploy_ssh rendering is idempotent"

# --- deploy_ssh: an invalid value preserves the previous output -----------------------------
# Validation fails before rendering, so the previous generated file must stay byte-identical and
# no temp file may be left behind.
S="${T}/deploy-invalid"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
run_generate "${S}" >/dev/null
cp "${S}/docker-compose.generated.yml" "${S}/before.yml"
printf 'Alpha deploy_ssh=../escape\n' > "${S}/orgs.conf"
if run_generate "${S}" >/dev/null 2>&1; then
    fail "an escaping deploy_ssh value should fail generation"
fi
cmp -s "${S}/before.yml" "${S}/docker-compose.generated.yml" ||
    fail "previous output was modified by an invalid deploy_ssh value"
[ -z "$(find "${S}" -maxdepth 1 -name '*.tmp' -print -quit)" ] ||
    fail "temp file left behind after an invalid deploy_ssh value"
echo "PASS: an invalid deploy_ssh value preserves the previous output and leaves no temp file"

# --- deploy_ssh: clean never touches operator material ---------------------------------------
S="${T}/deploy-preserve-clean"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
mkdir -p "${S}/deploy-ssh/alpha/keys"
printf 'secret\n' > "${S}/deploy-ssh/alpha/keep.txt"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" clean --yes >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "clean --yes should succeed"
}
[ -d "${S}/deploy-ssh/alpha" ] || fail "clean must not delete deploy-ssh/alpha"
[ -d "${S}/deploy-ssh/alpha/keys" ] || fail "clean must not delete deploy-ssh/alpha/keys"
[ "$(cat "${S}/deploy-ssh/alpha/keep.txt")" = "secret" ] ||
    fail "clean must not delete files inside deploy-ssh/alpha"
echo "PASS: clean --yes preserves deploy-ssh folders and contents"

# --- deploy_ssh: upgrade-all never touches operator material ---------------------------------
S="${T}/deploy-preserve-upgrade-all"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
mkdir -p "${S}/deploy-ssh/alpha/keys"
printf 'secret\n' > "${S}/deploy-ssh/alpha/keep.txt"
stub_tools "${S}"
: > "${S}/trace"
CURL_BODY='{"tag_name":"v9.9.9"}' run_fleet "${S}" upgrade-all --yes >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "upgrade-all --yes should succeed"
}
[ -d "${S}/deploy-ssh/alpha" ] || fail "upgrade-all must not delete deploy-ssh/alpha"
[ -d "${S}/deploy-ssh/alpha/keys" ] || fail "upgrade-all must not delete deploy-ssh/alpha/keys"
[ "$(cat "${S}/deploy-ssh/alpha/keep.txt")" = "secret" ] ||
    fail "upgrade-all must not delete files inside deploy-ssh/alpha"
echo "PASS: upgrade-all --yes preserves deploy-ssh folders and contents"

# --- keygen (real ssh-keygen): a valid matching pair with restricted modes --------------------
S="${T}/keygen-real"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" keygen Alpha >"${S}/out" 2>&1 || {
    cat "${S}/out" >&2
    fail "keygen with the real ssh-keygen should succeed"
}
KEY="${S}/deploy-ssh/alpha/keys/id_ed25519"
[ -f "${KEY}" ] || fail "keygen must create the private key"
[ -f "${KEY}.pub" ] || fail "keygen must create the public key"
[ "$(stat -c '%a' "${KEY}")" = "600" ] || fail "the private key must be 0600"
grep -q 'BEGIN OPENSSH PRIVATE KEY' "${KEY}" || fail "the private key must be a real OpenSSH key"
DERIVED="$(ssh-keygen -y -f "${KEY}" | awk '{print $1" "$2}')"
PUB_FIELDS="$(awk '{print $1" "$2}' "${KEY}.pub")"
[ "${DERIVED}" = "${PUB_FIELDS}" ] || fail "the public key must match the private key"
case "${DERIVED}" in
    ssh-ed25519\ *) ;;
    *) fail "the default key must be ed25519" ;;
esac
echo "PASS: keygen produces a valid matching pair with 0600"

# --- starter files are byte-identical across provisioning runs --------------------------------
S="${T}/seed-idempotent"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" up >/dev/null 2>&1 || fail "the first up must seed the deploy folder"
cp "${S}/deploy-ssh/alpha/config" "${S}/config.first"
cp "${S}/deploy-ssh/alpha/known_hosts" "${S}/known_hosts.first"
run_fleet "${S}" up >"${S}/out" 2>&1 || fail "the second up must succeed"
cmp -s "${S}/config.first" "${S}/deploy-ssh/alpha/config" ||
    fail "the starter config must stay byte-identical"
cmp -s "${S}/known_hosts.first" "${S}/deploy-ssh/alpha/known_hosts" ||
    fail "the seeded known_hosts must stay byte-identical"
grep -q 'created deploy-ssh/alpha' "${S}/out" &&
    fail "the second up must not announce a creation"
echo "PASS: starter files are byte-identical across provisioning runs"

# --- keygen --force replaces a real pair; a refusal preserves it ------------------------------
S="${T}/keygen-force"
new_sandbox "${S}"
printf 'Alpha deploy_ssh=deploy-ssh/alpha\n' > "${S}/orgs.conf"
stub_tools "${S}"
: > "${S}/trace"
run_fleet "${S}" keygen Alpha >/dev/null 2>&1 || fail "the first keygen must succeed"
KEY="${S}/deploy-ssh/alpha/keys/id_ed25519"
cp "${KEY}.pub" "${S}/pub.first"
set +e
run_fleet "${S}" keygen Alpha >"${S}/out" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "the second keygen must refuse to overwrite"
cmp -s "${S}/pub.first" "${KEY}.pub" || fail "a refused keygen must preserve the pair"
run_fleet "${S}" keygen Alpha --force >/dev/null 2>&1 || fail "keygen --force must replace the pair"
cmp -s "${S}/pub.first" "${KEY}.pub" && fail "keygen --force must generate a new pair"
DERIVED="$(ssh-keygen -y -f "${KEY}" | awk '{print $1" "$2}')"
PUB_FIELDS="$(awk '{print $1" "$2}' "${KEY}.pub")"
[ "${DERIVED}" = "${PUB_FIELDS}" ] || fail "the forced pair must be valid"
echo "PASS: keygen refuses to overwrite and --force replaces the pair"

echo "fleet impl tests: PASS"
