# Preflight Report: deploy-ssh Implementation Plan

> **Status**: ✅ PREFLIGHT PASSED — all 19 findings resolved (fixes applied and verified)
> **Iteration**: 1 (first scan)
> **Artifact**: Implementation plan (10 documents) at `codeops/features/deploy-ssh/plans/deploy-ssh/`
> **Artifact hash (sha256 of the 10 docs, iteration 1)**: `a1776f0ad2d1d765a274b0e457fc6a1a89db7c39290d1e74156ae3b07dfd9fd8`
> **Fix-pass revision (all fixes applied + verified)**: `0e5f8e79a7aedd6609352d9d2ce72a9c19d5de000df7f13532f4c3e9d460db96`
> **Codebase Grounded**: 15 source/config/test/doc files examined; all plan `file:line` references verified
> **Last Updated**: 2026-10-07 15:19

```
SAME-SESSION REVIEW: This artifact was created in the current session.
Same-agent bias risk is elevated. Consider running preflight in a new session
for maximum review independence.
```

**Bias mitigation applied:** the 13-dimension scan ran as five independent auditor subagent
contexts (soundness · grounding · delivery · risk · fit), and the MAJOR finding batch was reviewed
by a separate independent challenger before any recommendation was recorded. All findings were
re-verified against the repository by the lead before inclusion.

**Fix pass:** all 19 accepted resolutions were applied on 2026-10-07, and a bounded iteration-2
verification in an independent fresh context confirmed every fix; the four residual bookkeeping
gaps it found (AR-12 wording, PF-012 decision cell, Phase 2 red-phase exceptions, the spec-file
mapping table) were corrected the same day.

### Codebase Context Summary

**Tech Stack:** Bash 5, Docker/Compose, OpenSSH client (Ubuntu 24.04 image), stub-based shell test suites, VitePress docs.
**Architecture:** one persistent privileged runner container per organization (own inner Docker daemon); `fleet.sh` renders Compose from `orgs.conf`; `entrypoint.sh` runs as root, starts `dockerd`, then drops to the `docker` user via `setpriv`; credentials are baked into the image at build time.
**Key Files Examined:** `fleet.sh`, `entrypoint.sh`, `Dockerfile`, `bootstrap.sh`, `start.sh`, `orgs.conf`, `.gitignore`, `.dockerignore`, `test/verify.sh`, `test/orgs.spec.test.sh`, `test/fleet.spec.test.sh`, `test/fleet.impl.test.sh`, `test/entrypoint.spec.test.sh`, `test/entrypoint.impl.test.sh`, `test/dockerfile.spec.test.sh`, `test/bootstrap.spec.test.sh`, `test/compose.spec.test.sh`, `docs/reference/testing.md`, `docs/reference/faq.md`, `docs/guide/custom-images.md`, `docs/.vitepress/config.mts`.
**Key constraints found:** no `known_hosts` is baked into the image (`Dockerfile:52-59` copies only `id_rsa`, `id_rsa.pub`, `config`); entrypoint tests stub `chmod`/`chown` as no-ops without argument recording; `verify.sh` lists every test file explicitly; Compose bind mounts use short syntax from the repository root.

### Summary by Dimension

| # | Dimension | Findings | Highest Severity |
|---|-----------|----------|------------------|
| 1 | Ambiguities | 2 | 🟡 |
| 2 | Implicit Assumptions | 1 | 🟠 |
| 3 | Logical Contradictions | 0 | — |
| 4 | Completeness Gaps | 2 | 🟡 |
| 5 | Dependency Issues | 0 | — |
| 6 | Feasibility Concerns | 0 | — |
| 7 | Testability | 3 | 🟠 |
| 8 | Security Blind Spots | 2 | 🟠 |
| 9 | Edge Cases | 1 | 🟡 |
| 10 | Scope Creep Indicators | 1 | 🔵 |
| 11 | Ordering & Sequencing | 2 | 🟠 |
| 12 | Consistency | 3 | 🟡 |
| 13 | Codebase Alignment | 2 | 🟠 |

