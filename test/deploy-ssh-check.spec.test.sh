#!/bin/bash
# Specification tests for the deploy-ssh connectivity check script.
#
# The script reads the staged deploy config from ${HOME}/.ssh/deploy.d/config. External commands
# (ssh, ssh-keyscan) are replaced with PATH stubs that record their arguments, so the suite never
# opens a real network connection. Every case runs the script through its real entry point and
# asserts the exact output, exit code, and recorded invocations the specification requires.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${CODEOPS_TMPDIR:-${TMPDIR:-/tmp}}/deploy-ssh-check.spec.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# --- stubs ------------------------------------------------------------------------------------
mkdir -p "${T}/bin"

# ssh stub:
#   * records every invocation on $TRACE;
#   * answers `-G` (effective-config resolution) from SSH_G_DUMP, or from SSH_G_DUMP_<host> when a
#     per-host dump is set, then exits SSH_G_EXIT;
#   * simulates a remote `ssh-keyscan` run by printing KEYS_CAN_OUTPUT and exiting SSH_EXIT;
#   * every other connection attempt prints SSH_STDERR to stderr and exits SSH_EXIT.
cat > "${T}/bin/ssh" <<'EOF'
#!/bin/bash
printf 'ssh %s\n' "$*" >> "${TRACE}"
is_g=0
has_keyscan=0
for arg in "$@"; do
    if [ "${arg}" = "-G" ]; then
        is_g=1
    fi
    case "${arg}" in
        *ssh-keyscan*) has_keyscan=1 ;;
    esac
done
if [ "${is_g}" -eq 1 ]; then
    host=""
    for arg in "$@"; do
        case "${arg}" in
            -*) ;;
            *) host="${arg}" ;;
        esac
    done
    host="${host##*@}"
    host="${host%%:*}"
    var="SSH_G_DUMP_${host//[^A-Za-z0-9]/_}"
    dump="${!var:-}"
    if [ -z "${dump}" ]; then
        dump="${SSH_G_DUMP:-}"
    fi
    if [ -n "${dump}" ]; then
        printf '%s\n' "${dump}"
    fi
    exit "${SSH_G_EXIT:-0}"
fi
if [ "${has_keyscan}" -eq 1 ]; then
    if [ -n "${KEYS_CAN_OUTPUT:-}" ]; then
        printf '%s\n' "${KEYS_CAN_OUTPUT}"
    fi
    exit "${SSH_EXIT:-0}"
fi
if [ -n "${SSH_STDERR:-}" ]; then
    printf '%s\n' "${SSH_STDERR}" >&2
fi
exit "${SSH_EXIT:-0}"
EOF

# ssh-keyscan stub: record the argv, print the canned keys, and exit KEYSCAN_EXIT.
cat > "${T}/bin/ssh-keyscan" <<'EOF'
#!/bin/bash
printf 'ssh-keyscan %s\n' "$*" >> "${TRACE}"
if [ -n "${KEYS_CAN_OUTPUT:-}" ]; then
    printf '%s\n' "${KEYS_CAN_OUTPUT}"
fi
exit "${KEYSCAN_EXIT:-0}"
EOF

chmod +x "${T}/bin/ssh" "${T}/bin/ssh-keyscan"

# --- helpers ------------------------------------------------------------------------------------
fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Clear every stub environment variable so one case can never inherit another case's behavior.
reset_stub_env() {
    SSH_G_DUMP=""
    SSH_G_DUMP_bastion_corp=""
    SSH_G_EXIT=0
    SSH_EXIT=0
    SSH_STDERR=""
    KEYS_CAN_OUTPUT=""
    KEYSCAN_EXIT=0
}

# Start an isolated case sandbox and point H (runner home), OUT (combined output), and TRACE at it.
new_case() {
    local name="$1"
    local dir="${T}/${name}"
    mkdir -p "${dir}/home/.ssh"
    : > "${dir}/trace"
    H="${dir}/home"
    OUT="${dir}/out"
    TRACE="${dir}/trace"
    reset_stub_env
}

# Write the staged deploy config with the given content into the sandbox home.
write_config() {
    mkdir -p "${H}/.ssh/deploy.d"
    printf '%s' "$1" > "${H}/.ssh/deploy.d/config"
}

