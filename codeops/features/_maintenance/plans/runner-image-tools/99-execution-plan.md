# Task T-11: Runner image tooling: git, openssh-client, pnpm

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 4/4 tasks (100%)

## Objective

A fresh image built from `Dockerfile` does not contain `git` or `ssh`, although both are required:
`start.sh` runs `git config` under `set -euo pipefail` (the container would exit before the runner
registers), `actions/checkout` runs `/usr/bin/git`, and the fleet stages SSH keys for private
repository clones. Replace the retired `lerna` global install with `pnpm`.

## Authorized design

- Add `git` and `openssh-client` to the base apt package list; no other package changes.
- Install `pnpm` globally via npm and drop `lerna`.
- Extend the static Dockerfile spec test: `git` and `openssh-client` present, `pnpm` present,
  `lerna` absent.
- Image hygiene findings (apt lists cleanup, unpinned Docker/Node versions, legacy docker-compose)
  are reported to the user, not changed in this task.

## Tasks

- [x] T-11.1 Spec tests: git, openssh-client, pnpm present; lerna absent
- [x] T-11.2 Red phase
- [x] T-11.3 Dockerfile: add git/openssh-client, swap lerna for pnpm
- [x] T-11.4 Verify, commit, push, watch CI

**Verify**: `shellcheck -S style test/*.sh && bash test/verify.sh && npm run docs:build`
