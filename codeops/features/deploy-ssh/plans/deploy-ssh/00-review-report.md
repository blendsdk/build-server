# Review Report: deploy-ssh

> **Artifact**: Phase reviews for the deploy-ssh execution plan
> **Mode**: auto-design (eligible technical fixes selected and recorded; no reserved decisions arose)
> **CodeOps Artifact Schema**: 1
> **Last Updated**: 2026-10-07 15:43

## Phase 1 — Fleet configuration and mounting

- Baseline tree: `2abaea015d0e0e1a8c63c63e2274273a7eb40f9f` · phase diff: 792 lines (`fleet.sh`, four test suites, `.gitignore`, `.dockerignore`, plan docs)
- Reviewers (independent contexts): correctness-reviewer, security-auditor
- Verify at review time: `bash test/verify.sh` → PASS (2026-10-07 15:38)

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| RV-001 | 🟡 | `umask 077` in `ensure_deploy_dirs` leaked into later commands (the generated Compose file became `0600` after an `up` that created a folder) | Fixed: the `umask` is scoped to a subshell around `mkdir` |
| RV-002 | 🟡 | Auto-create ran before some commands' own failure points (`update` without arguments; `up`/`restart` before `require_images`), creating folders on aborted commands | Fixed: each call site moved after its command's failure points and immediately before the first `compose up`; `update-runners` provisions inside `update_runners()` after the fetch and rebuilds |
| RV-003 | 🟡 | Plan bookkeeping: the Phase 1 expected-changes list omitted the AR-28-touched plan documents; the register `Last Updated` was stale | Fixed: list and timestamp updated |
| RV-004 | 🟡 | Test gap: the notice-suppression branch (folder already present, or only `keys/` missing) was unasserted; ST-12 never checked `generate`/`status` exit status | Fixed: a new impl case asserts a silent repeat run; ST-12 asserts both commands exit 0 |
| SA-001 | 🟡 | Validation/use divergence: character checks ran on the raw value but rendering used the `realpath`-resolved path; a symlink inside `deploy-ssh/` whose target name contains `:`, `$`, or a control character bypassed the checks and could inject lines into the generated privileged-service Compose YAML (confirmed empirically) | Fixed: the resolved path is re-validated (same metacharacters plus control characters), the spec gains validation step 9 and ST-42, and tests cover it. Severity stays 🟡 because the precondition is write access to the operator-owned `deploy-ssh/` folder |
| SA-002 | 🟡 | ST-41 exercised only `:` and `*`; `?`, `[`, `$` could regress unnoticed | Fixed: one rejection case per metacharacter, plus the resolved-path case (ST-42) |
| SA-003 | 🟡 | TOCTOU between parse-time validation and `ensure_deploy_dirs`: `mkdir -p` (and Compose at start) follow symlinks swapped in afterwards | Fixed (defense-in-depth): `ensure_deploy_dirs` re-canonicalizes each path before creation and skips it with a warning when it changed since validation |

No 🔴/🟠 findings; no reserved decisions arose; nothing deferred. The accepted fixes were implemented, verified with the full suite, and committed as a follow-up.
