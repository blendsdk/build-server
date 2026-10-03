# Task T-06: Bootstrap always completes the registry credentials

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 5/5 tasks (100%)

## Objective

An install created before the registry-credential feature ends up with `REGISTRY_USER`/`REGISTRY_PASS`
missing from `.env`, so jobs cannot push (the E2E registry step failed on exactly this). Re-running
the current bootstrap does not repair it because the generated password no longer matches the
existing htpasswd.

**Smallest viable design:** make the installer idempotent and self-healing:

1. Load existing `.env` values (explicit environment wins) for `ACCESS_TOKEN`, `REGISTRY_USER`,
   `REGISTRY_PASS`, `REGISTRY_HTTP_SECRET`, and `REGISTRY_PORT` before prompting or generating.
2. Keep the htpasswd in sync with the resolved credentials using `htpasswd -vb` — regenerate only
   when the file is missing or the password does not match.
3. Always ensure `.env` contains every required key, appending any that are missing.

## Tasks

- [x] T-06.1 Spec tests: upgrade without creds is repaired; matching install is untouched; mismatch regenerates htpasswd ✅ (completed: 2026-10-03 17:24)
- [x] T-06.2 Red phase ✅ (completed: 2026-10-03 17:24)
- [x] T-06.3 Implement `load_env_var`, verify-first htpasswd, and complete `.env` appends in `bootstrap.sh` ✅ (completed: 2026-10-03 17:26)
- [x] T-06.4 Green phase plus docs (getting started installer note) ✅ (completed: 2026-10-03 17:28)
- [x] T-06.5 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 17:28)

**Verify**: `shellcheck -S style bootstrap.sh test/bootstrap.spec.test.sh && bash test/bootstrap.spec.test.sh && bash test/verify.sh`
