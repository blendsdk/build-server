#!/bin/bash
# Implementation tests for the deploy-ssh connectivity check script.
#
# These cases cover edges the specification suite does not: Host-line parsing details (mixed-case
# keywords, blank lines, multiple tokens, duplicates, rejected tokens), an empty ssh-keyscan result,
# a bastion authentication failure, chained jumps, and multi-host exit-code propagation.
#
# The harness mirrors test/deploy-ssh-check.spec.test.sh: `ssh` and `ssh-keyscan` are replaced with
# PATH stubs that record their arguments on $TRACE, `ssh -G` answers from SSH_G_DUMP (or the
# per-host SSH_G_DUMP_<host>), and a connection attempt takes its outcome from SSH_EXIT/SSH_STDERR
# (or the per-host SSH_EXIT_<host>/SSH_STDERR_<host>). Each case runs the real script entry point in
# an isolated sandbox home and asserts the exact output, exit code, and recorded invocations.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${CODEOPS_TMPDIR:-${TMPDIR:-/tmp}}/deploy-ssh-check.impl.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# --- stubs ------------------------------------------------------------------------------------
mkdir -p "${T}/bin"

# ssh stub:
#   * records every invocation on $TRACE;
#   * answers `-G` (effective-config resolution) from SSH_G_DUMP, or from SSH_G_DUMP_<host> when a
#     per-host dump is set, then exits SSH_G_EXIT;
#   * simulates a remote `ssh-keyscan` run by printing KEYS_CAN_OUTPUT and exiting SSH_EXIT;
#   * for every other connection attempt, resolves the destination host from the argv (skipping
#     option arguments) so a case can vary PASS/FAIL per host, then prints that host's stderr and
#     exits with its status. SSH_STDERR_<host>/SSH_EXIT_<host> win over SSH_STDERR/SSH_EXIT.
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
# Connection attempt: options that take a value are skipped so the first bare argument is the
# destination host (the user and any port are stripped, mirroring how SSH names the peer).
dest=""
skip_next=0
for arg in "$@"; do
    if [ "${skip_next}" -eq 1 ]; then
        skip_next=0
        continue
    fi
    case "${arg}" in
        -o | -p | -l | -i | -F | -J | -W)
            skip_next=1
            ;;
        -*) ;;
        *)
            dest="${arg}"
            break
            ;;
    esac
done
dest="${dest##*@}"
dest="${dest%%:*}"
stderr=""
stderr_var="SSH_STDERR_${dest//[^A-Za-z0-9]/_}"
stderr="${!stderr_var:-}"
if [ -z "${stderr}" ]; then
    stderr="${SSH_STDERR:-}"
fi
exit_code="${SSH_EXIT:-0}"
exit_var="SSH_EXIT_${dest//[^A-Za-z0-9]/_}"
if [ -n "${!exit_var:-}" ]; then
    exit_code="${!exit_var}"
fi
if [ -n "${stderr}" ]; then
    printf '%s\n' "${stderr}" >&2
fi
exit "${exit_code}"
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
    SSH_G_DUMP_app_far=""
    SSH_G_DUMP_app_near=""
    SSH_G_EXIT=0
    SSH_EXIT=0
    SSH_STDERR=""
    SSH_EXIT_app_bad=""
    SSH_STDERR_app_bad=""
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
        SSH_G_DUMP_app_far="${SSH_G_DUMP_app_far-}" \
        SSH_G_DUMP_app_near="${SSH_G_DUMP_app_near-}" \
        SSH_G_EXIT="${SSH_G_EXIT-0}" SSH_EXIT="${SSH_EXIT-0}" SSH_STDERR="${SSH_STDERR-}" \
        SSH_EXIT_app_bad="${SSH_EXIT_app_bad-}" SSH_STDERR_app_bad="${SSH_STDERR_app_bad-}" \
        KEYS_CAN_OUTPUT="${KEYS_CAN_OUTPUT-}" KEYSCAN_EXIT="${KEYSCAN_EXIT-0}" \
        bash "${ROOT}/deploy-ssh-check.sh" "$@" >"${out}" 2>&1
    CODE=$?
    set -e
}

# --- impl-01: mixed-case Host keyword and blank lines -----------------------------------------
new_case impl-01
write_config 'host app-lower

   HOST app-upper
'
SSH_G_DUMP='hostname app-lower
port 22'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "impl-01: expected exit 0, got ${CODE}"
grep -qF 'PASS app-lower' "${OUT}" || fail "impl-01: a lowercase host keyword was not recognized"
grep -qF 'PASS app-upper' "${OUT}" || fail "impl-01: an uppercase HOST keyword was not recognized"
grep -qF 'deploy-ssh-check: 2 of 2 hosts passed' "${OUT}" ||
    fail "impl-01: blank lines must be ignored"
echo "PASS: impl-01 mixed-case Host keywords are recognized and blank lines are ignored"

# --- impl-02: multiple tokens and duplicate hosts are each tested once -------------------------
new_case impl-02
write_config 'Host alpha beta alpha
Host gamma
Host gamma
'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "impl-02: expected exit 0, got ${CODE}"
grep -qF 'deploy-ssh-check: 3 of 3 hosts passed' "${OUT}" ||
    fail "impl-02: duplicate tokens or lines must be counted once"
[ "$(grep -c '^ssh -G alpha$' "${TRACE}" || true)" -eq 1 ] ||
    fail "impl-02: a duplicated token was resolved more than once"
[ "$(grep -c '^ssh -G gamma$' "${TRACE}" || true)" -eq 1 ] ||
    fail "impl-02: a duplicated host line was resolved more than once"
