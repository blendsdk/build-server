# Execution Plan: deploy-ssh

> **Document**: 99-execution-plan.md
> **Parent**: [Index](00-index.md)
> **Last Updated**: 2026-10-07 15:23
> **Progress**: 3/39 tasks (8%)
> **CodeOps Artifact Schema**: 1

## Overview

Implements the host-mounted deploy SSH material (`deploy_ssh=` in `orgs.conf`, read-only mount,
entrypoint staging and SSH wiring), the `deploy-ssh-check` script with `--learn`, the
`fleet.sh check-ssh` command, and the packaging and documentation around them. See
[`00-index.md`](00-index.md) for the overview and [`01-requirements.md`](01-requirements.md) for
the requirements.

**🚨 Update this document after EACH completed task!**

---

## Implementation Phases

| Phase | Title | Tasks |
| ----- | ----- | ----- |
| 1 | Fleet configuration and mounting | 11 |
| 2 | Container staging | 7 |
| 3 | Connectivity check | 9 |
| 4 | Packaging, documentation, and release validation | 12 |

**Total: 39 tasks across 4 phases** (no fabricated hour estimates — scope is bounded by the
task-size criteria in `quality-checklist.md`)

> **⚠️ EXECUTION RULE — APPLIES TO EVERY AGENT EXECUTING THIS PLAN:**
>
> The task checkboxes in the phase sections below are the **single source of truth** for
> progress. Every task line appears exactly once in this document. The executing agent MUST:
>
> 1. **On implementation:** mark the task `[~]` with a timestamp —
>    `- [~] 1.1.1 Task description ⏳ (implemented: YYYY-MM-DD HH:MM)`
> 2. **On verify pass:** promote it to `[x]` —
>    `- [x] 1.1.1 Task description ✅ (completed: YYYY-MM-DD HH:MM)`
> 3. **Update the Progress header** (`> **Progress**: X/Y tasks (Z%)`) and the Last Updated
>    stamp after EVERY task — never batch updates. Only `[x]` counts as complete.
> 4. **Resume** by scanning the phase sections top-to-bottom: the first `[~]` task is resumed
>    first, else the first `[ ]` task.
> 5. **On blocker:** mark the task `[!]` and append `Blocked: <short reason>` on the same line.
>    The plan lifecycle is `Ready`, `Executing`, `Done`, or `Blocked`, derived from these markers.
>
> Timestamps come from `date '+%Y-%m-%d %H:%M'` — never invented. Failure to keep the marks
> current means progress is invisible after crashes, context resets, or session handoffs.

---

## Phase 1: Fleet configuration and mounting

> **Phase baseline tree**: 2abaea015d0e0e1a8c63c63e2274273a7eb40f9f
> **Expected changes** (scope: strict): `fleet.sh`, `test/orgs.spec.test.sh`, `test/fleet.spec.test.sh`, `test/fleet.impl.test.sh`, `test/dockerfile.spec.test.sh`, `.gitignore`, `.dockerignore`, `codeops/features/deploy-ssh/plans/deploy-ssh/99-execution-plan.md`
> **Lenses**: security
> **Reasoning**: high — path validation is security-relevant and the renderer feeds every runner

### Step 1.1: Specification tests

**Reference**: [`03-01-orgs-configuration.md`](03-01-orgs-configuration.md) · AR #3, #12, #15, #16, #17
**Objective**: Pin the parser, validation, auto-create, and rendering behavior as failing tests first.

- [x] 1.1.1 [spec-author] Write the parser and rendering spec cases ST-1..ST-10, ST-38, ST-41 — `test/orgs.spec.test.sh` ✅ (completed: 2026-10-07 15:22)
- [x] 1.1.2 [spec-author] Write the auto-create and never-delete spec cases ST-11..ST-13 — `test/fleet.spec.test.sh` ✅ (completed: 2026-10-07 15:22)
- [x] 1.1.3 Run both spec suites and record the red-phase results (behavior-adding cases fail; negative/regression cases ST-2, ST-12, ST-13 pass in red; existing cases stay green) ✅ (completed: 2026-10-07 15:23)