# Run the check script against the sandbox home; capture combined output in $OUT and status in $CODE.
# The stub behavior comes from the per-case environment variables set before the call.
run_check() {
    local home="$1"
    local out="$2"
    shift 2
    set +e
    HOME="${home}" TRACE="${TRACE}" PATH="${T}/bin:${PATH}" \
        SSH_G_DUMP="${SSH_G_DUMP-}" \
        SSH_G_DUMP_bastion_corp="${SSH_G_DUMP_bastion_corp-}" \
        SSH_G_EXIT="${SSH_G_EXIT-0}" SSH_EXIT="${SSH_EXIT-0}" SSH_STDERR="${SSH_STDERR-}" \
        KEYS_CAN_OUTPUT="${KEYS_CAN_OUTPUT-}" KEYSCAN_EXIT="${KEYSCAN_EXIT-0}" \
        bash "${ROOT}/deploy-ssh-check.sh" "$@" >"${out}" 2>&1
    CODE=$?
    set -e
}

# The install instruction that must terminate every successful --learn run.
LEARN_INSTRUCTION="Append the lines above to the deploy folder's known_hosts on the host, restart the runner, then re-run --learn."

# --- ST-20: pattern hosts are listed as skipped and never tested -------------------------------
new_case st-20
write_config 'Host app-prod
Host app-*
'
SSH_G_DUMP='hostname app-prod
port 22'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "ST-20: expected exit 0, got ${CODE}"
grep -qF 'PASS app-prod' "${OUT}" || fail "ST-20: the literal host app-prod was not tested"
grep -qF "skipped pattern 'app-*' (pass explicit hostnames to test it)" "${OUT}" ||
    fail "ST-20: the app-* pattern was not listed as skipped"
grep -qF 'ssh -G app-*' "${TRACE}" && fail "ST-20: a pattern host must never be resolved or tested"
grep -qF 'deploy-ssh-check: 1 of 1 hosts passed' "${OUT}" ||
    fail "ST-20: the summary must count only the literal host"
echo "PASS: ST-20 pattern hosts are listed as skipped and never tested"

# --- ST-21: a reachable host reports PASS and exit 0 -------------------------------------------
new_case st-21
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "ST-21: expected exit 0, got ${CODE}"
grep -qF 'PASS app-prod' "${OUT}" || fail "ST-21: the PASS line is missing"
grep -qF 'deploy-ssh-check: 1 of 1 hosts passed' "${OUT}" ||
    fail "ST-21: the pass summary is missing"
echo "PASS: ST-21 a reachable host reports PASS and exit 0"

# --- ST-22: a host-key failure reports FAIL with the stderr reason and exit 1 -------------------
new_case st-22
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22'
SSH_EXIT=255
SSH_STDERR='Host key verification failed.'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 1 ] || fail "ST-22: expected exit 1, got ${CODE}"
grep -qF 'FAIL app-prod - Host key verification failed.' "${OUT}" ||
    fail "ST-22: the FAIL line must carry the last non-empty stderr line"
grep -qF "hint: run 'deploy-ssh-check --learn <host>' to collect a failing host key" "${OUT}" ||
    fail "ST-22: the failing-host hint is missing"
grep -qF 'deploy-ssh-check: 0 of 1 hosts passed' "${OUT}" ||
    fail "ST-22: the failing summary is missing"
echo "PASS: ST-22 a host-key failure reports FAIL and exit 1"

# --- ST-23: a missing deploy config exits 2 with the mount hint --------------------------------
new_case st-23
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 2 ] || fail "ST-23: expected exit 2, got ${CODE}"
grep -qF "deploy-ssh-check: no deploy-ssh configuration at ${H}/.ssh/deploy.d/config (mount the folder and restart the runner)" "${OUT}" ||
    fail "ST-23: the missing-config message is missing"
echo "PASS: ST-23 a missing deploy config exits 2 with the mount hint"

# --- ST-24: --learn without a host is a usage error --------------------------------------------
new_case st-24
write_config 'Host app-prod
'
run_check "${H}" "${OUT}" --learn
[ "${CODE}" -eq 2 ] || fail "ST-24: expected exit 2, got ${CODE}"
grep -qi 'usage' "${OUT}" || fail "ST-24: a usage message is required when --learn has no host"
echo "PASS: ST-24 --learn without a host exits 2 with usage"

