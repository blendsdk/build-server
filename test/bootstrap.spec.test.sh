#!/bin/bash
# Specification tests for the fresh-host bootstrap installer.
#
# Every external command is stubbed on PATH so nothing is installed, cloned, built, or started.
# The tests assert the documented setup behavior: required secrets, the generated host files,
# idempotent reruns, and the start sequence.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Create a stub command directory shared by the tests.
make_stubs() {
    local bin="$1"
    mkdir -p "${bin}"

    # sudo passes through.
    printf '#!/bin/bash\nexec "$@"\n' > "${bin}/sudo"

    # git records calls; a clone populates the target with a fake repository tree, and
    # rev-parse reports a fixed revision.
    cat > "${bin}/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >> "${TRACE}"

populate_fake_repo() {
    dir="$1"
    mkdir -p "${dir}/.git" "${dir}/test" "${dir}/docs" "${dir}/codeops" "${dir}/.opencode/skills" \
        "${dir}/node_modules/pkg" "${dir}/examples/runner-custom"
    cat > "${dir}/fleet.sh" <<'FLEET'
#!/bin/bash
printf 'fleet %s\n' "$*" >> "${TRACE}"
if [ "${FAKE_FLEET_FAIL_UP:-0}" = "1" ] && [ "${1:-}" = "up" ]; then
    exit 1
fi
exit 0
FLEET
    chmod +x "${dir}/fleet.sh"
    for file in .dockerignore bootstrap.sh deploy-ssh-check.sh docker-compose.yml Dockerfile start.sh entrypoint.sh; do
        printf 'stub %s\n' "${file}" > "${dir}/${file}"
    done
    chmod +x "${dir}/bootstrap.sh" "${dir}/deploy-ssh-check.sh" "${dir}/start.sh" "${dir}/entrypoint.sh"
    for file in package.json package-lock.json AGENTS.md; do
        printf 'dev\n' > "${dir}/${file}"
    done
    printf 'dev\n' > "${dir}/test/README.md"
    printf 'dev\n' > "${dir}/docs/index.md"
    printf 'dev\n' > "${dir}/codeops/.codeops.yml"
    printf 'dev\n' > "${dir}/.opencode/skills/example.md"
    printf 'dev\n' > "${dir}/README.md"
    printf 'dev\n' > "${dir}/LICENSE"
    printf 'dev\n' > "${dir}/examples/playground.sh"
    printf 'dev\n' > "${dir}/examples/README.md"
    printf 'dev\n' > "${dir}/examples/orgs.conf"
    printf 'FROM runner-image\n' > "${dir}/examples/runner-custom/Dockerfile"
}

if [ "${1:-}" = "-C" ]; then
    shift 2
fi
if [ "${1:-}" = "rev-parse" ]; then
    printf '%s\n' "${GIT_REVISION:-0123456789abcdef0123456789abcdef01234567}"
    exit 0
fi
is_clone=0
for arg in "$@"; do
    [ "${arg}" = "clone" ] && is_clone=1
done
if [ "${is_clone}" = "1" ]; then
    [ "${GIT_CLONE_EXIT:-0}" = "0" ] || exit "${GIT_CLONE_EXIT}"
    for last in "$@"; do :; done
    populate_fake_repo "${last}"
fi
exit 0
EOF

    # Returns a predictable temporary directory so tests can assert cleanup.
    cat > "${bin}/mktemp" <<'EOF'
#!/bin/bash
dir="${MKTEMP_TARGET:-/tmp/bootstrap-mktemp-stub}"
mkdir -p "${dir}"
printf '%s' "${dir}"
exit 0
EOF

    # docker reports a working daemon and records everything else.
    cat > "${bin}/docker" <<'EOF'
#!/bin/bash
printf 'docker %s\n' "$*" >> "${TRACE}"
if [ "${1:-}" = "info" ]; then exit 0; fi
exit 0
EOF

    cat > "${bin}/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "${TRACE}"
printf '%s' "${CURL_BODY:-}"
printf '\n%s' "${CURL_HTTP_CODE:-200}"
exit "${CURL_EXIT:-0}"
EOF

    cat > "${bin}/htpasswd" <<'EOF'
#!/bin/bash
printf 'htpasswd %s\n' "$*" >> "${TRACE}"
case "${1:-}" in
    -vb)
        [ -s "${2:-}" ] || exit 1
        exit "${HTPASSWD_VERIFY_EXIT:-0}"
        ;;
