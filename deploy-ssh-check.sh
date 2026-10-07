#!/bin/bash
# deploy-ssh-check — test the runner's deploy SSH configuration and learn host keys.
#
# Test mode checks every literal host from the deploy config (or the hosts given as arguments) with
# a strict, non-interactive SSH connection and reports PASS/FAIL per host. Learn mode prints
# ready-to-paste known_hosts lines, collecting target keys through the configured bastion when one
# applies; it never writes files and never weakens host-key verification.
#
# Exit codes: 0 when every tested host passed (or every requested key was collected), 1 when at
# least one failed, 2 for usage or configuration errors.
set -euo pipefail

SCRIPT_NAME="deploy-ssh-check"
CONFIG="${HOME}/.ssh/deploy.d/config"
CONNECT_TIMEOUT=5
KEYSCAN_TYPES="ed25519,rsa"

# Globals filled by argument parsing and host collection.
MODE="test"
HOSTS=()
LITERAL_HOSTS=()
PATTERNS=()

# Print a usage error and exit 2. Every usage problem is a configuration error by contract.
usage_error() {
    echo "${SCRIPT_NAME}: $1" >&2
    echo "usage: ${SCRIPT_NAME} [host ...] | ${SCRIPT_NAME} --learn <host> ..." >&2
    exit 2
}

# Extract the effective value of one OpenSSH option from an `ssh -G` dump.
dump_field() {
    local dump="$1" key="$2"
    printf '%s\n' "${dump}" | awk -v k="${key}" '$1 == k { print $2; exit }'
}

# Return the last non-empty line of a captured stderr file, or a fallback when it is empty.
last_error_line() {
    local file="$1" fallback="$2" line
    line="$(grep -v '^[[:space:]]*$' "${file}" | tail -n 1 || true)"
    if [ -n "${line}" ]; then
        printf '%s' "${line}"
    else
        printf '%s' "${fallback}"
    fi
}

# Append a literal host once, preserving first-seen order.
add_literal_host() {
    local host="$1" existing
    for existing in "${LITERAL_HOSTS[@]}"; do
        [ "${existing}" = "${host}" ] && return 0
    done
    LITERAL_HOSTS+=("${host}")
}

# Remember a pattern entry once and tell the operator it is skipped.
add_pattern() {
    local pattern="$1" existing
    for existing in "${PATTERNS[@]}"; do
        [ "${existing}" = "${pattern}" ] && return 0
    done
    PATTERNS+=("${pattern}")
    echo "skipped pattern '${pattern}' (pass explicit hostnames to test it)"
}

# Parse the Host lines of the deploy config into literal hosts and skipped patterns.
# Tokenization stops at the first token beginning with `#`; a `#` inside a token stays literal.
collect_hosts() {
    local line keyword token i
    local -a fields=()
    while IFS= read -r line || [ -n "${line}" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [ -n "${line}" ] || continue
        read -ra fields <<<"${line}"
        keyword="${fields[0],,}"
        [ "${keyword}" = "host" ] || continue
        for ((i = 1; i < ${#fields[@]}; i++)); do
            token="${fields[$i]}"
            case "${token}" in
                '#'*) break ;;
            esac
            case "${token}" in
                -*) usage_error "host token '${token}' must not start with '-'" ;;
            esac
            case "${token}" in
                *'*'* | *'?'* | *'!'*) add_pattern "${token}" ;;
                *) add_literal_host "${token}" ;;
            esac
        done
    done <"${CONFIG}"
}

# Run one strict connection test. Returns 0 for PASS, 1 for FAIL; exits 2 when the SSH
# configuration itself cannot be resolved.
test_host() {
    local host="$1" dump jump err rc reason
    if ! dump="$(ssh -G "${host}" 2>/dev/null)"; then
        echo "${SCRIPT_NAME}: invalid SSH configuration for '${host}'" >&2
        exit 2
    fi
    jump="$(dump_field "${dump}" proxyjump)"
    case "${jump}" in none) jump="" ;; esac
    err="$(mktemp "${TMPDIR:-/tmp}/deploy-ssh-check.XXXXXX")"
    set +e
    ssh -o BatchMode=yes -o ConnectTimeout="${CONNECT_TIMEOUT}" -o StrictHostKeyChecking=yes \
        "${host}" true 2>"${err}"
    rc=$?
    set -e
    if [ "${rc}" -eq 0 ]; then
        if [ -n "${jump}" ]; then
            echo "PASS ${host} (jump ${jump})"
        else
            echo "PASS ${host}"
        fi
        rm -f "${err}"
        return 0
    fi
    reason="$(last_error_line "${err}" "ssh exited with status ${rc}")"
    if [ -n "${jump}" ]; then
        echo "FAIL ${host} - ${reason} (jump ${jump})"
    else
        echo "FAIL ${host} - ${reason}"
    fi
    rm -f "${err}"
    return 1
}

