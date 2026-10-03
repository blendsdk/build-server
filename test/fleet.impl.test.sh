#!/bin/bash
# Implementation tests for fleet.sh.
#
# Covers internals the specification tests do not pin: byte-identical idempotence, the atomic
# temp file, preservation of the previous output when generation fails, and whitespace/comment
# handling in orgs.conf.
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
grep -q '^  alpha_1:$' "${S}/docker-compose.generated.yml" || fail "Alpha service missing"
grep -q '^  beta_1:$' "${S}/docker-compose.generated.yml" || fail "Beta service missing"
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
for expected in "Alpha" "alpha_1" "alpha_runner_1" "runner-image" "Runner version:" "alpha-container"; do
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

echo "fleet impl tests: PASS"