esac
printf '%s:$2y$examplehash\n' "${2:-user}"
exit 0
EOF

    # ssh-keygen creates the requested key files.
    cat > "${bin}/ssh-keygen" <<'EOF'
#!/bin/bash
printf 'ssh-keygen %s\n' "$*" >> "${TRACE}"
path=""
previous=""
for arg in "$@"; do
    [ "${previous}" = "-f" ] && path="${arg}"
    previous="${arg}"
done
if [ -n "${path}" ]; then
    printf 'private' > "${path}"
    printf 'public' > "${path}.pub"
fi
exit 0
EOF

    cat > "${bin}/apt-get" <<'EOF'
#!/bin/bash
printf 'apt-get %s\n' "$*" >> "${TRACE}"
exit 0
EOF

    cat > "${bin}/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF

    cat > "${bin}/ssh-keyscan" <<'EOF'
#!/bin/bash
printf '%s ssh-ed25519 AAAATESTKEY\n' "${1:-github.com}"
exit 0
EOF

    # Reports a listening port only when SS_BUSY_PORT names it.
    cat > "${bin}/ss" <<'EOF'
#!/bin/bash
last=""
for arg in "$@"; do last="${arg}"; done
port="${last##*:}"
if [ -n "${SS_BUSY_PORT:-}" ] && [ "${port}" = "${SS_BUSY_PORT}" ]; then
    printf 'LISTEN 0 4096 *:%s *:*\n' "${port}"
fi
exit 0
EOF

    cat > "${bin}/sg" <<'EOF'
#!/bin/bash
printf 'sg %s\n' "$*" >> "${TRACE}"
exit 0
EOF

    chmod +x "${bin}/"*
}

# Run the installer against the stubs. Tests that need no organizations pass ORGS= (empty) and
# tests that need a custom-context build use --keep-orgs.
run_bootstrap() {
    local home="$1" dir="$2"
    shift 2
    (cd "${T}" && HOME="${home}" INSTALL_DIR="${dir}" TRACE="${T}/trace" \
        ORGS="${ORGS:-ExampleOrg}" CURL_HTTP_CODE="${CURL_HTTP_CODE:-201}" \
        PATH="${T}/bin:${PATH}" bash "${ROOT}/bootstrap.sh" --non-interactive "$@")
}

# --- Required secrets fail without a value --------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-empty"
set +e
HOME="${T}/home-empty" INSTALL_DIR="${T}/empty" TRACE="${T}/trace" \
    PATH="${T}/bin:${PATH}" bash "${ROOT}/bootstrap.sh" --non-interactive --no-start \
    >"${T}/out-missing" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "missing ACCESS_TOKEN must fail"
grep -qi 'ACCESS_TOKEN' "${T}/out-missing" || fail "missing-token error should name ACCESS_TOKEN"
echo "PASS: missing secrets fail with guidance"

# --- Full setup creates the host files ------------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home" "${T}/install"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_USER=ci REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home" "${T}/install" --no-start >"${T}/out-ok" 2>&1 ||
    {
        cat "${T}/out-ok" >&2
        fail "bootstrap should succeed with all values"
    }

[ -f "${T}/install/.env" ] || fail ".env was not written"
[ "$(stat -c '%a' "${T}/install/.env")" = "600" ] || fail ".env must be 0600"
grep -q '^ACCESS_TOKEN=secret-token$' "${T}/install/.env" || fail ".env token wrong"
grep -q '^REGISTRY_HTTP_SECRET=secret-http$' "${T}/install/.env" || fail ".env secret wrong"
grep -q '^REGISTRY_USER=ci$' "${T}/install/.env" || fail ".env registry user wrong"
grep -q '^REGISTRY_PASS=secret-pass$' "${T}/install/.env" || fail ".env registry password wrong"
EXPECTED_PROJECT="$(printf '%s' "$(id -un)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-' | sed 's/^[^a-z0-9]*//')"
[ -n "${EXPECTED_PROJECT}" ] || EXPECTED_PROJECT=build-server
grep -q "^COMPOSE_PROJECT_NAME=${EXPECTED_PROJECT}$" "${T}/install/.env" ||
    fail "the Compose project name must default to the sanitized login name"

