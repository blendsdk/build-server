# Review Report: deploy-ssh-keygen (T-02)

> **Artifact**: Post-phase quality review for the deploy-ssh-keygen task mini-plan
> **Mode**: normal (strict quality profile: independent review on, stop on major findings; no 🔴/🟠 findings arose)
> **CodeOps Artifact Schema**: 1
> **Last Updated**: 2026-10-08 09:22

## Post-phase review — T-02 "Deploy SSH starter files and key generation"

- Baseline tree: `8d1fd6914e2fb74d4d010f9771360630ac1d715c` · phase diff: 808 lines (`fleet.sh`, `test/fleet.spec.test.sh`, `test/fleet.impl.test.sh`, `docs/guide/deploy-ssh.md`, `docs/guide/cli.md`, `docs/reference/files.md`, plan/roadmap bookkeeping)
- Reviewers: correctness-reviewer and security-auditor packets, each in an independent context. **Fallback reported:** the project's generated agents cannot run as subagents in this harness, so complete dynamic packets were dispatched as generic subagents (per the quality profile; independence preserved).
- Verify at review time: `bash test/verify.sh` → PASS (2026-10-08 09:14); `npm run docs:build` → PASS; spec suite 42 sections, impl suite 21 sections.

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| RV-001 | 🟡 | `seed_deploy_folder` is called in an `\|\|` list, which disables `set -e` inside it; creation failures (blocked `keys/`, unwritable starter files) were swallowed and the command still exited 0 — a fail-fast regression from the pre-phase loop (reproduced with `keys` as a regular file) | Fixed: every creation and write step is fatal (`die "could not create/write …"`); ST-59 pins the failure and that the fleet does not start |
| RV-002 | 🟡 | The pinned creation-notice wording was only asserted by prefix; a mutation of the parenthetical survived both suites | Fixed: the full notice line is asserted (ST-48, ST-56, and the impl notice case) |
| RV-003 | 🟡 | `chmod 600` for the generated private key had no independent assertion (real `ssh-keygen` already writes 0600), so deleting the chmod survived | Fixed: ST-51 asserts the private-key mode through the recording stub, which writes with the test umask — the `chmod` is now exercised |
| SA-001 | 🟡 | A dangling `config`/`known_hosts` symlink passed the `[ ! -f ]` test, and the `>` redirect created the file at the symlink target outside the deploy folder (verified) | Fixed: seeding writes only completely absent paths (`[ ! -e ] && [ ! -L ]`); ST-57 pins that dangling symlinks and their targets stay untouched |
| SA-002 | 🟡 | A `keys/` symlink to a directory outside `deploy-ssh/` let `keygen` write the private key outside the gitignored tree (verified) | Fixed: `keygen` refuses a symlinked `keys/` directory; ST-58 pins the refusal and that nothing is written through the link |

No 🔴/🟠 findings; no reserved decisions arose. All five fixes were implemented, verified with the full suite (`bash test/verify.sh` → PASS, 2026-10-08 09:22; spec suite 45 sections, impl suite 21), and committed as a follow-up. No re-review is required — re-review is reserved for 🔴/🟠 fixes.
