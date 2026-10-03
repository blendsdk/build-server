#!/bin/bash
# Specification tests for the fleet configuration parser and compose generator.
#
# Each case runs a sandbox copy of fleet.sh with a fixture orgs.conf, then inspects the generated
# YAML through `docker compose config --format json`, or checks the command's exit status and
# message for validation errors.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Build a sandbox root: the script under test plus an empty compose base it is merged with.
new_sandbox() {
    local dir="$1"
    mkdir -p "${dir}"
    cp "${ROOT}/fleet.sh" "${dir}/fleet.sh"
    printf 'services: {}\n' > "${dir}/docker-compose.yml"
}

# Render and normalize the generated model to JSON.
render_json() {
    local dir="$1"
    (cd "${dir}" && ACCESS_TOKEN=dummy bash fleet.sh generate) >"${dir}/generate.out" 2>&1 ||
        {
            cat "${dir}/generate.out" >&2
            fail "generate should succeed in ${dir}"
        }
    ACCESS_TOKEN=dummy docker compose -f "${dir}/docker-compose.yml" \
        -f "${dir}/docker-compose.generated.yml" config --format json
}

# Run a fixture expected to fail validation; assert a non-zero exit, no output file, and the
# expected message.
run_bad() {
    (cd "$1" && ACCESS_TOKEN=dummy bash fleet.sh generate) >"$1/out" 2>&1
}

expect_fail() {
    local dir="$1" label="$2" pattern="$3"
    if run_bad "${dir}"; then
        fail "${label}: expected non-zero exit"
    fi
    [ ! -f "${dir}/docker-compose.generated.yml" ] || fail "${label}: output file was written"
    grep -qF "${pattern}" "${dir}/out" || {
        cat "${dir}/out" >&2
        fail "${label}: expected message containing '${pattern}'"
    }
}

# --- Valid config renders slug-derived services and prints a summary ----------------------
S="${T}/valid"
new_sandbox "${S}"
cat > "${S}/orgs.conf" <<'EOF'
# fleet organizations
AcmeTools

Globex
Foo-Bar
EOF
MODEL="$(render_json "${S}")"
[ "$(jq -r '.services | length' <<<"${MODEL}")" -eq 3 ] || fail "expected three services"
for pair in "acmetools:AcmeTools" "globex:Globex" "foobar:Foo-Bar"; do
    svc="${pair%%:*}"
    org="${pair#*:}"
    [ "$(jq -r --arg s "${svc}" '.services[$s].environment.ORGANIZATION' <<<"${MODEL}")" = "${org}" ] ||
        fail "missing or wrong organization for ${svc}"
    [ "$(jq -r --arg s "${svc}" '.services[$s].hostname' <<<"${MODEL}")" = "${svc}_runner_1" ] ||
        fail "wrong hostname for ${svc}"
    [ "$(jq -r --arg s "${svc}" '.services[$s].container_name' <<<"${MODEL}")" = "null" ] ||
        fail "${svc} must not pin a global container name"
done
grep -q 'generated' "${S}/generate.out" || fail "expected a summary on stdout"
echo "PASS: valid config renders slug-derived services with a summary"

# --- URL defaults and GHES derivation (scheme+authority, port preserved) -------------------
S="${T}/urls"
new_sandbox "${S}"
cat > "${S}/orgs.conf" <<'EOF'
PlainOrg
GheOrg url=https://ghe.example.com:8443/GheCorp
CaseOrg url=https://GitHub.COM:443/CaseOrg
EOF
MODEL="$(render_json "${S}")"
[ "$(jq -r '.services.plainorg.environment.GITHUB_URL' <<<"${MODEL}")" = "https://github.com/PlainOrg" ] ||
    fail "default GITHUB_URL wrong"
[ "$(jq -r '.services.plainorg.environment.GITHUB_API_URL' <<<"${MODEL}")" = "https://api.github.com" ] ||
    fail "default GITHUB_API_URL wrong"
[ "$(jq -r '.services.gheorg.environment.GITHUB_URL' <<<"${MODEL}")" = "https://ghe.example.com:8443/GheCorp" ] ||
    fail "custom GITHUB_URL wrong"
[ "$(jq -r '.services.gheorg.environment.GITHUB_API_URL' <<<"${MODEL}")" = "https://ghe.example.com:8443/api/v3" ] ||
    fail "custom GITHUB_API_URL derivation wrong"
[ "$(jq -r '.services.caseorg.environment.GITHUB_API_URL' <<<"${MODEL}")" = "https://api.github.com" ] ||
    fail "case/port github.com normalization wrong"
echo "PASS: URL defaults, GHES derivation, and github.com normalization"

# --- Context selects the custom image; others use the default -----------------------------
S="${T}/context"
new_sandbox "${S}"
mkdir -p "${S}/orgs/custom"
printf 'FROM scratch\n' > "${S}/orgs/custom/Dockerfile"
cat > "${S}/orgs.conf" <<'EOF'
CustomOrg context=orgs/custom
DefaultOrg
EOF
MODEL="$(render_json "${S}")"
[ "$(jq -r '.services.customorg.image' <<<"${MODEL}")" = "runner-image-customorg" ] ||
    fail "custom image wrong"
[ "$(jq -r '.services.defaultorg.image' <<<"${MODEL}")" = "runner-image" ] ||
    fail "default image wrong"
echo "PASS: context selects the custom image"