for file in .npmrc .yarnrc .bunfig.toml config.json; do
    [ -f "${T}/install/${file}" ] || fail "placeholder ${file} missing"
done
[ -s "${T}/install/registry/auth/registry.password" ] || fail "registry htpasswd missing"
[ -f "${T}/home/.ssh/id_rsa" ] || fail "deploy key not generated"
[ -f "${T}/home/.ssh/config" ] || fail "ssh config not created"
grep -q -- '--branch main' "${T}/trace" || fail "clone must target the configured branch"
grep -q 'https://github.com/blendsdk/build-server.git' "${T}/trace" || fail "clone must target the public repository"
EXPECTED_AUTH="AUTHORIZATION: Basic $(printf 'x-access-token:secret-token' | base64 -w0)"
grep -qF "${EXPECTED_AUTH}" "${T}/trace" ||
    fail "clone must authenticate with the token over HTTP basic auth"
for file in .dockerignore bootstrap.sh fleet.sh deploy-ssh-check.sh docker-compose.yml Dockerfile start.sh entrypoint.sh; do
    [ -f "${T}/install/${file}" ] || fail "runtime file ${file} was not installed"
done
[ -x "${T}/install/deploy-ssh-check.sh" ] ||
    fail "the installed deploy-ssh-check.sh must be executable"
[ -e "${T}/install/.git" ] && fail "a clean install must not contain .git"
[ -d "${T}/install/test" ] && fail "a clean install must not contain the test tree"
[ -d "${T}/install/docs" ] && fail "a clean install must not contain the docs tree"
[ -f "${T}/install/.build-server-manifest" ] || fail "the install manifest was not written"
grep -qx 'fleet.sh' "${T}/install/.build-server-manifest" || fail "the manifest must list the runtime files"
grep -qx 'deploy-ssh-check.sh' "${T}/install/.build-server-manifest" ||
    fail "the manifest must list deploy-ssh-check.sh"
grep -q '^REVISION=0123456789abcdef0123456789abcdef01234567$' "${T}/install/.build-server-version" ||
    fail "the installed revision was not recorded"
CLONE_DEST="$(grep 'git .*clone' "${T}/trace" | tail -1 | awk '{print $NF}')"
[ "${CLONE_DEST}" = "${T}/install" ] && fail "the clone must not target the install directory"
echo "PASS: full setup installs only the runtime files, credentials, keys, and htpasswd"

# --- Reruns are idempotent and preserve .env -------------------------------------------------
printf 'ACCESS_TOKEN=keep-me\n' > "${T}/install/.env"
chmod 600 "${T}/install/.env"
: > "${T}/trace"
ACCESS_TOKEN=other-token REGISTRY_HTTP_SECRET=other-http REGISTRY_PASS=other-pass \
    HTPASSWD_VERIFY_EXIT=1 \
    run_bootstrap "${T}/home" "${T}/install" --no-start >/dev/null 2>&1 ||
    fail "bootstrap rerun should succeed"
grep -q '^ACCESS_TOKEN=keep-me$' "${T}/install/.env" || fail "rerun must not overwrite .env"
grep -q '^REGISTRY_PORT=' "${T}/install/.env" || fail "a missing REGISTRY_PORT should be added on rerun"
grep -q '^REGISTRY_USER=ci$' "${T}/install/.env" || fail "missing registry user should be added on rerun"
grep -q '^REGISTRY_PASS=other-pass$' "${T}/install/.env" || fail "an explicit registry password should be recorded on rerun"
grep -q '^COMPOSE_PROJECT_NAME=' "${T}/install/.env" || fail "the Compose project name should be recorded on rerun"
grep -q 'git .*clone' "${T}/trace" || fail "rerun must refresh the runtime files from a temporary clone"
echo "PASS: reruns refresh the runtime files and preserve .env"