# Print collected ssh-keyscan output, keyed to the name SSH verifies (the HostKeyAlias when set).
# Returns 1 and prints a FAIL line when nothing was collected.
print_collected_keys() {
    local out="$1" rc="$2" key_name="$3" resolved="$4"
    if [ "${rc}" -ne 0 ] || [ ! -s "${out}" ]; then
        echo "FAIL ${resolved} - ssh-keyscan returned no keys"
        return 1
    fi
    if [ "${key_name}" != "${resolved}" ]; then
        awk -v n="${key_name}" '{ $1 = n; print }' "${out}"
    else
        cat "${out}"
    fi
    return 0
}

# Collect a target's host key directly from the runner.
learn_direct() {
    local resolved="$1" port="$2" key_name="$3" out rc
    out="$(mktemp "${TMPDIR:-/tmp}/deploy-ssh-check.XXXXXX")"
    set +e
    ssh-keyscan -t "${KEYSCAN_TYPES}" -p "${port}" "${resolved}" >"${out}" 2>/dev/null
    rc=$?
    set -e
    print_collected_keys "${out}" "${rc}" "${key_name}" "${resolved}" || rc=1
    [ "${rc}" -eq 0 ] || rc=1
    rm -f "${out}"
    [ "${rc}" -eq 0 ]
}

# Print the actionable diagnostic for a bastion whose key is missing or changed.
bastion_diagnostic() {
    local err="$1" jump="$2" eff_host="$3" eff_port="$4" reason
    if grep -qF 'Host key verification failed.' "${err}"; then
        echo "The bastion '${jump}' is not covered by the deploy known_hosts. Check that:"
        echo "  1) the deploy config contains a Host block for the bastion (or the target pattern)"
        echo "     setting UserKnownHostsFile ~/.ssh/deploy.d/known_hosts and StrictHostKeyChecking yes,"
        echo "     and 2) its key is pinned. To collect it:"
        echo "     ssh-keyscan -t ${KEYSCAN_TYPES} -p ${eff_port} ${eff_host}"
        echo "Append the output to the deploy folder's known_hosts on the host, restart the runner, then re-run --learn."
    elif grep -qF 'REMOTE HOST IDENTIFICATION HAS CHANGED' "${err}"; then
        echo "The bastion '${jump}' presents a changed key. Remove its stale entry from the deploy"
        echo "known_hosts on the host, restart the runner, then re-run --learn."
    else
        reason="$(last_error_line "${err}" "ssh exited without a message")"
        echo "FAIL ${eff_host} - ${reason}"
    fi
}