echo "PASS: impl-02 multiple tokens are split and duplicates are counted once"

# --- impl-03: a -prefixed host token is rejected ----------------------------------------------
new_case impl-03
write_config 'Host app-prod -evil
'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 2 ] || fail "impl-03: expected exit 2, got ${CODE}"
grep -qF "host token '-evil' must not start with '-'" "${OUT}" ||
    fail "impl-03: the -prefixed token rejection message is missing"
[ ! -s "${TRACE}" ] || fail "impl-03: no ssh call may run after a rejected token"
echo "PASS: impl-03 a -prefixed host token is rejected with a config error"

# --- impl-04: an empty ssh-keyscan result reports FAIL ----------------------------------------
new_case impl-04
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22'
KEYS_CAN_OUTPUT=""
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 1 ] || fail "impl-04: expected exit 1, got ${CODE}"
grep -qF 'FAIL app-prod - ssh-keyscan returned no keys' "${OUT}" ||
    fail "impl-04: an empty keyscan result must report FAIL"
echo "PASS: impl-04 an empty ssh-keyscan result reports FAIL and exits 1"

# --- impl-05: a bastion authentication failure is per host, the run continues -----------------
new_case impl-05
write_config 'Host app-far
'
SSH_G_DUMP_app_far='hostname app-far
port 22
proxyjump deploy@bastion.corp:2222'
SSH_G_DUMP_bastion_corp='hostname bastion.corp
port 2222'
SSH_G_DUMP_app_near='hostname app-near
port 22'
SSH_EXIT=255
SSH_STDERR='Permission denied (publickey).'
KEYS_CAN_OUTPUT='app-near ssh-ed25519 AAAANEAR'
run_check "${H}" "${OUT}" --learn app-far app-near
[ "${CODE}" -eq 1 ] || fail "impl-05: expected exit 1, got ${CODE}"
grep -qF 'FAIL bastion.corp - Permission denied (publickey).' "${OUT}" ||
    fail "impl-05: the bastion and the auth reason must be named"
grep -qF 'app-near ssh-ed25519 AAAANEAR' "${OUT}" ||
    fail "impl-05: the remaining host must still be processed"
grep -qF 'not covered by the deploy known_hosts' "${OUT}" &&
    fail "impl-05: an auth failure must not print the host-key diagnostic"
echo "PASS: impl-05 a bastion auth failure reports FAIL, continues, and exits 1"

# --- impl-06: chained jumps are unsupported ---------------------------------------------------
new_case impl-06
write_config 'Host app-prod
'
SSH_G_DUMP='hostname app-prod
port 22
proxyjump bastion-a,bastion-b'
run_check "${H}" "${OUT}" --learn app-prod
[ "${CODE}" -eq 2 ] || fail "impl-06: expected exit 2, got ${CODE}"
grep -qF "does not support chained jumps ('bastion-a,bastion-b')" "${OUT}" ||
    fail "impl-06: the chained-jump message is missing"
grep -q '^ssh-keyscan ' "${TRACE}" && fail "impl-06: no keyscan may run for a chained jump"
echo "PASS: impl-06 chained jumps are unsupported and exit 2"

# --- impl-07: mixed results report the pass count and exit 1 ----------------------------------
new_case impl-07
write_config 'Host app-ok
Host app-bad
'
SSH_EXIT_app_bad=255
SSH_STDERR_app_bad='Connection refused'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 1 ] || fail "impl-07: expected exit 1, got ${CODE}"
grep -qF 'PASS app-ok' "${OUT}" || fail "impl-07: the reachable host must PASS"
grep -qF 'FAIL app-bad - Connection refused' "${OUT}" ||
    fail "impl-07: the unreachable host must FAIL with its reason"
grep -qF 'deploy-ssh-check: 1 of 2 hosts passed' "${OUT}" ||
    fail "impl-07: the summary must count 1 of 2"
echo "PASS: impl-07 mixed results report 1 of 2 and exit 1"

# --- impl-08: an all-pass pair reports 2 of 2 and exits 0 -------------------------------------
new_case impl-08
write_config 'Host app-one
Host app-two
'
run_check "${H}" "${OUT}"
[ "${CODE}" -eq 0 ] || fail "impl-08: expected exit 0, got ${CODE}"
grep -qF 'PASS app-one' "${OUT}" || fail "impl-08: the first host must PASS"
grep -qF 'PASS app-two' "${OUT}" || fail "impl-08: the second host must PASS"
grep -qF 'deploy-ssh-check: 2 of 2 hosts passed' "${OUT}" ||
    fail "impl-08: the summary must count 2 of 2"
echo "PASS: impl-08 an all-pass pair reports 2 of 2 and exits 0"

# --- impl-09: explicit hosts override the default (pattern-only) selection --------------------
new_case impl-09
write_config 'Host app-*
'
SSH_G_DUMP='hostname app-prod
port 22'
run_check "${H}" "${OUT}" app-prod
[ "${CODE}" -eq 0 ] || fail "impl-09: expected exit 0, got ${CODE}"
grep -qF 'PASS app-prod' "${OUT}" || fail "impl-09: the explicit host must be tested"
grep -qF 'deploy-ssh-check: 1 of 1 hosts passed' "${OUT}" ||
    fail "impl-09: only the explicit host may be counted"
grep -qF 'skipped pattern' "${OUT}" &&
    fail "impl-09: explicit hosts must not trigger the pattern note"
grep -qF 'ssh -G app-*' "${TRACE}" &&
    fail "impl-09: the config pattern must not be resolved"
echo "PASS: impl-09 explicit hosts override the default selection"

echo "deploy-ssh-check impl tests: PASS"
