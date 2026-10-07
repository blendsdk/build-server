# Current State: deploy-ssh

> **Document**: 02-current-state.md
> **Parent**: [Index](00-index.md)

## Existing Implementation

### What Exists

The fleet already provides SSH material for GitHub access, but nothing for deployment targets:

- The runner image installs `openssh-client`, `rsync`, and `git` and bakes three SSH files from the
  host's `~/.ssh`: `id_rsa`, `id_rsa.pub`, and `config` (`Dockerfile:13-15`, `Dockerfile:52-59`).
  `fleet.sh build` stages the whole host `~/.ssh` into the build context first
  (`fleet.sh:382-388`).
- The host's `known_hosts` is populated for GitHub when bootstrap uses SSH auth
  (`bootstrap.sh:227-234`), but it is **not** copied into the image — the Dockerfile copies only the
  three files above. A non-interactive job has no TTY to accept an unknown host key, so the first
  connection to any unlisted host fails at host-key verification (Gap 2).
- `fleet.sh generate` renders one Compose service per organization from `orgs.conf`
  (`fleet.sh:164-209`), and the `build_temp=1` option already demonstrates a per-organization
  volume mount (`fleet.sh:198-203`).
- The entrypoint runs as root, starts the private Docker daemon, then drops privileges to the
  `docker` user via `setpriv` with `HOME=/home/docker` (`entrypoint.sh:109-111`). It already uses
  overridable path/behavior variables for tests (`entrypoint.sh:11-16`).
- `fleet.sh` validates the `context=` option with an existence check and realpath containment against
  the repository root (`fleet.sh:122-131`); a literal glob fails only as a side effect of the
  existence requirement. The planned `deploy_ssh` validation adds explicit rejection of glob and
  mount metacharacters (`*`, `?`, `[`, `:`, `$`) and restricts paths to `deploy-ssh/`.
- Tests are stub-based shell scripts run by `bash test/verify.sh` (`test/verify.sh:10-23`); the
  playground (`examples/playground.sh`) exercises the CLI offline.

### Relevant Files

| File | Purpose | Changes Needed |
| ---- | ------- | -------------- |
| `fleet.sh` | Fleet admin CLI | `deploy_ssh=` parsing/validation, auto-create, mount rendering, `check-ssh` command |
| `entrypoint.sh` | Container entrypoint (root, then `setpriv`) | Stage `/run/deploy-ssh` for the runner user; add the `Include` line |
| `Dockerfile` | Runner image | Install `deploy-ssh-check` |
| `deploy-ssh-check.sh` | *(new)* connectivity check + host-key learning | New file |
| `bootstrap.sh` | Fresh-host installer | Add the new script to `INSTALL_FILES` (`bootstrap.sh:368-376`) |
| `.gitignore` | Host-local secrets | Exclude `deploy-ssh/` |
| `.dockerignore` | Build context hygiene | Exclude `deploy-ssh/` |
| `test/orgs.spec.test.sh` | Parser/renderer spec tests | New `deploy_ssh` cases |
| `test/fleet.spec.test.sh` | CLI spec tests (stub docker/curl) | Auto-create, never-delete, `check-ssh` cases |
| `test/fleet.impl.test.sh` | CLI internals | Auto-create coverage across commands, idempotence |
| `test/entrypoint.spec.test.sh` / `.impl.test.sh` | Entrypoint behavior | Staging behavior, ownership/modes, include idempotence, failure tolerance |
| `test/deploy-ssh-check.spec.test.sh` / `.impl.test.sh` | *(new)* script tests | Test/learn behavior with stub `ssh`/`ssh-keyscan` |
| `test/dockerfile.spec.test.sh` | Image contents | Assert the script is installed |
| `test/bootstrap.spec.test.sh` | Installer spec tests | Fake repo file, install assertion, manifest |
| `test/verify.sh` | Verify command | Add new test files; add the script to shellcheck |
| `docs/` | VitePress site | New guide page, sidebar, reference/operations/security updates |