> Mark spec-test tasks with `[spec-author]`: in a repo with an active quality profile, the
> exec-plan skill dispatches the spec-test-author agent for them; the marker is inert without a
> profile and the session writes the tests itself.

**Deliverables**:
- [x] ST-1..ST-13, ST-38, ST-41 exist; behavior-adding cases fail in red (ST-2, ST-12, ST-13 pass in red)

**Verify**: `bash test/orgs.spec.test.sh && bash test/fleet.spec.test.sh` (expected red)

---

### Step 1.2: Implementation

**Reference**: [`03-01-orgs-configuration.md`](03-01-orgs-configuration.md) §Implementation Details
**Objective**: Parse and validate the option, create missing folders, render the mount.

- [ ] 1.2.1 Add `deploy_ssh` parsing and validation to `parse_config()` — `fleet.sh`
- [ ] 1.2.2 Add `ensure_deploy_dirs()` and call it from `up`/`restart`/`start`/`update`/`update-runners`/`upgrade-all` (for `upgrade-all`: after confirmation and version fetch — PF-007) — `fleet.sh`
- [ ] 1.2.3 Render the read-only deploy volume, merged with `build_temp` under one `volumes:` key — `fleet.sh`
- [ ] 1.2.4 Run the Phase 1 spec cases; verify green

**Deliverables**:
- [ ] `generate` renders the mount; unsafe paths fail with line-numbered messages
- [ ] Container-starting commands create missing folders (`0700` + `keys/`); `generate`/`status` do not

**Verify**: `bash test/orgs.spec.test.sh && bash test/fleet.spec.test.sh`

---

### Step 1.3: Implementation tests, hygiene, and hardening

**Reference**: [`07-testing-strategy.md`](07-testing-strategy.md) §Implementation Tests · PF-005
**Objective**: Author ST-35 before the ignore entries, cover internals, and exclude the folder from git and build contexts.

- [ ] 1.3.1 [spec-author] Author the ignore-file spec case ST-35 and record its red phase — `test/dockerfile.spec.test.sh`
- [ ] 1.3.2 Extend `test/fleet.impl.test.sh` (auto-create on `restart`/`update`/`update-runners`/`upgrade-all`, idempotent rendering, validation failure preserves the previous output, sentinel files survive `clean --yes`/`upgrade-all --yes`) — `test/fleet.impl.test.sh`
- [ ] 1.3.3 Add `deploy-ssh/` to `.gitignore` and `deploy-ssh` to `.dockerignore`
- [ ] 1.3.4 Full verification — `bash test/verify.sh`

**Deliverables**:
- [ ] All Phase 1 behavior covered; keys never enter git or build contexts

**Verify**: `bash test/verify.sh`

---

## Phase 2: Container staging

> **Phase baseline tree**: _(recorded by the exec-plan skill from a temporary-index snapshot)_
> **Lenses**: security
> **Reasoning**: high — credential ownership/modes and non-fatal failure semantics

### Step 2.1: Specification tests

**Reference**: [`03-02-container-staging.md`](03-02-container-staging.md) · AR #4, #5, #9, #10, #14
**Objective**: Pin staging behavior (copy, modes, include, tolerance) as failing tests first.

- [ ] 2.1.1 [spec-author] Write the staging spec cases ST-14..ST-19 — `test/entrypoint.spec.test.sh`
- [ ] 2.1.2 Run the entrypoint spec suite and record the red-phase results (behavior-adding cases fail; ST-16 and ST-17 pass in red)

**Deliverables**:
- [ ] ST-14..ST-19 exist; behavior-adding cases fail in red (ST-16 and ST-17 pass in red)

**Verify**: `bash test/entrypoint.spec.test.sh` (expected red)

---

### Step 2.2: Implementation

**Reference**: [`03-02-container-staging.md`](03-02-container-staging.md) §Implementation Details
**Objective**: Stage the mount for the runner user and wire the SSH include.

- [ ] 2.2.1 Add `DEPLOY_SSH_SOURCE` and `RUNNER_USER_HOME` overrides; use `RUNNER_USER_HOME` for the runner `HOME` — `entrypoint.sh`
- [ ] 2.2.2 Implement `stage_deploy_ssh()` (fresh copy, modes, ownership, include line, warnings, success log) and call it before `setpriv` — `entrypoint.sh`
- [ ] 2.2.3 Run the entrypoint spec cases; verify green