# --- Start path builds and starts the fleet --------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home2" "${T}/install2"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home2" "${T}/install2" >/dev/null 2>&1 ||
    fail "bootstrap with start should succeed"
grep -q '^fleet build$' "${T}/trace" || fail "start path must build the image"
grep -q '^fleet up$' "${T}/trace" || fail "start path must start the fleet"
echo "PASS: start path builds and starts the fleet"

# --- Generated registry password is reported -------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home3" "${T}/install3"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http \
    run_bootstrap "${T}/home3" "${T}/install3" --no-start >"${T}/out-gen" 2>&1 ||
    fail "bootstrap should generate a registry password when none is given"
grep -qi 'registry password' "${T}/out-gen" || fail "generated registry password should be reported"
echo "PASS: generated registry password is reported"

# --- SSH clone with an existing key ----------------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-ssh/.ssh" "${T}/install-ssh"
printf 'private' > "${T}/home-ssh/.ssh/id_rsa"
printf 'public' > "${T}/home-ssh/.ssh/id_rsa.pub"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-ssh" "${T}/install-ssh" --no-start --ssh >"${T}/out-ssh" 2>&1 ||
    {
        cat "${T}/out-ssh" >&2
        fail "SSH bootstrap should succeed with an existing key"
    }
grep -q 'clone --depth 1 --single-branch --branch main git@github.com:blendsdk/build-server.git' "${T}/trace" ||
    fail "SSH mode must clone over git@github.com"
grep -q 'AUTHORIZATION:' "${T}/trace" && fail "SSH mode must not send the token to git"
[ -f "${T}/install-ssh/.env" ] || fail "SSH mode must still write .env"
SSH_DEST="$(grep 'git .*clone' "${T}/trace" | tail -1 | awk '{print $NF}')"
[ "${SSH_DEST}" = "${T}/install-ssh" ] && fail "SSH mode must clone into a temporary directory"
echo "PASS: SSH clone with an existing key"

# --- Generate and install a new SSH key ------------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-gen" "${T}/install-gen"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-gen" "${T}/install-gen" --no-start --generate-ssh-key \
    >"${T}/out-genkey" 2>&1 ||
    {
        cat "${T}/out-genkey" >&2
        fail "generated-key bootstrap should succeed"
    }
grep -q 'ssh-keygen' "${T}/trace" || fail "a new key must be generated"
grep -q '/user/keys' "${T}/trace" || fail "the public key must be installed via the API"
grep -qi 'installed the SSH public key' "${T}/out-genkey" || fail "success message missing"
grep -q 'clone --depth 1 --single-branch --branch main git@github.com:blendsdk/build-server.git' "${T}/trace" ||
    fail "generated-key mode must clone over git@github.com"
[ -f "${T}/home-gen/.ssh/id_rsa" ] || fail "generated key missing"
echo "PASS: generate and install a new SSH key"

# --- SSH without a key fails with guidance ---------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-nokey" "${T}/install-nokey"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-nokey" "${T}/install-nokey" --no-start --ssh \
    >"${T}/out-nokey" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "SSH mode without a key must fail"
grep -q -- '--generate-ssh-key' "${T}/out-nokey" || fail "missing-key error should mention --generate-ssh-key"
echo "PASS: SSH without a key fails with guidance"

# --- Organizations are required and validated -----------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-noorgs" "${T}/install-noorgs"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    HOME="${T}/home-noorgs" INSTALL_DIR="${T}/install-noorgs" TRACE="${T}/trace" \
    CURL_HTTP_CODE=201 PATH="${T}/bin:${PATH}" bash "${ROOT}/bootstrap.sh" \
    --non-interactive --no-start >"${T}/out-noorgs" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "missing organizations must fail in non-interactive mode"
grep -q 'ORGS' "${T}/out-noorgs" || fail "missing-organizations error should mention ORGS"
echo "PASS: organizations are required in non-interactive mode"

make_stubs "${T}/bin"
mkdir -p "${T}/home-badorg" "${T}/install-badorg"
: > "${T}/trace"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    ORGS=GhostOrg CURL_HTTP_CODE=404 run_bootstrap "${T}/home-badorg" "${T}/install-badorg" --no-start \
    >"${T}/out-badorg" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "an unknown organization must fail validation"