# --- build_temp is scoped to its org ------------------------------------------------------
S="${T}/buildtemp"
new_sandbox "${S}"
cat > "${S}/orgs.conf" <<'EOF'
WithTemp build_temp=1
WithoutTemp
EOF
MODEL="$(render_json "${S}")"
WITH="$(jq -r '.services.withtemp.volumes[]?.target' <<<"${MODEL}")"
WITHOUT="$(jq -r '.services.withouttemp.volumes[]?.target' <<<"${MODEL}")"
[ "${WITH}" = "/build-temp" ] || fail "withtemp must mount /build-temp (got ${WITH})"
[ -z "${WITHOUT}" ] || fail "withouttemp must not mount build-temp (got ${WITHOUT})"
echo "PASS: build_temp is scoped to its org"

# --- Validation failures name the line and write nothing -----------------------------------
S="${T}/badkey"; new_sandbox "${S}"
printf 'GoodOrg\nBadOrg bogus=1\n' > "${S}/orgs.conf"
expect_fail "${S}" "unknown option" "orgs.conf:2: unknown option 'bogus'"

S="${T}/malformed"; new_sandbox "${S}"
printf 'GoodOrg\nBroken line here\n' > "${S}/orgs.conf"
expect_fail "${S}" "malformed line" "orgs.conf:2: malformed option 'line'"

S="${T}/duplicate"; new_sandbox "${S}"
printf 'DupOrg\nDupOrg\n' > "${S}/orgs.conf"
expect_fail "${S}" "duplicate organization" "orgs.conf:2: duplicate organization 'DupOrg'"

S="${T}/empty"; new_sandbox "${S}"
printf '# only comments\n\n' > "${S}/orgs.conf"
expect_fail "${S}" "zero organizations" "no organizations defined"

S="${T}/badname"; new_sandbox "${S}"
printf 'Bad!Org\n' > "${S}/orgs.conf"
expect_fail "${S}" "invalid name" "orgs.conf:1: invalid organization name 'Bad!Org'"
echo "PASS: validation failures name the offending line"

# --- Context presence, containment, and Dockerfile -----------------------------------------
S="${T}/missingctx"; new_sandbox "${S}"
printf 'Missing context=does/not/exist\n' > "${S}/orgs.conf"
expect_fail "${S}" "missing context" "orgs.conf:1: context 'does/not/exist' does not exist"

S="${T}/nodockerfile"; new_sandbox "${S}"
mkdir -p "${S}/orgs/nodockerfile"
printf 'NoDockerfile context=orgs/nodockerfile\n' > "${S}/orgs.conf"
expect_fail "${S}" "context without Dockerfile" "orgs.conf:1: context 'orgs/nodockerfile' has no Dockerfile"

S="${T}/traversal"; new_sandbox "${S}"
printf 'Traversal context=..\n' > "${S}/orgs.conf"
expect_fail "${S}" "parent traversal" "orgs.conf:1: context '..' resolves outside the repository"

S="${T}/symlink"; new_sandbox "${S}"
mkdir -p "${T}/outside/ctx"
printf 'FROM scratch\n' > "${T}/outside/ctx/Dockerfile"
ln -sfn "${T}/outside/ctx" "${S}/escape"
printf 'Escape context=escape\n' > "${S}/orgs.conf"
expect_fail "${S}" "symlink escape" "orgs.conf:1: context 'escape' resolves outside the repository"

S="${T}/globliteral"; new_sandbox "${S}"
mkdir -p "${S}/orgs/glo1" "${S}/orgs/glo2"
printf 'GlobOrg context=orgs/glo*\n' > "${S}/orgs.conf"
expect_fail "${S}" "literal glob option" "orgs.conf:1: context 'orgs/glo*' does not exist"
echo "PASS: context validation covers presence, containment, and Dockerfile"

# --- URL shapes and slug validation ---------------------------------------------------------
S="${T}/http"; new_sandbox "${S}"
printf 'HttpOrg url=http://example.com/HttpOrg\n' > "${S}/orgs.conf"
expect_fail "${S}" "http scheme" "orgs.conf:1: url must start with https://"

S="${T}/userinfo"; new_sandbox "${S}"
printf 'UserInfo url=https://u:p@example.com/UserInfo\n' > "${S}/orgs.conf"
expect_fail "${S}" "userinfo" "orgs.conf:1: url must not contain userinfo, query, or fragment"

S="${T}/query"; new_sandbox "${S}"
printf 'Query url=https://example.com/Query?x=1\n' > "${S}/orgs.conf"
expect_fail "${S}" "query" "orgs.conf:1: url must not contain userinfo, query, or fragment"

S="${T}/fragment"; new_sandbox "${S}"
printf 'Fragment url=https://example.com/Fragment#top\n' > "${S}/orgs.conf"
expect_fail "${S}" "fragment" "orgs.conf:1: url must not contain userinfo, query, or fragment"

S="${T}/slugcollision"; new_sandbox "${S}"
printf 'Foo.Bar\nFoo-Bar\n' > "${S}/orgs.conf"
expect_fail "${S}" "slug collision" "orgs.conf:2: slug 'foobar' collides with organization 'Foo.Bar'"

S="${T}/emptyslug"; new_sandbox "${S}"
printf '...\n' > "${S}/orgs.conf"
expect_fail "${S}" "empty slug" "orgs.conf:1: organization '...' has an empty slug"
echo "PASS: URL shapes and slug validation"

echo "orgs spec tests: PASS"
