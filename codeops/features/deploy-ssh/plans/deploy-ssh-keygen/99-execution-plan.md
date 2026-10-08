# Task T-02: Deploy SSH starter files and key generation

> **Type**: Task (lightweight) · **Feature**: deploy-ssh · **CodeOps Artifact Schema**: 1
> **Progress**: 5/6 tasks (83%)
> **Reasoning**: medium — bounded CLI addition and starter-file seeding in existing, well-tested code
> **Phase baseline tree**: 8d1fd6914e2fb74d4d010f9771360630ac1d715c
> **Expected changes** (scope: strict): `fleet.sh`, `test/fleet.spec.test.sh`, `test/fleet.impl.test.sh`, `docs/guide/deploy-ssh.md`, `docs/guide/cli.md`, `docs/reference/files.md`, and the plan/roadmap documents (`99-execution-plan.md`, `00-review-report.md`, `codeops/features/deploy-ssh/00-roadmap.md`, `codeops/00-roadmap.md`)
> **Lenses**: security

## Objective

Ease deploy-ssh key management. Provisioning commands (`up`, `restart`, `start`, `update`,
`update-runners`, `upgrade-all`) seed a starter `config` and an empty `known_hosts` when missing —
never overwriting existing files — and a new `fleet.sh keygen <org> [name]` command generates a
dedicated key pair in the organization's `deploy-ssh/<slug>/keys/` folder and prints paste-ready
setup instructions.

**Smallest viable design:** extend the existing `ensure_deploy_dirs` seeding and reuse it from one
new subcommand that wraps `ssh-keygen` (already a host prerequisite, used by `bootstrap.sh`). No
new dependencies, no automatic configuration editing, no new runtime files. The template is fully
commented, so an untouched folder keeps today's behavior: no active `Host` block exists until the
operator uncomments one, and `check-ssh` never tests phantom hosts.

Confirmed with the operator (2026-10-08): seeding whenever a starter entry is missing (existing
files never overwritten); `keygen` may provision the folder; no passphrase support; the template
carries placeholders plus a direct example and a bastion example.

## Pinned behavior

- **Seeding:** during provisioning (and from `keygen`), create any missing `keys/`, `config`,
  `known_hosts`. `config` is written as the fully commented template below; `known_hosts` is
  created empty. Existing files are never modified. The repair path stays silent — the creation
  notice prints only when the folder itself was created (existing RV-004 rule).
- **Notice:** `fleet: created <rel> with starter files (edit config, add a key, then restart the
  runner to apply)` — the existing `created <rel>` substring stays stable for current assertions.
- **`keygen` interface:** `./fleet.sh keygen <org> [name] [--rsa] [--force]`.
  - `name` defaults to `id_ed25519`; valid names match `[A-Za-z0-9][A-Za-z0-9._-]*` and must not
    end with `.pub`; otherwise `invalid key name '<name>'`.
  - No passphrase (`-N ''`): the runner has no SSH agent, so a passphrase would hang every job.
  - `--rsa` selects `-t rsa -b 4096`; the default is `-t ed25519`. The comment uses the org slug.
  - Refuses to overwrite an existing key pair (either half) unless `--force`; with `--force` the
    old pair is removed first so `ssh-keygen` can never prompt on stdin.
  - Errors: missing org → usage; `unknown organization '<slug>'`; organization without
    `deploy_ssh` → `organization '<slug>' has no deploy_ssh configured`.
  - Output: the public key line, a paste-ready `Host` stanza using
    `IdentityFile ~/.ssh/deploy.d/keys/<name>`, and next-step hints (authorized_keys, restart,
    `check-ssh`). Exact wording is pinned by the spec tests.
- **Out of scope (confirmed):** editing `config` automatically, installing keys over the network
  (`ssh-copy-id`), any known_hosts helper (`deploy-ssh-check --learn` covers it).

**Modification set:** `fleet.sh`, `test/fleet.spec.test.sh`, `test/fleet.impl.test.sh`,
`docs/guide/deploy-ssh.md`, `docs/guide/cli.md`, `docs/reference/files.md`.

### Starter config template