**Deliverables**:
- [ ] A started runner has `~/.ssh/deploy.d` owned by `docker` with `600`/`700` modes and the include line exactly once
- [ ] Staging failures warn and never block the runner

**Verify**: `bash test/entrypoint.spec.test.sh`

---

### Step 2.3: Implementation tests and hardening

**Reference**: [`07-testing-strategy.md`](07-testing-strategy.md) §Implementation Tests
**Objective**: Cover failure tolerance and re-copy internals.

- [ ] 2.3.1 Extend `test/entrypoint.impl.test.sh` (chmod/chown failure warnings, keys-only source, source changes between boots, staging order before the runner user) — `test/entrypoint.impl.test.sh`
- [ ] 2.3.2 Full verification — `bash test/verify.sh`

**Deliverables**:
- [ ] Edge and failure paths covered

**Verify**: `bash test/verify.sh`

---

## Phase 3: Connectivity check

> **Phase baseline tree**: _(recorded by the exec-plan skill from a temporary-index snapshot)_
> **Lenses**: security
> **Reasoning**: high — host-key verification semantics drive operator trust decisions

### Step 3.1: Specification tests

**Reference**: [`03-03-connectivity-check.md`](03-03-connectivity-check.md) · AR #6, #7, #8, #18, #19, #20
**Objective**: Pin check/learn behavior and the CLI wrapper as failing tests first.

- [ ] 3.1.1 [spec-author] Write the check-script spec cases ST-20..ST-28, ST-36, ST-37, ST-39 — `test/deploy-ssh-check.spec.test.sh`
- [ ] 3.1.2 [spec-author] Write the `check-ssh` spec cases ST-29..ST-32, ST-40 — `test/fleet.spec.test.sh`
- [ ] 3.1.3 Run the spec cases and record the red-phase results (all fail in red because the script does not exist; ST-30 may pass in red if it asserts only a generic usage failure)

**Deliverables**:
- [ ] ST-20..ST-32, ST-36, ST-37, ST-39, ST-40 exist and fail for the expected reason

**Verify**: `bash test/deploy-ssh-check.spec.test.sh && bash test/fleet.spec.test.sh` (expected red)

---

### Step 3.2: Implementation

**Reference**: [`03-03-connectivity-check.md`](03-03-connectivity-check.md) §Implementation Details
**Objective**: Implement the script and the `check-ssh` command; wire tests and lint.

- [ ] 3.2.1 Write `deploy-ssh-check.sh` (test mode, `--learn`, exit codes, `Host` parsing, strict host-key handling) — `deploy-ssh-check.sh`
- [ ] 3.2.2 Add the `check-ssh <org>` command and usage line — `fleet.sh`
- [ ] 3.2.3 Wire `deploy-ssh-check.sh` into the shellcheck list and the spec suite into `test/verify.sh` (the impl suite is wired in 3.3.1 — PF-009) — `test/verify.sh`
- [ ] 3.2.4 Run the Phase 3 spec cases; verify green

**Deliverables**:
- [ ] `deploy-ssh-check` reports PASS/FAIL with exit codes 0/1/2 and learns keys without weakening verification
- [ ] `fleet.sh check-ssh <org>` runs it and propagates the exit code

**Verify**: `bash test/deploy-ssh-check.spec.test.sh && bash test/fleet.spec.test.sh`

---

### Step 3.3: Implementation tests and hardening

**Reference**: [`07-testing-strategy.md`](07-testing-strategy.md) §Implementation Tests
**Objective**: Cover parsing edges and failure paths.

- [ ] 3.3.1 Write `test/deploy-ssh-check.impl.test.sh` (parsing edges, empty keyscan output, bastion authentication failure, chained jumps, mixed results) and add it to `test/verify.sh` — `test/deploy-ssh-check.impl.test.sh`
- [ ] 3.3.2 Full verification — `bash test/verify.sh`

**Deliverables**:
- [ ] Edge and failure paths covered

**Verify**: `bash test/verify.sh`

---

## Phase 4: Packaging, documentation, and release validation