# --- ST-25: --learn with no jump scans the target directly -------------------------------------
new_case st-25
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22'
KEYS_CAN_OUTPUT='app-prod ssh-ed25519 AAAATESTKEY'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 0 ] || fail "ST-25: expected exit 0, got ${CODE}"
grep -qF 'ssh-keyscan -t ed25519,rsa -p 22 app-prod' "${TRACE}" ||
    fail "ST-25: the keyscan must target the resolved name and port"
grep -qF 'app-prod ssh-ed25519 AAAATESTKEY' "${OUT}" ||
    fail "ST-25: the collected key line is missing"
[ "$(tail -n 1 "${OUT}")" = "${LEARN_INSTRUCTION}" ] ||
    fail "ST-25: the output must end with the install instruction"
echo "PASS: ST-25 --learn with no jump scans the target directly"

# --- ST-26: an unpinned bastion prints the Host-block diagnostic and skips the host -------------
new_case st-26
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22
proxyjump deploy@bastion.corp:2222'
SSH_G_DUMP_bastion_corp='hostname bastion.corp
port 2222'
SSH_EXIT=255
SSH_STDERR='Host key verification failed.'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 1 ] || fail "ST-26: expected exit 1, got ${CODE}"
grep -qi 'Host block' "${OUT}" ||
    fail "ST-26: the diagnostic must require a bastion Host block"
grep -qF 'UserKnownHostsFile ~/.ssh/deploy.d/known_hosts' "${OUT}" ||
    fail "ST-26: the diagnostic must show the known_hosts wiring"
grep -qF 'ssh-keyscan -t ed25519,rsa -p 2222 bastion.corp' "${OUT}" ||
    fail "ST-26: the diagnostic must print the bastion keyscan line"
grep -q '^ssh-keyscan ' "${TRACE}" && fail "ST-26: no target keyscan may run when the bastion fails"
echo "PASS: ST-26 an unpinned bastion prints the Host-block diagnostic and skips the host"

# --- ST-27: --learn scans the target through a reachable bastion -------------------------------
new_case st-27
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22
proxyjump deploy@bastion.corp:2222'
SSH_G_DUMP_bastion_corp='hostname bastion.corp
port 2222'
KEYS_CAN_OUTPUT='app-prod ssh-ed25519 AAAATESTKEY'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 0 ] || fail "ST-27: expected exit 0, got ${CODE}"
grep -F 'deploy@bastion.corp' "${TRACE}" | grep -qF 'ssh-keyscan -t ed25519,rsa -p 22 app-prod' ||
    fail "ST-27: the target keyscan must run through the bastion"
grep -q '^ssh-keyscan ' "${TRACE}" && fail "ST-27: the target keyscan must not run locally"
grep -qF 'app-prod ssh-ed25519 AAAATESTKEY' "${OUT}" ||
    fail "ST-27: the collected key line is missing"
[ "$(tail -n 1 "${OUT}")" = "${LEARN_INSTRUCTION}" ] ||
    fail "ST-27: the output must end with the install instruction"
grep -F 'deploy@bastion.corp' "${TRACE}" | grep -F 'ssh-keyscan' | grep -qF 'StrictHostKeyChecking=yes' ||
    fail "ST-27: the keyscan hop must use strict host-key checking"
echo "PASS: ST-27 --learn scans the target through the bastion"

# --- ST-28: an ssh -G failure exits 2 and names the host ---------------------------------------
new_case st-28
write_config 'Host app-prod
'
SSH_G_EXIT=1
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 2 ] || fail "ST-28: expected exit 2, got ${CODE}"
grep -qF 'app-prod' "${OUT}" || fail "ST-28: the failing host must be named"
echo "PASS: ST-28 an ssh -G failure exits 2 and names the host"

# --- ST-36: keyscan targets the resolved HostName ----------------------------------------------
new_case st-36
write_config 'Host app-prod
'
SSH_G_DUMP='hostname 10.20.1.5
port 22'
KEYS_CAN_OUTPUT='10.20.1.5 ssh-ed25519 AAAATESTKEY'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 0 ] || fail "ST-36: expected exit 0, got ${CODE}"
grep -qF 'ssh-keyscan -t ed25519,rsa -p 22 10.20.1.5' "${TRACE}" ||
    fail "ST-36: keyscan must target the resolved HostName"
