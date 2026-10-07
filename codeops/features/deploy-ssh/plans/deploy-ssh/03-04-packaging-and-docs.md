# Packaging and Documentation: deploy-ssh

> **Document**: 03-04-packaging-and-docs.md
> **Parent**: [Index](00-index.md)

## Overview

This component ships the check script with the image and the installer, keeps the deploy folder out
of git and Docker build contexts, and documents the operator workflows. It also records the
mixed-version behavior: the feature activates only after the image carrying the new entrypoint is
built (AR #23).

## Architecture

### Current Architecture

- Runtime files are installed by `bootstrap.sh` from `INSTALL_FILES` and recorded in
  `.build-server-manifest` (`bootstrap.sh:368-376`, `bootstrap.sh:431-455`).
- The image copies `start.sh` and `entrypoint.sh` and marks them executable
  (`Dockerfile:42-44`).
- `test/verify.sh` runs shellcheck on a fixed file list and executes every test file explicitly
  (`test/verify.sh:10-23`).
- The docs site is VitePress, with a hand-written sidebar (`docs/.vitepress/config.mts:41-85`).

### Proposed Changes

| Change | Location |
| ------ | -------- |
| Install the check script into the image | `Dockerfile` |
| Install the check script on the host | `bootstrap.sh` `INSTALL_FILES` |
| Ignore the deploy folder | `.gitignore`, `.dockerignore` |
| Wire tests and lint | `test/verify.sh` (file lists) |
| New guide page + sidebar entry | `docs/guide/deploy-ssh.md`, `docs/.vitepress/config.mts` |
| Updates to existing pages | `docs/guide/organizations.md`, `docs/guide/cli.md`, `docs/reference/files.md`, `docs/architecture/security.md`, `docs/operations/upgrades.md`, `docs/operations/troubleshooting.md` |

## Implementation Details

### Dockerfile

```dockerfile
# Deploy SSH connectivity check (installed for jobs and the operator).
COPY deploy-ssh-check.sh /usr/local/bin/deploy-ssh-check
RUN chmod +x /usr/local/bin/deploy-ssh-check
```

The copy joins the existing script-installation block (`Dockerfile:42-44`). No package changes.

### bootstrap.sh

Add `deploy-ssh-check.sh` to `INSTALL_FILES`. Existing installs pick it up on the next bootstrap
run; the manifest loop removes files that disappear upstream, so no migration code is needed.

### Ignore files

- `.gitignore`: add `/deploy-ssh/` (root-anchored so the CodeOps feature folder `codeops/features/deploy-ssh/` is not shadowed) under the host-local secrets section (`ssh/` is the precedent).
- `.dockerignore`: add `deploy-ssh` so keys are never sent as build context (the Dockerfile does
  not copy the folder, but contexts should not carry secrets — AR #5).
- The R1 path restriction (PF-003) is what makes these fixed entries sufficient: every deploy
  folder lives under `deploy-ssh/`.

### verify.sh

The final state after all phases:

```bash
shellcheck -S style bootstrap.sh fleet.sh entrypoint.sh start.sh deploy-ssh-check.sh \
    test/*.sh examples/playground.sh

# ... existing tests ...
bash test/deploy-ssh-check.spec.test.sh
bash test/deploy-ssh-check.impl.test.sh
```

Phase 3's implementation step wires the script into shellcheck and the spec suite into `verify.sh`;
the impl suite line is added by the task that creates that file (PF-009). The committed example
`orgs.conf` is not changed to declare `deploy_ssh` — the option is documented, not exercised by the
default fleet (its grammar header is updated separately, PF-011).

### Spec-test additions

- `test/dockerfile.spec.test.sh`: assert the Dockerfile installs `/usr/local/bin/deploy-ssh-check`.
- `test/bootstrap.spec.test.sh`: provide `deploy-ssh-check.sh` in the fake repository, assert it is
  installed, and assert the manifest lists it (the fake repo and install loops currently enumerate
  runtime files explicitly).

### Documentation deliverables

| Page | Content |
| ---- | ------- |
| `docs/guide/deploy-ssh.md` *(new)* | Purpose; folder layout and `deploy_ssh=`; complete SSH config template including the **separate bastion `Host` block**; collecting and pinning host keys (keyscan on the bastion, `known_hosts` file); `accept-new` fallback note (PASS semantics); applying and refreshing (restart interrupts running jobs); `fleet.sh check-ssh` and `deploy-ssh-check --learn` with exit codes; explicit-host usage for pattern-only configs; multiple targets/keys/bastions and shared folders; rotation and backups; **manual live-fleet checklist** (ssh/scp/rsync through a bastion, pinned keys, exit codes); troubleshooting pointers; security notes (org-wide visibility, private repos only, never commit keys) |
| `docs/guide/organizations.md` | Add a `deploy_ssh=` row to the field table and an example line |
| `docs/guide/cli.md` | Add `check-ssh <org>` to the command table; note folder auto-creation on container-starting commands |
| `docs/reference/files.md` | File-map rows for `deploy-ssh/` (host folder) and `deploy-ssh-check.sh` (runtime file) |
| `docs/reference/testing.md` | Add the new `deploy-ssh-check` suites to the test-layout table |
| `docs/reference/faq.md` | Add `deploy-ssh/` to the credential-locations answer |
| `docs/guide/custom-images.md` | Note that self-contained custom images must provide the entrypoint staging and `/usr/local/bin/deploy-ssh-check` to support `deploy_ssh` and `check-ssh` |
| `docs/architecture/security.md` | Add `deploy-ssh/` to the credentials table and a consequence line about org-wide job visibility |
| `docs/operations/upgrades.md` | Add `deploy-ssh/` to the backup list; add the image-rebuild ordering note (AR #23) |
| `docs/operations/troubleshooting.md` | Entries for: host key verification failures (`--learn`), mount missing (option/`up`), include line missing (restart), unstaged folder (rebuild/warning), `start` with a missing folder |
| `docs/.vitepress/config.mts` | Sidebar entry `Deploy SSH` in the Guide section |
| `orgs.conf` header, `bootstrap.sh` generated header | Grammar gains `[deploy_ssh=<path>]` with a one-line description (PF-011) |

## Error Handling

| Error Case | Handling Strategy | AR Ref |
| ---------- | ----------------- | ------ |
| Installer runs against a repo missing the script | bootstrap fails with its existing "missing runtime file" error (never a half install) | #25 |
| Older install without the new image | Docs state the feature activates after `fleet.sh build`/`upgrade-all`; existing behavior is unchanged until then | #23 |
| Docs build link failure | The docs task runs `npm ci && npm run docs:build`; VitePress fails on broken links before completion | #26 |

> **Traceability:** Every error-handling strategy and design choice references the Ambiguity
> Register entry (AR #) that resolved it. See `00-ambiguity-register.md`.

## Testing Requirements

- Specification tests (see `07-testing-strategy.md`): ST-33..ST-35.
- Verification: `bash test/verify.sh` and `npm ci && npm run docs:build`.