### Code Analysis

The pieces the feature builds on:

```bash
# fleet.sh:198-203 — per-org volumes are already part of the renderer
if [ "${build_temp}" = "1" ]; then
    cat <<EOF
    volumes:
      - /tmp:/build-temp
EOF
fi
```

```bash
# entrypoint.sh:109-111 — staging runs as root before the runner user starts
setpriv --reuid=docker --regid=docker --init-groups \
    env HOME=/home/docker "${RUNNER_START_SCRIPT}" &
```

```dockerfile
# Dockerfile:53-59 — today's baked SSH material: no known_hosts, fixed ownership
RUN mkdir -p /home/docker/.ssh
COPY ./ssh/id_rsa /home/docker/.ssh/id_rsa
COPY ./ssh/id_rsa.pub /home/docker/.ssh/id_rsa.pub
COPY ./ssh/config /home/docker/.ssh/config
RUN chmod 0700 /home/docker/.ssh && \
    chmod 0600 /home/docker/.ssh/id_rsa /home/docker/.ssh/id_rsa.pub /home/docker/.ssh/config && \
    chown -R docker ~docker
```

## Gaps Identified

### Gap 1: No deployment SSH material reaches jobs

**Current Behavior:** The image carries only the host's GitHub key and config; there is no
organization-scoped mechanism for deployment keys, jump-host topology, or target host keys.
**Required Behavior:** A per-org folder mounted into the runner, staged for the runner user, and
included by the SSH client (R1–R6).
**Fix Required:** `fleet.sh` (option, mount), `entrypoint.sh` (staging), `.gitignore`,
`.dockerignore`.

### Gap 2: Unknown host keys fail non-interactively

**Current Behavior:** Host `known_hosts` never reaches the container (`Dockerfile:54-56`), and jobs
cannot answer the host-key prompt; SSH to an unlisted server fails.
**Required Behavior:** Pinned host keys in the folder are used via `UserKnownHostsFile`; the check
script surfaces missing keys and prints installable lines (R5, R7, R8).
**Fix Required:** Docs template for `known_hosts`, the check/learn script, and its wiring.

### Gap 3: No way to verify or learn connections from inside the runner

**Current Behavior:** Operators can only discover problems when a deploy job fails.
**Required Behavior:** `deploy-ssh-check` + `fleet.sh check-ssh` diagnose connectivity and host-key
pinning from the runner's exact vantage point (R7–R9).
**Fix Required:** New script, `fleet.sh` subcommand, image and installer packaging.

## Dependencies

### Internal Dependencies

- `fleet.sh` renderer and validator patterns (`fleet.sh:122-131`, `fleet.sh:164-209`).
- Entrypoint root-side staging (before `setpriv`, `entrypoint.sh:109`).
- Existing test harnesses and stubs (`test/*.spec.test.sh`, `test/*.impl.test.sh`).
- VitePress sidebar configuration (`docs/.vitepress/config.mts:41-85`).

### External Dependencies

- None new. The image already provides `openssh-client` (including `ssh-keyscan` and `ssh-keygen`)
  and `rsync` (`Dockerfile:13-15`).

## Risks and Concerns

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Deploy keys are readable by every job of the organization | Certain by design | Medium | Documented trust boundary; per-org folders only; private repos only (`docs/architecture/security.md`) |
| Operators disable host-key checking to "make it work" | Medium | High | Pinning is the documented default; `--learn` produces keys; disabling is marked unsafe |
| Stale container copy diverges from the host folder | Low | Low | Staging is remove-and-copy at every boot; rotation procedure documented (AR #22) |
| User runs new `fleet.sh` with an old image | Medium | Low | Documented: rebuild the image; mixed versions are inert, not failing (AR #23) |
| Wildcard `Host` entries cannot be tested by the check | Medium | Low | Patterns are listed as skipped; explicit hostnames supported (AR #19) |
