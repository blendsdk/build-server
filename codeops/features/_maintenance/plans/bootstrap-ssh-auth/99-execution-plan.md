# Task T-01: Bootstrap SSH clone support

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 5/5 tasks (100%)

## Objective

Let `bootstrap.sh` clone the repository over SSH as an alternative to the token-based HTTPS clone:
reuse an existing SSH key, or generate a new one and install its public half on GitHub.

**Smallest viable design:** an auth-mode flag (`--token` default, `--ssh`, `--generate-ssh-key`)
plus a small URL conversion (`https://host/owner/repo.git` → `git@host:owner/repo.git`). Key
installation uses `POST /user/keys` with the already-required `ACCESS_TOKEN`; when the token lacks
`write:public_key`, the script prints the manual step. No new dependencies (`ssh-keygen`,
`ssh-keyscan`, `jq`, and `curl` are already prerequisites). `ACCESS_TOKEN` remains required for
runner registration in every mode.

## Tasks

- [x] T-01.1 Extend `test/bootstrap.spec.test.sh`: SSH with an existing key, `--generate-ssh-key` upload, and SSH without a key ✅ (completed: 2026-10-03 14:14)
- [x] T-01.2 Red phase: the new cases fail because the flags do not exist ✅ (completed: 2026-10-03 14:14)
- [x] T-01.3 Implement flags, SSH URL conversion, key ensure/generate/register, known_hosts, and SSH clone/update in `bootstrap.sh` ✅ (completed: 2026-10-03 14:17)
- [x] T-01.4 Green phase plus docs updates (`getting-started`, `github-token`, `files`, README, script usage) ✅ (completed: 2026-10-03 14:20)
- [x] T-01.5 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 14:20)

**Verify**: `shellcheck -S style bootstrap.sh test/bootstrap.spec.test.sh && bash test/bootstrap.spec.test.sh && bash test/verify.sh && npm run docs:build`
