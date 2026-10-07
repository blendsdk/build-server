# Container Staging: deploy-ssh

> **Document**: 03-02-container-staging.md
> **Parent**: [Index](00-index.md)

## Overview

The entrypoint runs as root before dropping privileges to the `docker` user (`entrypoint.sh:109`).
It uses that window to materialize the read-only `/run/deploy-ssh` mount into the runner user's
home, with correct ownership and modes, and to wire the deploy config into the SSH client.

## Architecture

### Current Architecture

- The entrypoint starts `dockerd`, waits for readiness, adjusts the daemon socket, and then runs
  `/start.sh` through `setpriv` with `HOME=/home/docker` (`entrypoint.sh:61-111`).
- Behavior is parameterized for tests through environment variables such as `DOCKERD_LOG` and
  `DOCKER_READY_ATTEMPTS` (`entrypoint.sh:11-16`).
- The image's `~/.ssh` material is owned by `docker:docker` with `0700`/`0600` modes
  (`Dockerfile:57-59`).

### Proposed Changes

| Change | Location |
| ------ | -------- |
| Two overridable paths: `DEPLOY_SSH_SOURCE` (default `/run/deploy-ssh`), `RUNNER_USER_HOME` (default `/home/docker`) | `entrypoint.sh` header block |
| `stage_deploy_ssh()` — remove, copy, modes, ownership, `Include` line | `entrypoint.sh`, called before the `setpriv` line |
| The `setpriv` call uses `${RUNNER_USER_HOME}` instead of the literal `/home/docker` | `entrypoint.sh:110` |

## Implementation Details

### Staging algorithm

```
stage_deploy_ssh():
  if DEPLOY_SSH_SOURCE is not a directory:            # no mount: nothing to do
      return 0
  if RUNNER_USER_HOME/.ssh is missing:                # fresh or overridden home
      create it 0700, chown docker:docker            # mkdir fails -> warn and return 0;
                                                     # chmod/chown fail -> warn and continue
  if removing ~/.ssh/deploy.d fails:                  # AR #14: always a fresh copy
      warn (naming the step), return 0                # AR #9: never block the runner
  if creating ~/.ssh/deploy.d fails:
      warn (naming the step), return 0
  if copying DEPLOY_SSH_SOURCE/. into the target fails:
      warn (naming source and target); remove the partial target; return 0
  normalize modes per type: directories 700, files 600
      (find -P <target> -type d -exec chmod 700 {} + / -type f -exec chmod 600 {} +; failure -> warn)
  chown -R docker:docker the target     (failure -> warn)
  if the target contains a file named config:
      if ~/.ssh/config exists and is a symlink:       # root never writes through a link
          warn and skip the include
      else:
          ensure ~/.ssh/config exists
          if it does not already contain the line exactly:
              prepend Include ~/.ssh/deploy.d/config using a fresh mktemp file inside ~/.ssh
          chmod go-rwx and chown docker:docker ~/.ssh/config (failures -> warn)
  log: Deploy SSH staged from <source>
```

- **Ownership and modes:** the mount keeps host uids, which need not match the container's `docker`
  user; the root-side copy fixes both. Modes are normalized per type — directories `700`, files
  `600` — regardless of the source modes (`chown -R docker:docker`; AR #5, PF-004).
- **Fresh copy per boot:** the target is removed before copying so a shrunk or renamed source never
  leaves stale files behind (AR #14). The mount itself is never modified (AR #5).
- **Include line:** exactly one occurrence, prepended so deploy `Host` blocks take precedence over
  the baked host config for the same fields (AR #10). No `config` file means no include line — an
  org may stage keys only.
- **No mount:** the function returns immediately; no directories are created or removed (AR #14).

The function runs after the daemon is ready and before `setpriv`, so the runner user finds a
complete `~/.ssh` from its first job.

### Test overrides

`DEPLOY_SSH_SOURCE` and `RUNNER_USER_HOME` exist so tests can point the staging at fixture
directories, matching the existing override pattern (`entrypoint.sh:11-16`). Production values are
the defaults; no behavior changes with them.

## Code Examples

### Example 1: Failures never block the runner

```text
WARNING: deploy-ssh staging failed to copy /run/deploy-ssh to /home/docker/.ssh/deploy.d; the runner starts without deploy SSH
Starting Docker daemon...
```

The warning goes to stderr and names the failed step and paths; the container start sequence is
unchanged (AR #9).

## Error Handling

| Error Case | Handling Strategy | AR Ref |
| ---------- | ----------------- | ------ |
| Mount absent | No-op; no directories touched | #14 |
| `~/.ssh` missing (fresh or overridden home) | Created `0700` and owned by `docker` before staging | SA-102 |
| Target removal, creation, or copy fails | Warning naming the failed step plus source/target; a partial copy is removed; runner continues without deploy SSH | #9, RV-102, SA-102 |
| `chmod`/`chown` fails | Warning; continues (the runner may still be usable, and `deploy-ssh-check` will expose the problem) | #9 |
| `~/.ssh/config` missing | Created before the include line is added | #10 |
| `~/.ssh/config` is a symlink | Warning; the include is skipped so root never writes through a link | SA-101 |
| `config` already includes the line | Nothing added; repeated boots stay idempotent | #10 |
| Mount present but empty | Empty `deploy.d` is staged; no include line; `deploy-ssh-check` exits 2 with the missing-configuration message | #4, #9 |

> **Traceability:** Every error-handling strategy and design choice references the Ambiguity
> Register entry (AR #) that resolved it. See `00-ambiguity-register.md`.

## Testing Requirements

- Specification tests (see `07-testing-strategy.md`): ST-14..ST-19, ST-43..ST-45. The entrypoint
  spec harness changes required by ST-14 are specified in `07-testing-strategy.md` §Test Data
  (permissive fixture, recording `chown` stub, sandbox-guarded delegating `chmod` stub).
- Implementation tests: warn-and-continue paths for mode/ownership failures, a source containing
  only a `config`, repeated boots against alternated sources, and preservation of a pre-existing
  `~/.ssh/config`.
