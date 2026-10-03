# Task T-08: Minimal production install

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 6/8 tasks (75%)

## Objective

An install currently clones the entire repository — `.git`, `test/`, `docs/`, `codeops/`, dev
manifests — onto a production host. Only a handful of files are needed at runtime. Move the fetch
step to a temporary shallow clone and copy a fixed allowlist into the install directory, keep a
manifest so upstream renames are cleaned safely, record the installed revision, and offer an
explicit `--slim` migration for existing full clones.

## Authorized design (user-approved)

- Fetch each run with a shallow clone into `mktemp -d`, reusing the existing token/SSH auth paths.
- Copy allowlist: `.dockerignore`, `bootstrap.sh`, `fleet.sh`, `docker-compose.yml`, `Dockerfile`,
  `start.sh`, `entrypoint.sh` — atomically per file (`.tmp` + `mv`).
- Write `.build-server-manifest` (copied paths) and `.build-server-version` (`REVISION`, `DATE`).
- On update, delete old-manifest paths that no longer exist upstream; never touch generated state
  (`.env`, `orgs.conf`, `ssh/`, `registry/`, credentials, `.runner-version`, context dirs).
- `--slim` prunes the fixed dev list (`.git`, `test/`, `docs/`, `codeops/`, `.opencode/`,
  `.github/`, `node_modules/`, `package*.json`, dev-only `examples/` files) with realpath guards;
  without the flag, refresh and print a hint. `README.md`, `LICENSE`, and `.env.example` stay as
  operator references.
- Drop `shellcheck` from prerequisites; keep `git`.
- `fleet.sh status` prints `Host version: <sha> (<date>)`.

## Tasks

- [x] T-08.1 Spec tests: fresh slim install, update refresh/preserve/delete-on-rename, manifest + version, `--slim` prune, SSH clone to tmp, clone failure + cleanup
- [x] T-08.2 Red phase
- [x] T-08.3 Implement bootstrap: tmp clone, allowlist copy, manifest/version, `--slim`, drop shellcheck, usage text
- [x] T-08.4 `fleet.sh status` host version
- [x] T-08.5 Docs: `getting-started`, `upgrades`, `files.md`, `testing.md`, `README.md`
- [x] T-08.6 Verify: `shellcheck -S style … && bash test/verify.sh && npm run docs:build`
- [ ] T-08.7 Fleet E2E: `bash bootstrap.sh --keep-orgs --slim` on the remote host, then smoke workflow
- [ ] T-08.8 Roadmap bookkeeping and commit

**Verify**: `shellcheck -S style bootstrap.sh fleet.sh entrypoint.sh start.sh test/*.sh examples/playground.sh && bash test/verify.sh && npm run docs:build`