> **Phase baseline tree**: _(recorded by the exec-plan skill from a temporary-index snapshot)_
> **Reasoning**: low — packaging and documentation with deterministic verification

### Step 4.1: Specification tests

**Reference**: [`03-04-packaging-and-docs.md`](03-04-packaging-and-docs.md) · AR #23, #24, #25, #26
**Objective**: Pin the image and installer wiring as failing static assertions first.

- [ ] 4.1.1 [spec-author] Add the image-install spec case ST-33 — `test/dockerfile.spec.test.sh`
- [ ] 4.1.2 [spec-author] Add the installer spec case ST-34 — `test/bootstrap.spec.test.sh`
- [ ] 4.1.3 Run the spec suites and record the red-phase results (ST-33 and ST-34 fail in red; ST-35 was authored and verified in Phase 1)

**Deliverables**:
- [ ] ST-33 and ST-34 exist and fail for the expected reason

**Verify**: `bash test/dockerfile.spec.test.sh && bash test/bootstrap.spec.test.sh` (expected red)

---

### Step 4.2: Implementation

**Reference**: [`03-04-packaging-and-docs.md`](03-04-packaging-and-docs.md) §Implementation Details
**Objective**: Ship the script with the image and the installer.

- [ ] 4.2.1 Install `deploy-ssh-check.sh` as `/usr/local/bin/deploy-ssh-check` — `Dockerfile`
- [ ] 4.2.2 Add `deploy-ssh-check.sh` to `INSTALL_FILES` — `bootstrap.sh`
- [ ] 4.2.3 Update the grammar headers with `[deploy_ssh=<path>]` — `orgs.conf`, `bootstrap.sh` (PF-011)
- [ ] 4.2.4 Run the Phase 4 spec suites; verify green

**Deliverables**:
- [ ] New and existing installs carry the script; the manifest records it

**Verify**: `bash test/dockerfile.spec.test.sh && bash test/bootstrap.spec.test.sh`

---

### Step 4.3: Implementation tests, documentation, and hardening

**Reference**: [`03-04-packaging-and-docs.md`](03-04-packaging-and-docs.md) §Documentation deliverables · AR #26
**Objective**: Publish the operator documentation and validate the release.

- [ ] 4.3.1 Write the guide page (including the manual live-fleet checklist — PF-014) and add the sidebar entry — `docs/guide/deploy-ssh.md`, `docs/.vitepress/config.mts`
- [ ] 4.3.2 Update the option and command references — `docs/guide/organizations.md`, `docs/guide/cli.md`, `docs/reference/files.md`
- [ ] 4.3.3 Update security, upgrade, troubleshooting, and the stale reference pages — `docs/architecture/security.md`, `docs/operations/upgrades.md`, `docs/operations/troubleshooting.md`, `docs/reference/testing.md`, `docs/reference/faq.md`, `docs/guide/custom-images.md`
- [ ] 4.3.4 Build the documentation site — `npm ci && npm run docs:build`
- [ ] 4.3.5 Full verification — `bash test/verify.sh`

**Deliverables**:
- [ ] Documentation covers setup, pinning, the check/learn flow, rotation, and troubleshooting
- [ ] Docs build passes; all verification passing

**Verify**: `bash test/verify.sh && npm ci && npm run docs:build`

---

## Dependencies

```
Phase 1 (config + mount)
    ↓
Phase 2 (staging consumes the mount contract)
    ↓
Phase 3 (check script verifies the staged configuration)
    ↓
Phase 4 (packaging and documentation)
```

---

## Success Criteria

**Feature is complete when:**

1. ✅ All phases completed
2. ✅ All verification passing (`bash test/verify.sh`; `npm ci && npm run docs:build`)
3. ✅ No warnings/errors; shellcheck clean
4. ✅ No dead code — no unused functions or variables
5. ✅ Security hardened — path validation, ownership/modes, never-weakened host-key verification
6. ✅ Documentation updated (guide, sidebar, reference, security, upgrades, troubleshooting)
7. ✅ Manual live-fleet check documented as the E2E step (AR #24)
8. ✅ Post-completion project re-analysis (handled by the exec-plan skill)
