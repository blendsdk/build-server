#!/bin/bash
# Offline playground for fleet.sh — no Docker daemon, no GitHub, no network.
#
# Builds a sandbox under /tmp/fleet-playground containing a copy of fleet.sh, the example
# configuration, a fake HOME with SSH material, and stub docker/curl commands that record what
# they were asked to do. Use it to explore what every fleet.sh command does before touching a real
# host.
#
# Usage:
#   examples/playground.sh                    # (re)create the sandbox and print the next steps
#   examples/playground.sh run generate       # run any fleet.sh command in the sandbox
#   examples/playground.sh run build
#   examples/playground.sh run update-runners
#   examples/playground.sh run status
#   examples/playground.sh show               # print the generated compose file
#   examples/playground.sh trace              # print every stub docker/curl call
#   examples/playground.sh reset              # recreate the sandbox from scratch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SANDBOX="${PLAYGROUND_DIR:-/tmp/fleet-playground}"

# Create a fresh sandbox: repository scripts plus fake docker/curl and a fake HOME.
setup() {
    rm -rf "${SANDBOX}"
    mkdir -p "${SANDBOX}/bin" "${SANDBOX}/home/.ssh" "${SANDBOX}/examples"
    cp "${ROOT}/fleet.sh" "${SANDBOX}/fleet.sh"
    cp "${ROOT}/examples/orgs.conf" "${SANDBOX}/orgs.conf"
    cp -R "${ROOT}/examples/runner-custom" "${SANDBOX}/examples/runner-custom"
    printf 'ARG RUNNER_VERSION="1.2.3"\n' >"${SANDBOX}/Dockerfile"
    printf 'services: {}\n' >"${SANDBOX}/docker-compose.yml"
    printf 'fake-ssh-key' >"${SANDBOX}/home/.ssh/id_rsa"
    local file
    for file in .npmrc .yarnrc .bunfig.toml config.json; do
        printf 'example-credential' >"${SANDBOX}/${file}"
    done
    cat >"${SANDBOX}/bin/docker" <<'EOF'
#!/bin/bash
printf 'docker %s\n' "$*" >> "${TRACE}"
exit 0
EOF
    # Emulates curl's -w behavior so fleet.sh can parse the HTTP status code.
    cat >"${SANDBOX}/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "${TRACE}"
printf '{"tag_name":"v9.9.9"}'
printf '\n200'
exit 0
EOF
    chmod +x "${SANDBOX}/bin/docker" "${SANDBOX}/bin/curl"
    : >"${SANDBOX}/trace"
    echo "Sandbox ready: ${SANDBOX}"
    echo
    echo "Try:"
    echo "  $0 run generate        # render the fleet from the example orgs.conf"
    echo "  $0 show                # inspect the generated compose file"
    echo "  $0 run build           # see how the default image would be built"
    echo "  $0 run build Initech   # see the custom-context staging flow"
    echo "  $0 run update-runners  # see the version update flow (stubbed release API)"
    echo "  $0 run status          # print the fleet table"
    echo "  $0 trace               # every stub call that was made"
    echo "  $0 reset               # start over"
}

# Run a fleet.sh command inside the sandbox with the stubs first on PATH.
run_fleet() {
    [ -f "${SANDBOX}/fleet.sh" ] || setup
    (cd "${SANDBOX}" && HOME="${SANDBOX}/home" ACCESS_TOKEN=example-token \
        TRACE="${SANDBOX}/trace" PATH="${SANDBOX}/bin:${PATH}" bash fleet.sh "$@")
}

case "${1:-}" in
    reset) setup ;;
    run)
        shift
        run_fleet "$@"
        ;;
    show) cat "${SANDBOX}/docker-compose.generated.yml" ;;
    trace) cat "${SANDBOX}/trace" ;;
    *)
        setup
        ;;
esac
