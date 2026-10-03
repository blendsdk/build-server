# Task T-10: Remove runner registrations on fleet down

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 4/5 tasks (80%)

## Objective

`./fleet.sh down` stops and removes the containers but leaves the GitHub runner registrations
behind (offline). The in-container deregistration is not reliable: it reuses the registration token
fetched at container start, and registration tokens expire after an hour. Make `down` remove the
registrations through the API so the organizations no longer list offline runners.

## Authorized design

- After `compose down --remove-orphans`, `fleet.sh down` lists each organization's runners through
  the API and deletes entries whose name matches `<org>_<slug>_runner_1`.
- Pagination via `per_page=100`; runners with other names are never touched.
- API errors and a missing `ACCESS_TOKEN` produce a warning; `down` still succeeds because the
  containers are already stopped.
- `up` after `down` re-registers everything (`start.sh` registers with `--replace`).

## Tasks

- [x] T-10.1 Spec tests: matching deletion, name guard, stop-before-delete order, warning paths
- [x] T-10.2 Red phase
- [x] T-10.3 Implement `unregister_runners` and wire it into `down`
- [x] T-10.4 Docs: admin CLI
- [ ] T-10.5 Verify, commit, push, watch CI

**Verify**: `shellcheck -S style fleet.sh test/*.sh && bash test/verify.sh && npm run docs:build`
