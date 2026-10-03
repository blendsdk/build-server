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

    # git records calls; a clone invocation creates the target as a repository.
    cat > "${bin}/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >> "${TRACE}"
is_clone=0
for arg in "$@"; do
    [ "${arg}" = "clone" ] && is_clone=1
done
if [ "${is_clone}" = "1" ]; then
    for last in "$@"; do :; done
    mkdir -p "${last}/.git"
fi
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

for file in .npmrc .yarnrc .bunfig.toml config.json; do
    [ -f "${T}/install/${file}" ] || fail "placeholder ${file} missing"
done
[ -s "${T}/install/registry/auth/registry.password" ] || fail "registry htpasswd missing"
[ -f "${T}/home/.ssh/id_rsa" ] || fail "deploy key not generated"
[ -f "${T}/home/.ssh/config" ] || fail "ssh config not created"
grep -q -- '--branch main' "${T}/trace" || fail "clone must target the configured branch"
grep -q 'https://github.com/blendsdk/build-server.git' "${T}/trace" || fail "clone must target the public repository"
grep -q 'AUTHORIZATION: bearer secret-token' "${T}/trace" || fail "clone must authenticate with the token"
echo "PASS: full setup creates configuration, credentials, keys, and htpasswd"

# --- Reruns are idempotent and preserve .env -------------------------------------------------
printf 'ACCESS_TOKEN=keep-me\n' > "${T}/install/.env"
chmod 600 "${T}/install/.env"
: > "${T}/trace"
ACCESS_TOKEN=other-token REGISTRY_HTTP_SECRET=other-http REGISTRY_PASS=other-pass \
    run_bootstrap "${T}/home" "${T}/install" --no-start >/dev/null 2>&1 ||
    fail "bootstrap rerun should succeed"
grep -q '^ACCESS_TOKEN=keep-me$' "${T}/install/.env" || fail "rerun must not overwrite .env"
grep -q '^REGISTRY_PORT=' "${T}/install/.env" || fail "a missing REGISTRY_PORT should be added on rerun"
grep -q 'git .*fetch' "${T}/trace" || fail "rerun must update the existing checkout"
echo "PASS: reruns update the checkout and preserve .env"

# --- Start path builds and starts the fleet --------------------------------------------------
make_stubs "${T}/bin"
mkdir -p "${T}/home2" "${T}/install2/.git"
cat > "${T}/install2/fleet.sh" <<'EOF'
#!/bin/bash
printf 'fleet %s\n' "$*" >> "${TRACE}"
exit 0
EOF
chmod +x "${T}/install2/fleet.sh"
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
grep -q 'git clone --branch main git@github.com:blendsdk/build-server.git' "${T}/trace" ||
    fail "SSH mode must clone over git@github.com"
grep -q 'AUTHORIZATION: bearer' "${T}/trace" && fail "SSH mode must not send the token to git"
[ -f "${T}/install-ssh/.env" ] || fail "SSH mode must still write .env"
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
grep -q 'git clone --branch main git@github.com:blendsdk/build-server.git' "${T}/trace" ||
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
mkdir -p "${T}/home-ctx" "${T}/install-ctx/.git"
printf 'RegisteredOrg\nInitech context=examples/runner-custom\n' > "${T}/install-ctx/orgs.conf"
cat > "${T}/install-ctx/fleet.sh" <<'EOF'
#!/bin/bash
printf 'fleet %s\n' "$*" >> "${TRACE}"
exit 0
EOF
chmod +x "${T}/install-ctx/fleet.sh"
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
mkdir -p "${T}/home-fail" "${T}/install-fail/.git"
cat > "${T}/install-fail/fleet.sh" <<'EOF'
#!/bin/bash
printf 'fleet %s\n' "$*" >> "${TRACE}"
if [ "${1:-}" = "up" ]; then exit 1; fi
exit 0
EOF
chmod +x "${T}/install-fail/fleet.sh"
: > "${T}/trace"
set +e
ACCESS_TOKEN=secret-token REGISTRY_HTTP_SECRET=secret-http REGISTRY_PASS=secret-pass \
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

echo "bootstrap spec tests: PASS"
