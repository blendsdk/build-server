# Requirements: deploy-ssh

> **Document**: 01-requirements.md
> **Parent**: [Index](00-index.md)
> **Risk tags**: security

## Feature Overview

The fleet's runner containers must be able to deploy files and run commands on internal servers
over SSH, including through a jump (bastion) host, where private targets may only be reachable from
that bastion. Today every repository would have to wire its own setup into CI/CD, and non-interactive
jobs fail on unknown host keys. This feature makes the capability an operator-managed part of the
runner fleet: a per-organization folder on the host, mounted into that organization's runner and
wired into the SSH client by the container entrypoint. Jobs then use plain `ssh`, `scp`, `rsync`, and
`git` with no additional steps.

The plan is a standalone plan: this document owns the requirements. Every decision traces to the
[Ambiguity Register](00-ambiguity-register.md).

## Functional Requirements

### Must Have

- [ ] **R1 — Declare a deploy folder per organization.** `orgs.conf` accepts an optional
  `deploy_ssh=<relative path>` key per organization. The path must be a strict subdirectory of
  `deploy-ssh/` (amending the AR #3 note per PF-003) and is rejected when empty, absolute,
  containing `..`, or containing `*`, `?`, `[`, `:`, or `$`, and when the resolved path escapes the
  repository through a symlink, points at an existing non-directory, equals the repository root, or
  equals bare `deploy-ssh` itself (AR #12, AR #16).
- [ ] **R2 — Create a missing folder.** When a declared path does not exist, the container-starting
  commands (`up`, `restart`, `start`, `update`, `update-runners`, `upgrade-all`) create the folder
  and its `keys/` subdirectory with `0700` modes and print a notice; for `upgrade-all` this happens
  after confirmation and the version fetch, immediately before `compose up`. `generate`, `status`,
  `down`, `stop`, and `clean` never create anything (AR #15, refined by PF-007). Host folders are
  never deleted, even when the option is removed (AR #17).
- [ ] **R3 — Mount the folder read-only.** Each declaring organization's generated service mounts
  its folder at `/run/deploy-ssh` with the `:ro` flag. Multiple organizations may declare the same
  path; the mount works independently per service (AR #4, AR #13). The `deploy-ssh/` directory and
  its contents are gitignored and excluded from Docker build contexts — guaranteed by the R1 path
  restriction (AR #5, AR #3).
- [ ] **R4 — Stage the material for the runner user.** When `/run/deploy-ssh` exists, the entrypoint
  removes any previous `~/.ssh/deploy.d`, copies the folder there, applies `chown docker:docker` and
  restrictive modes (files `600`, directories `700`), and logs a success line. When the mount is
  absent, it does nothing. Copy, ownership, or mode failures produce a warning and never prevent the
  runner from starting (AR #5, AR #9, AR #14).
- [ ] **R5 — Wire the deploy config into SSH.** When the staged folder contains `config`, the
  entrypoint prepends `Include ~/.ssh/deploy.d/config` to the runner user's `~/.ssh/config`, exactly
  once across repeated boots (AR #10). The file contract is `config`, `known_hosts`, and `keys/`
  (AR #4).
- [ ] **R6 — Plain SSH tools work.** After staging, `ssh <host>`, `scp`, `rsync`, and `git` resolve
  the operator's `Host` blocks, including `ProxyJump`, `IdentityFile`, `UserKnownHostsFile`, and
  `StrictHostKeyChecking`, with no job-side wrapper and no CI setup (AR #1, AR #2).
- [ ] **R7 — Connectivity check.** The image provides `deploy-ssh-check`:
  - without arguments it tests every literal hostname found in `Host` lines of the deploy config and
    lists pattern entries (`*`, `?`, `!`) as skipped;
  - explicit host arguments override the default selection;
  - it exits `0` when all tested hosts pass, `1` when any host fails, and `2` for usage or
    configuration errors;
  - it never weakens host-key verification (AR #7, #19, #20).
- [ ] **R8 — Learn host keys.** `deploy-ssh-check --learn <host>...` requires at least one host,
  parses the jump specification, resolves the effective `HostName`/`HostKeyAlias`/port/user through
  `ssh -G` for both the target and the bastion, scans the resolved names, and prints ready-to-paste
  `known_hosts` lines keyed to the name SSH verifies. If the bastion's key is not pinned, it prints
  the exact `ssh-keyscan` line plus the requirement that the deploy config contain a matching
  bastion `Host` block, and skips that host. Failures are per host: it continues with the remaining
  hosts and exits non-zero when any failed. It never writes files and never weakens verification
  (AR #6, AR #8, AR #19, refined by PF-001, PF-002, PF-012).
- [ ] **R9 — Operator convenience.** `fleet.sh check-ssh <org>` runs the check inside that
  organization's runner as the `docker` user and propagates the exit code. Exactly one organization
  argument is required; unknown organizations and organizations without `deploy_ssh` fail fast with
  clear messages, and a non-running container produces Compose's own error (AR #11, AR #18, refined
  by PF-008).
- [ ] **R10 — Packaging.** `deploy-ssh-check.sh` is installed into the image as
  `/usr/local/bin/deploy-ssh-check`, added to `bootstrap.sh`'s installed runtime files, and wired
  into `shellcheck` and `verify.sh` (AR #25).
- [ ] **R11 — Documentation.** A guide page documents setup, the SSH config template (including the
  separate bastion block), host-key pinning, the check/learn flow, rotation, troubleshooting, and
  the manual live-fleet checklist; the sidebar links it; the reference, security, upgrades,
  troubleshooting, CLI, organizations, `reference/testing.md`, `reference/faq.md`, and
  `guide/custom-images.md` pages are updated; and the `orgs.conf` and bootstrap-generated grammar
  headers gain the option (AR #26, PF-011, PF-014, PF-015).

### Should Have

- [ ] **R12 — Clear operator feedback.** Auto-create, staging success/failure, check results, and
  learn output each name the affected folder, host, or organization so problems can be located
  without reading source code (AR #15, #20, AR #26).

### Won't Have (Out of Scope)

- A CI-side per-job setup script or GitHub-secret provisioning (AR #2, AR #27).
- Per-repository or per-environment key granularity; folders are org-scoped (AR #1, AR #27).
- SSH agent forwarding, SSH certificate authority integration, and password authentication
  (AR #27).
- Automatic connection checks at container boot (AR #7).
- `StrictHostKeyChecking accept-new` as the default; it remains a documented fallback only
  (AR #6).
- Live re-sync of changed folder contents into running containers (AR #22).
- A version/compatibility gate inside `fleet.sh` (AR #23).
- Changes to `fleet.sh status` output (AR #21).
- Chained (`ProxyJump a,b`) learning support; single-hop jumps only, documented (AR #27).

## Technical Requirements

### Compatibility

- Ubuntu 24.04 with the image's OpenSSH client (`openssh-client`, `Dockerfile:13-15`); Bash 5
  features already used by the fleet are allowed.
- No new packages or dependencies.
- Mixed versions: an image built before this feature ignores the mount and the option has no effect
  until the image is rebuilt; configurations without `deploy_ssh` are unaffected (AR #23).
- Existing checks stay green: `fleet.sh generate` idempotence, atomic output behavior, and the
  committed example `orgs.conf` remain valid without the new option.

### Verification

- The project verify command is `bash test/verify.sh` (documented in `AGENTS.md`): shellcheck plus
  all spec and implementation tests.
- Documentation changes verify with `npm ci && npm run docs:build` (documented in `AGENTS.md`).

### Performance

- No hot paths: all behavior is operator-time or container-boot-time. Staging copies a small folder;
  the check incurs one SSH connection per tested host with a 5 s connect timeout.

## Security Requirements

- **Path safety:** `deploy_ssh` is validated as described in R1 before any file or mount action; the
  repository root is rejected (AR #12, AR #16).
- **Exposure boundary:** deploy keys live on the host and are readable by every job of that
  organization's runner — the same documented trust model as the baked `~/.ssh/id_rsa`
  (`docs/architecture/security.md:21-27`); folders are never shared across organizations unless the
  operator explicitly declares the same path (AR #1, AR #13).
- **At-rest handling:** the host folder is created `0700`; the staged copy is `0600`/`700` and owned
  by the unprivileged runner user; the container mount is read-only (AR #4, AR #5).
- **Host-key verification:** pinning is the recommended path; `--learn` never weakens verification;
  the check does not disable host-key checking; disabling verification is documented as unsafe and
  never produced by tooling (AR #6, AR #8).
- **No secret leakage:** no script prints private key material; `known_hosts` output is public key
  data; the folder is excluded from git and Docker build contexts (AR #5, AR #25).

## Scope Decisions

| Decision | Options Considered | Chosen | Rationale | AR Ref |
| -------- | ------------------ | ------ | --------- | ------ |
| Delivery surface | Host folder, CI-side setup script | Host folder | Targets change rarely; matches persistent runners and the existing credentials model | AR #1, #2 |
| Enablement | Opt-in per org, always-on | Opt-in | Least privilege; nothing mounted for organizations that do not deploy | AR #3 |
| Mount handling | Direct writable mount, read-only + root copy | Read-only + copy | Host uid is not guaranteed inside; jobs must not mutate host keys | AR #5, #14 |
| Host-key policy | Pin, `accept-new`, disabled | Pin (fallback `accept-new`) | Deploy sessions are hijackable if unchecked; pinning suits stable targets | AR #6, #8 |
| Check tooling | Script only, script + CLI command | Script + `fleet.sh check-ssh` | Operators already work through the admin CLI; the raw Compose exec line is error-prone | AR #7, #11, #18 |
| Cleanup | Never delete, prune with `clean` | Never delete | Removal must be explicit and manual; `fleet.sh` never touches user files | AR #17 |

> **Traceability:** Every scope decision references the Ambiguity Register entry (AR #) that
> resolved it. See `00-ambiguity-register.md`.

## Acceptance Criteria

1. [ ] `./fleet.sh up` with a declared `deploy_ssh` folder mounts it read-only at `/run/deploy-ssh`
   and creates the folder if missing (`0700`, with `keys/`).
2. [ ] A started runner has `~/.ssh/deploy.d/` owned by the runner user with `600`/`700` modes and a
   first-line `Include ~/.ssh/deploy.d/config` exactly once.
3. [ ] A job in that organization can run `ssh`, `scp`, and `rsync` against a configured target,
   including through a `ProxyJump` bastion, with no repository-side setup.
4. [ ] `deploy-ssh-check` reports per-host PASS/FAIL, exits `0`/`1`/`2` as specified, and lists
   skipped patterns.
5. [ ] `deploy-ssh-check --learn` prints installable `known_hosts` lines, or the bastion keyscan
   instruction when the bastion is not pinned yet.
6. [ ] `fleet.sh check-ssh <org>` runs the check in the runner and propagates its exit code.
7. [ ] `bash test/verify.sh` passes; `npm ci && npm run docs:build` passes.
8. [ ] Documentation covers setup, pinning, rotation, and troubleshooting.