# Collect one target's host key, through the configured bastion when one applies.
# Returns 0 on success, 1 on a per-host failure; exits 2 for unsupported configurations.
learn_host() {
    local host="$1" dump hostname alias port jump key_name
    if ! dump="$(ssh -G "${host}" 2>/dev/null)"; then
        echo "${SCRIPT_NAME}: invalid SSH configuration for '${host}'" >&2
        exit 2
    fi
    hostname="$(dump_field "${dump}" hostname)"
    [ -n "${hostname}" ] || hostname="${host}"
    alias="$(dump_field "${dump}" hostkeyalias)"
    case "${alias}" in none) alias="" ;; esac
    port="$(dump_field "${dump}" port)"
    [ -n "${port}" ] || port=22
    jump="$(dump_field "${dump}" proxyjump)"
    case "${jump}" in none) jump="" ;; esac
    key_name="${alias:-${hostname}}"

    if [ -z "${jump}" ]; then
        learn_direct "${hostname}" "${port}" "${key_name}"
        return $?
    fi

    case "${jump}" in
        *,*)
            echo "${SCRIPT_NAME}: --learn does not support chained jumps ('${jump}'); collect the keys manually" >&2
            exit 2
            ;;
    esac

    # Parse the jump specification first: inline ports are not resolved by `ssh -G`.
    local jump_user="" jump_host jump_port="" rest
    rest="${jump}"
    case "${rest}" in *@*) jump_user="${rest%%@*}"; rest="${rest#*@}" ;; esac
    case "${rest}" in *:*) jump_port="${rest##*:}"; rest="${rest%:*}" ;; esac
    jump_host="${rest}"
    case "${jump_port}" in
        "") : ;;
        *[!0-9]*)
            echo "${SCRIPT_NAME}: cannot parse the jump specification '${jump}'; collect the keys manually" >&2
            exit 2
            ;;
    esac

    # Resolve the bastion through its own Host block (or defaults).
    local jump_dump="" eff_host eff_port eff_user eff_dest err rc out
    if [ -n "${jump_port}" ]; then
        jump_dump="$(ssh -G -p "${jump_port}" "${jump_host}" 2>/dev/null)" || {
            echo "${SCRIPT_NAME}: invalid SSH configuration for bastion '${jump_host}'" >&2
            exit 2
        }
    else
        jump_dump="$(ssh -G "${jump_host}" 2>/dev/null)" || {
            echo "${SCRIPT_NAME}: invalid SSH configuration for bastion '${jump_host}'" >&2
            exit 2
        }
    fi
    eff_host="$(dump_field "${jump_dump}" hostname)"
    [ -n "${eff_host}" ] || eff_host="${jump_host}"
    eff_port="$(dump_field "${jump_dump}" port)"
    [ -n "${eff_port}" ] || eff_port="${jump_port:-22}"
    eff_user="$(dump_field "${jump_dump}" user)"
    [ -n "${eff_user}" ] || eff_user="${jump_user}"
    eff_dest="${eff_host}"
    [ -z "${eff_user}" ] || eff_dest="${eff_user}@${eff_host}"

    err="$(mktemp "${TMPDIR:-/tmp}/deploy-ssh-check.XXXXXX")"
    set +e
    if [ -n "${eff_port}" ]; then
        ssh -o BatchMode=yes -o ConnectTimeout="${CONNECT_TIMEOUT}" -o StrictHostKeyChecking=yes \
            -p "${eff_port}" "${eff_dest}" true 2>"${err}"
    else
        ssh -o BatchMode=yes -o ConnectTimeout="${CONNECT_TIMEOUT}" -o StrictHostKeyChecking=yes \
            "${eff_dest}" true 2>"${err}"
    fi
    rc=$?
    set -e
    if [ "${rc}" -ne 0 ]; then
        bastion_diagnostic "${err}" "${jump}" "${eff_host}" "${eff_port}"
        rm -f "${err}"
        return 1
    fi
    rm -f "${err}"

    out="$(mktemp "${TMPDIR:-/tmp}/deploy-ssh-check.XXXXXX")"
    set +e
    ssh -p "${eff_port}" "${eff_dest}" "ssh-keyscan -t ${KEYSCAN_TYPES} -p ${port} ${hostname}" \
        >"${out}" 2>/dev/null
    rc=$?
    set -e
    print_collected_keys "${out}" "${rc}" "${key_name}" "${hostname}" || rc=1
    [ "${rc}" -eq 0 ] || rc=1
    rm -f "${out}"
    [ "${rc}" -eq 0 ]
}

# --- argument parsing ----------------------------------------------------------------------------
while [ "${#}" -gt 0 ]; do
    case "$1" in
        --learn)
            MODE="learn"
            shift
            ;;
        -h | --help)
            echo "usage: ${SCRIPT_NAME} [host ...] | ${SCRIPT_NAME} --learn <host> ..."
            exit 0
            ;;
        -*)
            usage_error "unknown option '$1'"
            ;;
        *)
            HOSTS+=("$1")
            shift
            ;;
    esac
done

[ -f "${CONFIG}" ] ||
    {
        echo "${SCRIPT_NAME}: no deploy-ssh configuration at ${CONFIG} (mount the folder and restart the runner)" >&2
        exit 2
    }

if [ "${MODE}" = "learn" ]; then
    [ "${#HOSTS[@]}" -gt 0 ] || usage_error "--learn requires at least one host"
    failed=0
    for host in "${HOSTS[@]}"; do
        learn_host "${host}" || failed=$((failed + 1))
    done
    [ "${failed}" -eq 0 ] || exit 1
    exit 0
fi

if [ "${#HOSTS[@]}" -eq 0 ]; then
    collect_hosts
    [ "${#LITERAL_HOSTS[@]}" -gt 0 ] ||
        usage_error "no literal hosts in the deploy config; pass hostnames explicitly"
    HOSTS=("${LITERAL_HOSTS[@]}")
fi

total=0
passed=0
failed=0
for host in "${HOSTS[@]}"; do
    total=$((total + 1))
    if test_host "${host}"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
done

echo "${SCRIPT_NAME}: ${passed} of ${total} hosts passed"
if [ "${failed}" -gt 0 ]; then
    echo "hint: run '${SCRIPT_NAME} --learn <host>' to collect a failing host key"
    exit 1
fi
exit 0