grep -q 'GhostOrg' "${T}/out-badorg" || fail "validation error should name the organization"
echo "PASS: unknown organizations fail validation"

# --- Custom-context images are built before starting -----------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-ctx" "${T}/install-ctx"
printf 'RegisteredOrg\nInitech context=examples/runner-custom\n' > "${T}/install-ctx/orgs.conf"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-ctx" "${T}/install-ctx" --keep-orgs >"${T}/out-ctx" 2>&1 ||
    {
        cat "${T}/out-ctx" >&2
        fail "bootstrap with a custom context should succeed"
    }
grep -q '^fleet build$' "${T}/trace" || fail "default image must be built"
grep -q '^fleet build Initech$' "${T}/trace" || fail "custom-context image must be built"
grep -q '^fleet up$' "${T}/trace" || fail "fleet must start after the builds"
echo "PASS: custom-context images are built before starting"

# --- A fleet failure is reported as such, not as a docker-access problem ---------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-fail" "${T}/install-fail"
: > "${T}/trace"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    FAKE_FLEET_FAIL_UP=1 \
    run_bootstrap "${T}/home-fail" "${T}/install-fail" >"${T}/out-fail" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failing fleet start must fail the installer"
grep -q 'up failed' "${T}/out-fail" || fail "the actual command failure should be reported"
grep -q 'not accessible' "${T}/out-fail" && fail "must not blame docker access for a command failure"
echo "PASS: fleet command failures are reported accurately"

# --- A busy registry port is replaced by a free one -------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-port" "${T}/install-port"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    SS_BUSY_PORT=5000 run_bootstrap "${T}/home-port" "${T}/install-port" --no-start \
    >"${T}/out-port" 2>&1 ||
    {
        cat "${T}/out-port" >&2
        fail "bootstrap should pick a free registry port"
    }
grep -q '^REGISTRY_PORT=5001$' "${T}/install-port/.env" || fail "a free registry port must be recorded in .env"
grep -qi 'busy' "${T}/out-port" || fail "the port change should be reported"
echo "PASS: a busy registry port is replaced by a free one"

# --- An explicitly requested busy port fails --------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-portbusy" "${T}/install-portbusy"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    REGISTRY_PORT=5000 SS_BUSY_PORT=5000 run_bootstrap "${T}/home-portbusy" "${T}/install-portbusy" \
    --no-start >"${T}/out-portbusy" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "an explicitly requested busy port must fail"
grep -q 'REGISTRY_PORT=5000' "${T}/out-portbusy" || fail "the error should name REGISTRY_PORT"
echo "PASS: an explicitly requested busy port fails clearly"

# --- An older install without credentials in .env is repaired --------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-upgrade" "${T}/install-upgrade/.git" "${T}/install-upgrade/registry/auth"
printf 'ACCESS_TOKEN=old-token\n' > "${T}/install-upgrade/.env"
# shellcheck disable=SC2016  # a literal bcrypt hash, not a shell expansion
printf 'stale:$2y$stalehash\n' > "${T}/install-upgrade/registry/auth/registry.password"
: > "${T}/trace"
HTPASSWD_VERIFY_EXIT=1 REGISTRY_HTTP_SECRET=secret-http \
    run_bootstrap "${T}/home-upgrade" "${T}/install-upgrade" --no-start \
    >"${T}/out-upgrade" 2>&1 ||
    {
        cat "${T}/out-upgrade" >&2
        fail "bootstrap should repair an install without registry credentials"
    }
grep -q '^ACCESS_TOKEN=old-token$' "${T}/install-upgrade/.env" || fail "existing token must be preserved"
grep -q '^REGISTRY_USER=ci$' "${T}/install-upgrade/.env" || fail "missing registry user must be added"
grep -qE '^REGISTRY_PASS=.+$' "${T}/install-upgrade/.env" || fail "missing registry password must be recorded"
grep -q -- '-Bbn' "${T}/trace" || fail "the htpasswd file must be regenerated to match"
grep -qi 'unknown' "${T}/out-upgrade" && fail "the repair must not leave an unknown-password warning"
echo "PASS: an older install without registry credentials is repaired"