```
# Deploy SSH configuration for this organization.
#
# This file is copied into the runner at ~/.ssh/deploy.d/config and included automatically;
# do not add an Include line yourself. After editing, run: ./fleet.sh restart
#
# Folder contents:
#   config       this file
#   known_hosts  pinned server host keys (collect with: deploy-ssh-check --learn <host>)
#   keys/        private keys referenced by IdentityFile (create with: ./fleet.sh keygen <org>)
#
# --- Direct target ---------------------------------------------------------------
#
# Host app-prod
#     HostName 192.168.1.1
#     User deploy
#     Port 22
#     IdentityFile ~/.ssh/deploy.d/keys/id_ed25519
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#
# --- Target behind a bastion -----------------------------------------------------
#
# Host app-private
#     HostName 10.20.1.5
#     User deploy
#     IdentityFile ~/.ssh/deploy.d/keys/id_ed25519
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#     ProxyJump deploy@bastion.example.com
#
# The bastion opens a separate SSH session and needs its own Host block (required):
#
# Host bastion.example.com
#     HostName bastion.example.com
#     User deploy
#     IdentityFile ~/.ssh/deploy.d/keys/bastion
#     UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
#     StrictHostKeyChecking yes
#
# Test from inside the runner:  ./fleet.sh check-ssh <org>
```

### Specification test cases (in `test/fleet.spec.test.sh`, ST-48..ST-56)

1. ST-48: `up` on a declared, missing folder seeds `config`, `known_hosts`, and `keys/` (0700) and
   prints the new notice.
2. ST-49: seeding never overwrites — sentinel `config`/`known_hosts` content survives `up`.
3. ST-50: repair seeding is silent — an existing folder with missing starter files gets them back
   without the creation notice.
4. ST-51: `keygen acmetools` (stub records `ssh-keygen` argv) creates the pair under `keys/` and
   prints the public key, the `~/.ssh/deploy.d/keys/id_ed25519` stanza, and the next-step hints.
5. ST-52: `keygen acmetools prod` names the pair `prod`.
6. ST-53: `keygen --rsa` records `-t rsa -b 4096`.
7. ST-54: overwrite protection — an existing key without `--force` fails with the message; with
   `--force` the pair is replaced.
8. ST-55: `keygen` errors — missing org (usage), unknown org, org without `deploy_ssh`, and an
   invalid key name.
9. ST-56: `keygen` on a missing folder seeds the starter files first (creation notice included).

Spec tests stub `ssh-keygen` (recording argv, writing canned key files) for determinism; the
implementation tests use the real `ssh-keygen`.

## Tasks

- [x] T-02.1 Extend `test/fleet.spec.test.sh` with ST-48..ST-56 and adjust any full-message notice
  expectations (`created <rel>` substring assertions stay valid) ✅ (completed: 2026-10-08 09:10)
- [x] T-02.2 Run the fleet spec suite and record the red-phase results (seeding and `keygen` cases
  fail; untouched cases stay green) ✅ (completed: 2026-10-08 09:10 — 33 existing sections green,
  then FAIL at ST-48 as expected)
- [x] T-02.3 Implement starter-file seeding in `fleet.sh`: a per-folder helper shared by
  `ensure_deploy_dirs` and `keygen` (change guard, 0700 modes, template heredoc, empty
  `known_hosts`, new notice) ✅ (completed: 2026-10-08 09:11 — ST-48..ST-50 green; the spec suite
  advances to the keygen cases; impl suite green)
- [x] T-02.4 Implement the `keygen` subcommand (argument parsing, validation, `--rsa`/`--force`,
  `ssh-keygen` invocation, paste-ready output) and its usage line ✅ (completed: 2026-10-08 09:12 —
  spec suite fully green, 42 sections; impl suite green)
- [x] T-02.5 Extend `test/fleet.impl.test.sh` (real `ssh-keygen`: private key is valid, `.pub`
  matches, mode 0600; repeated provisioning is byte-idempotent; `--force` replaces the pair) and
  run green ✅ (completed: 2026-10-08 09:13 — 21 impl sections green; the derived-key comparison
  trims the comment this ssh-keygen version prints)
- [~] T-02.6 Update docs (`docs/guide/deploy-ssh.md`, `docs/guide/cli.md`,
  `docs/reference/files.md`) and run the full verification ⏳ (implemented: 2026-10-08 09:13)

**Verify**: `bash test/verify.sh`; because docs change, also `npm ci && npm run docs:build`