### Summary by Severity

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | — |
| MAJOR | 5 | all resolved |
| MINOR | 13 | all resolved |
| OBSERVATION | 1 | resolved |

---

### PF-001: Jump-host key is checked outside the deploy `known_hosts`; the pinning loop cannot converge 🟠 MAJOR

**Dimension:** Implicit Assumptions
**Location:** `03-03-connectivity-check.md` §Learn mode; `00-index.md` §Usage Examples (config template); `01-requirements.md` R6/R8
**Codebase Evidence:** ProxyJump expands to a separate `ssh -l <user> -p <port> -W '<host>:<port>' <jump>` process that reads its own matching `Host` block and does not inherit the target block's options; the image bakes no `known_hosts` (`Dockerfile:52-59`).

**The Problem:** The template scopes `UserKnownHostsFile ~/.ssh/deploy.d/known_hosts` to the *target* `Host` block. The bastion connection is a separate ssh session, so the bastion's key is verified against the default (absent) `~/.ssh/known_hosts`. Adding the bastion's key to the deploy `known_hosts` therefore never fixes the jump, and `--learn` keeps failing after the instructed restart. This breaks the headline jump-host use case, not just tooling.

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Docs template adds a `Host` block for each bastion inside the deploy fragment (`UserKnownHostsFile ~/.ssh/deploy.d/known_hosts`, `StrictHostKeyChecking yes`); the check script resolves the bastion via `ssh -G` and, on a host-key failure, prints an actionable diagnostic (keyscan line + the bastion-block requirement) | Makes the recommended setup actually converge and jobs work; diagnosis explains the two-layer trust model | Slightly longer template and script logic |
| B | Docs-only: add the bastion block to the template without a script diagnostic | Minimal change; setup works when followed | Operators hitting the failure get the raw `Host key verification failed` with no path forward |

**Recommendation:** Option A — the template half is mandatory for R6 to hold; the diagnostic prevents a confusing dead end. A blanket `Host *` block was considered and dropped (it would shadow the baked GitHub config for all hosts); document the per-bastion block instead.
Confidence: High — would change only if jump-host support is explicitly scoped out.
Hardening: Challenger: converged (refined) — template fix + script diagnostic; do not force `-o` options in `--learn`, since the script should mirror job behavior.

**User Decision:** Resolved — User accepted recommendation: Option A (bastion `Host` block in the template + actionable `--learn` diagnostic).

---

### PF-002: `--learn` keyscans raw `Host` tokens instead of resolved names 🟠 MAJOR

**Dimension:** Codebase Alignment (stale assumption)
**Location:** `03-03-connectivity-check.md` §Learn mode steps 1–3; `01-requirements.md` R8
**Codebase Evidence:** OpenSSH verifies host keys against the resolved `HostName` (or `HostKeyAlias`), while `ssh -G <alias>` leaves an inline-port `proxyjump` unresolved. Therefore `ssh-keyscan <token>` produces entries that never match the connection for `Host app-prod` + `HostName 10.20.1.5` configs, and the printed bastion instruction can target the wrong name/port.

**The Problem:** For aliased targets — a normal SSH pattern — `--learn` prints unusable `known_hosts` lines and jobs keep failing; an unresolvable alias yields a bare FAIL with no cause. Both the target keyscan and the bastion instruction are affected.

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Parse `[user@]host[:port]` first, then resolve effective `hostname` / `hostkeyalias` / `port` / `user` via `ssh -G`; use those for target scans and printed entries (rewriting the first field to `HostKeyAlias` when set); add ST cases for aliased targets, aliased bastions, and `HostKeyAlias` | Correct for all real configs; reuses the planned `ssh -G` plumbing; shares its helper with PF-001 | More script logic and test cases |
| B | Document that `--learn` supports only directly resolvable names | Simpler script | Contradicts R6/normal SSH usage; silently bad output for common configs |

