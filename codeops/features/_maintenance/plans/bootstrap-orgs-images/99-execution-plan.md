# Task T-02: Bootstrap organizations and image handling

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 6/6 tasks (100%)

## Objective

Fix three bootstrap defects reported from a fresh-machine run:

1. The installer started the **example** organizations instead of asking for real ones.
2. It never built custom-context images, so Compose tried to **pull** `runner-image-<slug>` and
   failed with "pull access denied"; the log then blamed Docker group membership.
3. `fleet.sh up` can start with missing local images and produce the same misleading pull error.

**Smallest viable design:** ask for organization names and validate each by minting a registration
token (the exact permission the fleet needs); build the default image and each `context=` image
before starting; add `pull_policy: never` to generated services and a local-image pre-check in
`fleet.sh up`/`restart`; separate docker-access detection from command failure in the installer.
`--orgs "A B"` supports unattended runs and `--keep-orgs` preserves an existing file.

## Tasks

- [x] T-02.1 Spec tests: bootstrap org prompt/validation/unattended/keep-orgs, custom-image build, failure message ✅ (completed: 2026-10-03 14:36)
- [x] T-02.2 Spec tests: generated services use `pull_policy: never`; `up` rejects missing images with guidance ✅ (completed: 2026-10-03 14:36)
- [x] T-02.3 Red phase for both suites ✅ (completed: 2026-10-03 14:38)
- [x] T-02.4 Implement `fleet.sh` (pull policy + image pre-check) and `bootstrap.sh` (orgs, builds, error reporting) ✅ (completed: 2026-10-03 14:42)
- [x] T-02.5 Green phase plus docs updates (getting started, CLI, troubleshooting, reference, README) ✅ (completed: 2026-10-03 14:44)
- [x] T-02.6 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 14:45)

**Verify**: `shellcheck -S style bootstrap.sh fleet.sh test/*.sh && bash test/verify.sh && npm run docs:build`