# --- A complete, matching installation is left untouched --------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-match" "${T}/install-match/.git" "${T}/install-match/registry/auth"
cat > "${T}/install-match/.env" <<'EOF'
ACCESS_TOKEN=keep-token
REGISTRY_USER=ci
REGISTRY_PASS=keep-pass
REGISTRY_HTTP_SECRET=keep-http
REGISTRY_PORT=5002
COMPOSE_PROJECT_NAME=keep-proj
EOF
# shellcheck disable=SC2016  # a literal bcrypt hash, not a shell expansion
printf 'ci:$2y$goodhash\n' > "${T}/install-match/registry/auth/registry.password"
: > "${T}/trace"
HTPASSWD_VERIFY_EXIT=0 CURL_HTTP_CODE=201 \
    run_bootstrap "${T}/home-match" "${T}/install-match" --no-start \
    >"${T}/out-match" 2>&1 ||
    {
        cat "${T}/out-match" >&2
        fail "bootstrap should succeed on a matching install"
    }
grep -q -- '-Bbn' "${T}/trace" && fail "a matching htpasswd must not be regenerated"
grep -q '^REGISTRY_PASS=keep-pass$' "${T}/install-match/.env" || fail "credentials must be preserved"
grep -q '^REGISTRY_PORT=5002$' "${T}/install-match/.env" || fail "the recorded port must be preserved"
grep -q '^ACCESS_TOKEN=keep-token$' "${T}/install-match/.env" || fail "the recorded token must be preserved"
grep -q '^COMPOSE_PROJECT_NAME=keep-proj$' "${T}/install-match/.env" ||
    fail "the recorded project name must be preserved"
echo "PASS: a complete, matching installation is left untouched"

# --- Updates refresh the runtime files, keep state, and remove vanished files -----------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-upd" "${T}/install-upd/registry/auth" "${T}/install-upd/ssh" \
    "${T}/install-upd/orgs/acme"
printf 'ACCESS_TOKEN=keep-me\n' > "${T}/install-upd/.env"
printf 'AcmeTools\n' > "${T}/install-upd/orgs.conf"
printf 'old\n' > "${T}/install-upd/old-file.sh"
printf 'fleet.sh\nold-file.sh\n' > "${T}/install-upd/.build-server-manifest"
printf 'hash\n' > "${T}/install-upd/registry/auth/registry.password"
printf 'key\n' > "${T}/install-upd/ssh/id_rsa"
printf 'FROM runner-image\n' > "${T}/install-upd/orgs/acme/Dockerfile"
: > "${T}/trace"
ACCESS_TOKEN=other-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-upd" "${T}/install-upd" --no-start --keep-orgs \
    >"${T}/out-upd" 2>&1 ||
    {
        cat "${T}/out-upd" >&2
        fail "an update should succeed"
    }
[ -e "${T}/install-upd/old-file.sh" ] && fail "a file absent upstream must be removed on update"
[ -f "${T}/install-upd/fleet.sh" ] || fail "runtime files must be refreshed on update"
grep -q '^ACCESS_TOKEN=keep-me$' "${T}/install-upd/.env" || fail "the update must keep the recorded token"
grep -q '^AcmeTools$' "${T}/install-upd/orgs.conf" || fail "the update must keep orgs.conf"
[ -f "${T}/install-upd/registry/auth/registry.password" ] || fail "the update must keep registry state"
[ -f "${T}/install-upd/ssh/id_rsa" ] || fail "the update must keep the staged SSH material"
[ -f "${T}/install-upd/orgs/acme/Dockerfile" ] || fail "the update must keep user context directories"
grep -qx 'old-file.sh' "${T}/install-upd/.build-server-manifest" && fail "the manifest must be rewritten"
echo "PASS: updates refresh runtime files, keep state, and remove vanished files"

# --- A legacy checkout keeps development files without --slim --------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-legacy" "${T}/install-legacy/.git" "${T}/install-legacy/test" "${T}/install-legacy/docs"
printf 'dev\n' > "${T}/install-legacy/test/README.md"
printf 'dev\n' > "${T}/install-legacy/docs/index.md"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-legacy" "${T}/install-legacy" --no-start --keep-orgs \
    >"${T}/out-legacy" 2>&1 ||
    fail "an update of a legacy checkout should succeed"
