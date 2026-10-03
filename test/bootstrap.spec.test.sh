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
exit 0
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

    cat > "${bin}/sg" <<'EOF'
#!/bin/bash
printf 'sg %s\n' "$*" >> "${TRACE}"
exit 0
EOF

    chmod +x "${bin}/"*
}

# Run the installer against the stubs.
run_bootstrap() {
    local home="$1" dir="$2"
    shift 2
    (cd "${T}" && HOME="${home}" INSTALL_DIR="${dir}" TRACE="${T}/trace" \
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
[ "$(cat "${T}/install/.env")" = "ACCESS_TOKEN=keep-me" ] || fail "rerun must not overwrite .env"
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

echo "bootstrap spec tests: PASS"
