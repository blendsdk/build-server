# Task T-09: Project-named containers for multi-install hosts

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 6/6 tasks (100%)

## Objective

Runner containers pin global names (`<slug>_runner_1`) and the registry uses the install directory
as its implicit Compose project, so two installations on one Docker host collide. Prefix every
container with a Compose project named after the install user, drop the `_1` service postfix, and
remove legacy-named containers on upgrade.

## Authorized design

- `.env` gains `COMPOSE_PROJECT_NAME` (default: sanitized login name of the installer; explicit
  value wins). Raw `docker compose` picks it up from `.env` automatically.
- Generated services are `<slug>`, no `container_name`, and the hostname stays `<slug>_runner_1`
  so GitHub runner names do not change.
- `fleet.sh` passes `--project-name`; fallback is the sanitized login name when `.env` is absent.
- `up`, `down`, `restart`, and `update` remove legacy containers (`<slug>_runner_1`,
  `<dir>-registry-1`, `<dir>_registry_1`) only when their `com.docker.compose.project` label
  matches the former install-directory project.

## Tasks

- [x] T-09.1 Spec tests: service naming, no `container_name`, project from `.env`/login fallback, legacy cleanup and guard
- [x] T-09.2 Red phase
- [x] T-09.3 Implement `fleet.sh` and `bootstrap.sh`
- [x] T-09.4 Docs: organizations, architecture overview, upgrades, examples, files
- [x] T-09.5 Verify plus a real Compose naming check
- [x] T-09.6 Commit, push, watch CI

**Verify**: `shellcheck -S style bootstrap.sh fleet.sh entrypoint.sh start.sh work_queue test/*.sh examples/playground.sh && bash test/verify.sh && npm run docs:build`