[ -d "${T}/install-legacy/.git" ] || fail "without --slim the checkout must be kept"
[ -d "${T}/install-legacy/test" ] || fail "without --slim the test tree must be kept"
[ -d "${T}/install-legacy/docs" ] || fail "without --slim the docs tree must be kept"
grep -q -- '--slim' "${T}/out-legacy" || fail "the hint must mention --slim"
echo "PASS: legacy checkouts keep development files and print the --slim hint"

# --- --slim removes development files and keeps state ----------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-slim" "${T}/install-slim/.git" "${T}/install-slim/test" "${T}/install-slim/docs" \
    "${T}/install-slim/codeops" "${T}/install-slim/.opencode/util" "${T}/install-slim/node_modules/pkg" \
    "${T}/install-slim/registry/auth" "${T}/install-slim/ssh" "${T}/install-slim/orgs/acme"
printf 'ACCESS_TOKEN=keep\n' > "${T}/install-slim/.env"
printf 'AcmeTools\n' > "${T}/install-slim/orgs.conf"
printf 'dev\n' > "${T}/install-slim/test/README.md"
printf 'dev\n' > "${T}/install-slim/docs/index.md"
printf 'dev\n' > "${T}/install-slim/codeops/plan.md"
printf 'dev\n' > "${T}/install-slim/.opencode/util/chunk.js"
printf 'dev\n' > "${T}/install-slim/README.md"
printf 'dev\n' > "${T}/install-slim/LICENSE"
printf 'dev\n' > "${T}/install-slim/node_modules/pkg/index.js"
printf 'dev\n' > "${T}/install-slim/package.json"
printf 'dev\n' > "${T}/install-slim/package-lock.json"
printf 'dev\n' > "${T}/install-slim/AGENTS.md"
printf 'hash\n' > "${T}/install-slim/registry/auth/registry.password"
printf 'key\n' > "${T}/install-slim/ssh/id_rsa"
printf 'FROM runner-image\n' > "${T}/install-slim/orgs/acme/Dockerfile"
: > "${T}/trace"
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    run_bootstrap "${T}/home-slim" "${T}/install-slim" --no-start --keep-orgs --slim \
    >"${T}/out-slim" 2>&1 ||
    {
        cat "${T}/out-slim" >&2
        fail "--slim should succeed"
    }
for gone in .git test docs codeops .opencode node_modules package.json package-lock.json AGENTS.md; do
    [ -e "${T}/install-slim/${gone}" ] && fail "--slim must remove ${gone}"
done
for kept in .env orgs.conf registry/auth/registry.password ssh/id_rsa orgs/acme/Dockerfile \
    .build-server-manifest .build-server-version fleet.sh .dockerignore README.md LICENSE; do
    [ -e "${T}/install-slim/${kept}" ] || fail "--slim must keep ${kept}"
done
echo "PASS: --slim removes development files and keeps state"

# --- A failed fetch is reported and the temporary clone is removed ---------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home-cfail"
: > "${T}/trace"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
    GIT_CLONE_EXIT=1 MKTEMP_TARGET="${T}/tmp-clone" HOME="${T}/home-cfail" \
    INSTALL_DIR="${T}/install-cfail" TRACE="${T}/trace" ORGS=ExampleOrg CURL_HTTP_CODE=201 \
    PATH="${T}/bin:${PATH}" bash "${ROOT}/bootstrap.sh" --non-interactive --no-start \
    >"${T}/out-cfail" 2>&1
CODE=$?
set -e
[ "${CODE}" -ne 0 ] || fail "a failed fetch must fail the installer"
grep -qi 'could not fetch' "${T}/out-cfail" || fail "the fetch error should be reported"
[ -e "${T}/tmp-clone" ] && fail "the temporary clone must be removed after a failure"
[ -f "${T}/install-cfail/.build-server-manifest" ] && fail "nothing must be installed after a failed fetch"
echo "PASS: a failed fetch is reported and cleaned up"

echo "bootstrap spec tests: PASS"
