# Review Report: exchange-folder (T-15)

> **Artifact**: Post-phase quality review for the exchange-folder task mini-plan
> **Mode**: normal (strict quality profile: independent review on, stop on major findings)
> **CodeOps Artifact Schema**: 1
> **Last Updated**: 2026-10-08 16:32

## Post-phase review — T-15 "Shared artifact exchange folder"

- Baseline tree: `da6599d21f969b1cd754a1e6a24fe883e4215730` · phase diff: 488 lines (`fleet.sh`, `.gitignore`, `test/fleet.spec.test.sh`, `test/orgs.spec.test.sh`, three docs files, plan/roadmap bookkeeping)
- Reviewers: correctness-reviewer and security-auditor packets in independent contexts. **Fallback reported:** the project's generated agents cannot run as subagents in this harness, so the complete dynamic packets were dispatched as generic subagents (per the quality profile; independence preserved).
- Lenses: correctness + security (a world-writable host folder is mounted read-write into privileged containers).
- Verify at review time: `bash test/verify.sh` → PASS (2026-10-08 16:20); `npm run docs:build` → PASS.

### Findings and resolutions

The user ruled **"fix now + re-review"** for the major finding; all minor findings were fixed in the same pass.

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| RV-001 | 🟠 | `restart` and `upgrade-all` validated the exchange folders only after a compose teardown (`compose down`, or teardown + purge + rebuild for upgrade-all), so a non-directory entry took the fleet down (or tore it down and rebuilt it) before failing — a deviation from the pinned "fail before any compose call" behavior | Fixed: `restart` validates before `compose down`; `upgrade-all` validates right after the destructive confirmation, before the release fetch. ST-67 pins both with red→green regression cases (reverting either order fails the suite) |
| RV-002 | 🟡 | Only `up`/`start` creation was tested (4 of 6 call sites uncovered; mutations stayed green) | Fixed: ST-68 covers `update`, `update-runners`, `upgrade-all`, and `restart` (folder created, mode 0777, notice) |
| RV-003 | 🟡 | Symlink acceptance, dangling symlinks, and the parent mode were untested | Fixed: ST-69 pins a symlink-to-directory as accepted and untouched, a dangling symlink as fatal before start, and the parent mode as 0755 (mutation-verified) |
| SA-001 | 🟡 | `exchange/` was in `.gitignore` but not `.dockerignore`, so job artifacts rode in every build context | Fixed: `.dockerignore` excludes `exchange`; the Dockerfile spec asserts both ignore entries like the deploy-ssh rule |
| SA-002 | 🟡 | The parent `exchange/` mode depended on leaked umasks (`stage_ssh`/`build_org` set 077 without restoring), giving 0700 after `update-runners`/`upgrade-all` and 0755 elsewhere | Fixed: the parent is created in a `umask 022` subshell (deterministic 0755, never world-writable) |
| SA-003 | 🟡 | The docs' trust model was narrower than reality (mode 0777 exposes the folder to every local host account, and nested containers may write as root or arbitrary UIDs) | Fixed: the organizations guide now states the full trust model and keeps the "no secrets" warning |

Accepted residual observations (no defect): the privileged-runner trust model makes the folder not a
security boundary; a symlink relocation of the folder is an operator action; there is no root-side
write-through-symlink vector (`fleet.sh` only creates the folder and never writes inside it); path
construction is slug-restricted and injection-free. Pre-existing and out of scope: build commands
leak `umask 077` (the parent-mode fix makes the exchange path deterministic regardless), and
`restart`/`up` run `remove_legacy_containers` before the exchange check — unchanged ordering, and it
is not a compose call.

## Re-review — fix diff (`0ea6661` → `d9700d4`)

- Reviewer: correctness re-review packet in an independent context (same fallback note).
- Result: **no findings** (`RR` clean). All six resolutions verified by inspection and repro:
  - `restart`/`upgrade-all` fail before any compose call, fetch, or teardown (reverting either order
    fails ST-67).
  - ST-68 covers all six call sites; ST-69's symlink/parent cases are meaningful (removing the `-L`
    guard or the fixed umask fails them).
  - `.dockerignore`/`.gitignore` entries asserted; the parent mode is deterministic 0755.
- Regression sweep: no compose call precedes exchange validation in any of the six runner-starting
  commands; no teardown path touches `exchange/`.
- Verify after the fixes: `bash test/verify.sh` → PASS; `npm run docs:build` → PASS.

No reserved decisions remain open; the phase is accepted.