grep -qF '10.20.1.5 ssh-ed25519 AAAATESTKEY' "${OUT}" ||
    fail "ST-36: the resolved-name key line is missing"
echo "PASS: ST-36 keyscan targets the resolved HostName"

# --- ST-37: printed entries are keyed to the HostKeyAlias --------------------------------------
new_case st-37
write_config 'Host app-prod
'
SSH_G_DUMP='hostname 10.20.1.5
port 22
hostkeyalias alias-host'
KEYS_CAN_OUTPUT='10.20.1.5 ssh-ed25519 AAAATESTKEY'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 0 ] || fail "ST-37: expected exit 0, got ${CODE}"
grep -qF 'ssh-keyscan -t ed25519,rsa -p 22 10.20.1.5' "${TRACE}" ||
    fail "ST-37: keyscan must target the resolved HostName"
awk '$1 == "alias-host" && $2 == "ssh-ed25519" { found = 1 } END { exit !found }' "${OUT}" ||
    fail "ST-37: the printed entry must be keyed to the HostKeyAlias"
grep -q '^10\.20\.1\.5[[:space:]]' "${OUT}" &&
    fail "ST-37: the resolved name must be replaced by the HostKeyAlias"
echo "PASS: ST-37 printed entries use the HostKeyAlias"

# --- ST-39: inline comments stop tokenization; '#' inside a token stays literal ------------------
new_case st-39
write_config 'Host foo # comment
Host baz#qux
'
SSH_G_DUMP='hostname foo
port 22'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "ST-39: expected exit 0, got ${CODE}"
grep -qF 'PASS foo' "${OUT}" || fail "ST-39: foo must be tested"
grep -qF 'PASS baz#qux' "${OUT}" || fail "ST-39: baz#qux must be tested as one token"
grep -qF 'PASS comment' "${OUT}" && fail "ST-39: the inline comment must not be tested"
grep -qF 'deploy-ssh-check: 2 of 2 hosts passed' "${OUT}" ||
    fail "ST-39: only foo and baz#qux may be tested"
grep -qE '^ssh -G (comment|#)' "${TRACE}" && fail "ST-39: comment tokens must never be resolved"
echo "PASS: ST-39 inline comments stop tokenization while a '#' inside a token stays literal"

# --- ST-46: a resolved HostName with shell metacharacters is rejected --------------------------
new_case st-46
write_config 'Host app-prod
'
# The single-quoted dump keeps the backticks literal, so the resolved hostname is `id` (a command
# substitution if it ever reached a shell). The check must refuse it before any keyscan runs.
# shellcheck disable=SC2016  # the backticks must stay literal in the resolved hostname under test
SSH_G_DUMP='hostname `id`
port 22'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 2 ] || fail "ST-46: expected exit 2, got ${CODE}"
grep -qF 'resolved hostname' "${OUT}" || fail "ST-46: the resolved-hostname label is missing"
grep -qF 'is not supported' "${OUT}" || fail "ST-46: the unsupported-value message is missing"
grep -q 'ssh-keyscan' "${TRACE}" && fail "ST-46: no keyscan may run for an unsupported resolved name"
echo "PASS: ST-46 a resolved HostName with shell metacharacters is rejected"

# --- ST-47: test mode fails when a jump's bastion is not strictly verified ---------------------
new_case st-47
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22
proxyjump deploy@bastion.corp:2222'
SSH_G_DUMP_bastion_corp='hostname bastion.corp
port 2222
stricthostkeychecking ask'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 1 ] || fail "ST-47: expected exit 1, got ${CODE}"
grep -qF "FAIL app-prod - bastion 'deploy@bastion.corp:2222' host-key checking is not strict (set StrictHostKeyChecking yes for it)" "${OUT}" ||
    fail "ST-47: the non-strict bastion FAIL line is missing"
grep -qF 'deploy-ssh-check: 0 of 1 hosts passed' "${OUT}" ||
    fail "ST-47: the failing summary is missing"
grep -q '^ssh-keyscan ' "${TRACE}" && fail "ST-47: no keyscan may run in test mode"
echo "PASS: ST-47 a non-strict bastion FAILs the host with exit 1"

echo "deploy-ssh-check spec tests: PASS"