**Recommendation:** Option A — aliasing is ubiquitous and printing unusable keys is the worst failure mode; the plan already pays for `ssh -G`.
Confidence: High — would change only if aliased configs were explicitly declared unsupported.
Hardening: Challenger: converged — implement one effective-config resolution helper covering target and bastion (also serves PF-001); note that inline jump ports must be parsed before calling `ssh -G`.

**User Decision:** Resolved — User accepted recommendation: Option A (resolve effective hostname/port/user through `ssh -G`; shared helper with PF-001).

---

### PF-003: Ignore-file hygiene covers `deploy-ssh/` only, while any in-repo path is allowed 🟠 MAJOR

**Dimension:** Security Blind Spots
**Location:** `03-04-packaging-and-docs.md` §Ignore files; `03-01-orgs-configuration.md` §orgs.conf grammar; `01-requirements.md` R3; AR #3 resolution note
**Codebase Evidence:** `.gitignore` / `.dockerignore` would carry the fixed entries `deploy-ssh/` / `deploy-ssh`; a declared path such as `ops/keys` passes all six validation rules, so its private keys can be committed and are sent to the Docker daemon with the build context (`fleet.sh:408-409`).

**The Problem:** R3 promises unconditionally that the folder is "gitignored and excluded from Docker build contexts", but the guarantee holds only for the conventional `deploy-ssh/` path, with no warning otherwise. For a key-bearing directory this is a silent security gap.

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Validation requires the resolved path to be a strict subdirectory of `deploy-ssh/` (also rejecting bare `deploy-ssh`, which would expose every org's keys at once). Sharing (`deploy-ssh/shared`) remains allowed | Makes R3's guarantee true; simpler mental model; no docs caveats | Narrows the AR #3 note ("any in-repo path is valid") — needs your explicit sign-off; alternative locations become unavailable |
| B | Keep arbitrary paths, but make `parse_config` **fail** (not warn) for paths outside `deploy-ssh/` unless the operator acknowledges via docs — or accept the responsibility explicitly documented | Keeps flexibility | Private-key safety becomes an operator obligation; the docs must state it loudly |

**Recommendation:** Option A — the docs already teach `deploy-ssh/<slug>` as the convention, sharing still works, and convenience does not outweigh committed private keys. This amends the AR #3 note, so it requires your ruling; if you value arbitrary paths, the fallback is a parse-time failure (warning is too weak).
Confidence: High on the security need; the chosen pick needs your acceptance.
Hardening: Challenger: converged (refined) — also reject bare `deploy-ssh`; fallback must be a hard failure, not a warning.

**User Decision:** Resolved — User accepted recommendation: Option A (restrict to strict `deploy-ssh/` subdirectories; reject bare `deploy-ssh`; the AR #3 note is amended when fixes are applied).

---

### PF-004: ST-14's mode and `chown` assertions are not verifiable with the current harness 🟠 MAJOR

**Dimension:** Testability
**Location:** `07-testing-strategy.md` ST-14 and §Mock Requirements; `03-02-container-staging.md` §Staging algorithm; `99-execution-plan.md` tasks 2.1.1/2.3.1
**Codebase Evidence:** `test/entrypoint.spec.test.sh:48-56` stubs `chmod` as a no-op and `chown` without argument recording, so staged modes are never applied and the `chown` call is invisible. Separately, `chmod -R go-rwx` does not normalize stricter source modes (0400 stays 0400), contradicting the exact `600`/`700` spec.

**The Problem:** As written, ST-14 fails against a correct implementation (permissive fixture) or is vacuous (pre-normalized fixture), and the expected input→output relation is unpinned. A failing immutable-oracle test invites the executor to weaken it.

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Normalize exactly in the implementation (`find <target> -type d -exec chmod 700 {} +` / `-type f -exec chmod 600 {} +`); spec the harness changes: permissive fixture (0644/0755), a `chmod` stub that records argv and delegates to the real binary **only under the test sandbox** (never for `/var/run/docker.sock`), a `chown` stub that records argv and never delegates | ST-14 becomes real; exact modes guaranteed for any source | Touches shared entrypoint stubs |
| B | Keep `go-rwx`; weaken ST-14 to "no group/other bits" + add chown recording | Fewer changes | Weakens a security-relevant requirement; vacuous with a no-op stub unless the fixture is permissive anyway |

**Recommendation:** Option A — exact normalization is one `find` pair and keeps R4's promise; the guard keeps the suite's "never touches the host Docker socket" property intact.
Confidence: High.
Hardening: Challenger: converged (refined) — `u+rwX` alone is insufficient (0755→700); use explicit per-type modes; `chown` must never delegate.

**User Decision:** Resolved — User accepted recommendation: Option A (exact per-type mode normalization + guarded harness changes).

---

### PF-005: ST-35's red phase cannot happen (authored in Phase 4 after its Phase 1 implementation) 🟠 MAJOR

**Dimension:** Ordering & Sequencing
**Location:** `99-execution-plan.md` task 1.3.2 vs 4.1.1/4.1.3; `07-testing-strategy.md` ST-35
**Codebase Evidence:** Plan-internal; the repository's non-negotiable rule requires spec tests before implementation (`test/verify.sh` conventions, `07-testing-strategy.md` checklist).

**The Problem:** The `.gitignore`/`.dockerignore` edits land in Phase 1, but their static assertion ST-35 is authored in Phase 4, where it can only pass on first run. This violates the plan's own spec-first ordering and risks the assertion being written to match the implementation.

**Options:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Add a `[spec-author]` task at the top of Step 1.3 that authors ST-35 and records red, then 1.3.2 implements the ignore entries; remove ST-35 from Phase 4 (4.1.1 covers ST-33 only) | Preserves red-first; hygiene lands early | `dockerfile.spec.test.sh` is touched in two phases |
| B | Move the ignore edits to Phase 4 before 4.1.1 | Single touch of the test file | Delays a cheap secret-hygiene change until after the feature is built |
| C | Record ST-35 as a green-on-authoring exception | No task changes | Contradicts the non-negotiable ordering rule |

**Recommendation:** Option A.
Confidence: High.
Hardening: Challenger: converged (refined) — Step 1.3 placement is better than Step 1.1 (Step 1.1's red-run scope is parser/CLI, not the dockerfile suite).

**User Decision:** Resolved — User accepted recommendation: Option A (ST-35 authored at the top of Step 1.3, before the ignore edits).

---

### PF-006: Validation misses mount-string metacharacters; the claimed glob rejection does not exist 🟡 MINOR

**Dimension:** Consistency
**Location:** `03-01-orgs-configuration.md` §Validation; `00-ambiguity-register.md` AR-12 note; `02-current-state.md`
**Codebase Evidence:** `fleet.sh:122-131` rejects a glob for `context=` only because the path must exist; `deploy_ssh` allows missing paths, and Compose short syntax treats `:` and `$` specially.

**The Problem:** `deploy_ssh=deploy-ssh/*` passes all six rules, is literally created as `*`, and mounted; `:` breaks the mount specification (`compose up` fails for the whole fleet) and `$` silently alters the source via Compose interpolation. Two documents claim a glob rejection parity that does not exist.

**Recommendation (single viable path):** Add one validation step rejecting `*`, `?`, `[`, `:`, and `$` in the value, with a line-numbered message and an ST case; correct the AR-12 note and `02-current-state.md` to describe the explicit rule. Rejected alternative: keeping the claim and accepting the inputs — the failure modes are silent or fleet-wide.
Confidence: High.

**User Decision:** Resolved — User accepted recommendation: reject `*`, `?`, `[`, `:`, `$`; correct the AR-12 note and `02-current-state.md`.

---

### PF-007: Auto-create call-site semantics are underspecified (`start`; `upgrade-all` timing) 🟡 MINOR

**Dimension:** Consistency
**Location:** `01-requirements.md` R2; `03-01-orgs-configuration.md` §Auto-creation; AR #15
**Codebase Evidence:** `fleet.sh:635-639` — `start` is a container-starting command but excluded from the five call sites; Docker recreates a missing bind source on start as root-owned 0755. `fleet.sh:601-613` — `upgrade-all` runs confirmation, fetch, teardown, and rebuild before `compose up`, so folders can be created for an aborted or failed operation.

**The Problem:** R2's definitional phrase conflicts with the operative list; a deleted folder + `start` silently violates the `0700` contract with no notice. `upgrade-all` can create never-deleted folders on an operation that never started anything.

**Recommendation (single viable path):** Add `start` to `ensure_deploy_dirs` call sites and reword R2/R12 to name the six commands explicitly; for `upgrade-all`, call `ensure_deploy_dirs` after confirmation and version fetch, immediately before `compose up`. **User Decision:** Resolved — User accepted recommendation: add `start` to the ensure call sites; move the `upgrade-all` call to immediately before `compose up`.

---

### PF-008: `check-ssh` for an org without `deploy_ssh` is undefined, and one 03-02 row promises a message that does not exist 🟡 MINOR

**Dimension:** Ambiguities
**Location:** `01-requirements.md` R9; `03-03-connectivity-check.md` §Configuration discovery; `03-02-container-staging.md` error table
**Codebase Evidence:** `fleet.sh:416,456` establish the `unknown organization '<slug>'` pattern; no path defines an undeclared-but-known org.

**The Problem:** For a known org without `deploy_ssh`, the script prints "mount the folder and restart the runner" — advice that cannot work — while 03-02 promises "reports no configured hosts", which no output spec defines.

**Recommendation (single viable path):** `fleet.sh check-ssh` fails fast for an org without `deploy_ssh` (`organization '<slug>' has no deploy_ssh configured`), checked before `compose exec`; align the 03-02 row; add an ST case. **User Decision:** Resolved — User accepted recommendation: fail fast for an undeclared org; align the 03-02 row; add an ST case.

---

### PF-009: `verify.sh` wiring is ordered before the impl test file exists 🟡 MINOR

**Dimension:** Ordering & Sequencing
**Location:** `99-execution-plan.md` tasks 3.2.3 and 3.3.1; `03-04-packaging-and-docs.md` §verify.sh
**Codebase Evidence:** `test/verify.sh:14-23` executes every test file explicitly under `set -euo pipefail`.

**The Problem:** Task 3.2.3 wires "the new test files" (plural) but `test/deploy-ssh-check.impl.test.sh` is created later at 3.3.1; either an intermediate `verify.sh` run fails or the impl suite is never wired.

**Recommendation (single viable path):** 3.2.3 wires the shellcheck entry plus the spec suite only; 3.3.1 explicitly adds the impl suite to `verify.sh`. **User Decision:** Resolved — User accepted recommendation: 3.2.3 wires shellcheck + spec suite; 3.3.1 adds the impl suite to `verify.sh`.

---

### PF-010: The Quick Reference template makes `check-ssh` exit 2 by its own rules 🟡 MINOR

**Dimension:** Consistency
**Location:** `00-index.md` §Usage Examples; `03-03-connectivity-check.md` §Host selection; ST-20
**Codebase Evidence:** Plan-internal; AR #19 defines "no literal hosts → exit 2".

**The Problem:** The flagship example uses only pattern tokens (`Host app-* 10.20.*`), so the first-use command in the plan fails by design.

**Recommendation (single viable path):** Include at least one literal hostname in the shipped template (`Host app-prod app-* 10.20.*`) and show explicit-host usage for pattern-only configs. **User Decision:** Resolved — User accepted recommendation: include a literal host in the shipped template and show explicit-host usage.

---

### PF-011: `orgs.conf` and bootstrap grammar headers go stale 🟡 MINOR

**Dimension:** Codebase Alignment (impact blindness)
**Location:** `03-04-packaging-and-docs.md` docs deliverables; `00-index.md` §Related Files
**Codebase Evidence:** `orgs.conf:3-8` and the header generated by `bootstrap.sh:287` both enumerate `url/context/build_temp` only.

**The Problem:** Operators read the config file, not the docs; after the feature, every fresh install still advertises an option set without `deploy_ssh`.

**Recommendation (single viable path):** Add `[deploy_ssh=<path>]` plus a one-line description to both headers as part of the docs tasks. **User Decision:** Resolved — User accepted recommendation: update both grammar headers (`orgs.conf` and the bootstrap-generated header).

---

### PF-012: `--learn` bastion-failure branch is under-specified 🟡 MINOR

**Dimension:** Ambiguities
**Location:** `03-03-connectivity-check.md` §Learn mode step 3 and exit codes; `01-requirements.md` R8
**Codebase Evidence:** `ssh` exits 255 for host-key, authentication, DNS, and network failures alike; ST-26 stubs only the host-key case.

**The Problem:** The detection matcher is unspecified (grep text vs any non-zero exit), other bastion failures have no defined output or exit path, and R8's "stops without collecting anything else" contradicts the per-host semantics. "Remote host identification has changed" needs different advice (replace the entry) than a missing key (append).

**Recommendation (single viable path):** Pin the matcher to OpenSSH's stable `Host key verification failed.`; define the other-failure branch (`FAIL <bastion> - <last stderr line>`, exit 1, continue with remaining hosts); handle the changed-key message separately; reword R8 to per-host semantics; add an impl test for an authentication failure. Rejected alternative: treating any failure as unpinned — misdirects operators to keyscan for auth problems.
Confidence: High.

**User Decision:** Resolved — User accepted recommendation: pin the matcher; other failures → `FAIL` + exit 1 and continue; changed-key handled separately; R8 reworded; impl test added.

---

### PF-013: The `accept-new` PASS claim is overstated 🟡 MINOR

**Dimension:** Security Blind Spots
**Location:** `03-03-connectivity-check.md` §Test mode; AR #6/#8
**Codebase Evidence:** The staged `known_hosts` is writable by the runner user; `accept-new` sessions append keys to it, and the entrypoint replaces the directory at every boot.

**The Problem:** On an `accept-new` org, a job can learn a key at runtime, after which `deploy-ssh-check` reports PASS although the host folder lacks it — and the next boot wipes it. The claim "unknowns are reported as failures until pinned" is not reliable.

**Recommendation (single viable path):** Correct the wording: PASS verifies the effective trust state, not pinning; the host folder is the source of truth; re-run the check right after a restart for a pinning verdict. **User Decision:** Resolved — User accepted recommendation: reword 03-03 (PASS verifies the effective trust state; host folder is the source of truth; re-run after restart for a pinning verdict).

---

### PF-014: The manual live-fleet E2E checklist is not a committed deliverable 🟡 MINOR

**Dimension:** Completeness Gaps
**Location:** `07-testing-strategy.md` §End-to-End; `03-04-packaging-and-docs.md` guide row; task 4.3.1; success criterion 7
**Codebase Evidence:** AC3/R6 have no automated test by design (AR #24); the guide is the only vehicle for the manual check.

**The Problem:** The guide's content table and task 4.3.1 omit the checklist, so the core acceptance criterion can ship unverified.

**Recommendation (single viable path):** Add the manual checklist (ssh/scp/rsync through ProxyJump, pinned known_hosts, exit codes) to the guide row and task 4.3.1. **User Decision:** Resolved — User accepted recommendation: add the manual checklist to the guide row and task 4.3.1.

---

### PF-015: Docs omissions — `testing.md`, `faq.md`, `custom-images.md` go stale 🟡 MINOR

**Dimension:** Completeness Gaps
**Location:** `03-04-packaging-and-docs.md` §Documentation deliverables
**Codebase Evidence:** `docs/reference/testing.md:22-31` enumerates every suite (the two new ones are missing); `docs/reference/faq.md:24-28` lists credential locations without `deploy-ssh/`; `docs/guide/custom-images.md:30-42` defines the base-image contract that new self-contained images must now also honor.

**The Problem:** These pages become factually incomplete after the feature.

**Recommendation (single viable path):** Extend the docs deliverables and tasks 4.3.2/4.3.3 to cover the three pages. **User Decision:** Resolved — User accepted recommendation: extend the docs deliverables to `testing.md`, `faq.md`, and `custom-images.md`.

---

### PF-016: Negative safety clauses are under-verified 🟡 MINOR

**Dimension:** Testability
**Location:** `07-testing-strategy.md` ST-12/ST-13; `99-execution-plan.md` task 1.3.1
**Codebase Evidence:** ST-12 pins only `generate` (R2 also names `status`); ST-13 pins only `down`; `clean`/`upgrade-all` are the commands that actually purge resources (`fleet.sh:326-337,596-600`).

**The Problem:** "Never create from read-only commands" and "never delete host folders" are the feature's safety guarantees, yet the strongest purge paths have no test.

**Recommendation (single viable path):** Extend ST-12 to `status`; extend impl tests so a sentinel file survives `clean --yes` and `upgrade-all --yes`. **User Decision:** Resolved — User accepted recommendation: extend ST-12 to `status`; add frozen-folder assertions for `clean --yes` and `upgrade-all --yes`.

---

### PF-017: Red-phase deliverables demand failures from cases that legitimately pass 🟡 MINOR

**Dimension:** Testability
**Location:** `99-execution-plan.md` tasks 1.1.3/2.1.2/3.1.3/4.1.3 and phase deliverables; `07-testing-strategy.md` checklist
**Codebase Evidence:** ST-2, ST-16, ST-17 and ST-30 assert absence or pre-existing behavior (e.g., unknown-command usage already exits non-zero, `fleet.sh:658-661`) and pass against the unimplemented tree.

**The Problem:** "New cases fail" is inaccurate for negative/regression cases, inviting false failure reports or artificially failing tests.

**Recommendation (single viable path):** Reword red-phase tasks and deliverables as "behavior-adding cases fail; negative/regression cases are expected to pass in red", enumerating the exceptions per phase. **User Decision:** Resolved — User accepted recommendation: reword the red-phase tasks and deliverables (behavior-adding cases fail; listed negative/regression cases pass in red).

---

### PF-018: Bracketed-IPv6 learn parsing exceeds the confirmed baseline 🔵 OBSERVATION

**Dimension:** Scope Creep Indicators
**Location:** `03-03-connectivity-check.md` §Learn mode; `07-testing-strategy.md` impl tests
**Codebase Evidence:** No requirement or AR entry mentions IPv6; the design already has a catch-all parse error (exit 2).

**The Problem:** Extra parser logic and a dedicated impl-test item trace to no requirement — mild strict-scope drift in an otherwise minimal design.

**Recommendation (single viable path):** Drop bracketed-IPv6 support; document the limitation and point at manual `ssh-keyscan`. **User Decision:** Resolved — User accepted recommendation: drop bracketed-IPv6 support and document the limitation.

---

### PF-019: `Host`-line trailing comments are not covered by the parse spec 🟡 MINOR

**Dimension:** Edge Cases
**Location:** `03-03-connectivity-check.md` §Test mode host selection; `07-testing-strategy.md` impl tests
**Codebase Evidence:** OpenSSH treats a token starting with `#` as a comment start (`Host foo # comment` matches only `foo`; `Host baz#qux` is one literal token). A parser that strips only full-line comments would test `#` and `comment` as hosts and emit spurious FAILs.

**The Problem:** The spec says "comments" only in passing; the exact rule is undefined.

**Recommendation (single viable path):** Specify: tokenize on whitespace, stop at the first token beginning with `#`, `#` inside a token is literal; add `Host foo # comment` and `Host baz#qux` cases. **User Decision:** Resolved — User accepted recommendation: specify the `#` comment rule (stop at first `#`-prefixed token) and add both cases.
