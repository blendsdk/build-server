# Ambiguity Register: deploy-ssh material for runner containers

> **Status**: ✅ GATE PASSED — all 27 items resolved
> **Last Updated**: 2026-10-07 14:07

| # | Category | Ambiguity / Gap | Options Presented | User Decision | Status |
|---|----------|-----------------|-------------------|---------------|--------|
| 1 | Scope | How deploy SSH material reaches jobs: host-managed folder vs per-job CI setup | A: host-mounted per-org folder (user proposal) · B: per-job `ssh-setup` from GitHub secrets | User: host-mounted folder, setup stays out of CI/CD | ✅ Resolved |
| 2 | Scope | Whether a CI-side setup script ships in this plan | A: host folder only; CI-side stays a future option · B: ship both | User: host folder only for this plan | ✅ Resolved |
| 3 | Scope | How a runner enables the deploy folder | A: opt-in per org via `deploy_ssh=<path>` in `orgs.conf`; folder auto-created · B: auto-create and mount for every org | User accepted recommendation: opt-in per org, auto-created when declared | ✅ Resolved |
| 4 | Naming | Folder contract names and container paths | A (rec.): `config` + `known_hosts` + `keys/`; staging `/run/deploy-ssh` (ro) → `~/.ssh/deploy.d/` · B: `ssh_config` filename · C: `*.conf` drop-in layout | User accepted recommendation: `config` + `known_hosts` + `keys/`; `/run/deploy-ssh` → `~/.ssh/deploy.d/` | ✅ Resolved |
| 5 | Technical, Security | Mount is read-only and the entrypoint copies for the docker user (uid is not guaranteed to match the host) | A (rec.): `:ro` mount + root copy + `chown docker` + 700/600 · B: direct writable mount, host-managed uid | User accepted recommendation: read-only mount + root staging copy | ✅ Resolved |
| 6 | Security | Host-key verification policy for deploy targets | A (rec.): pin keys once (operator keyscan, via bastion for private targets) · B: `accept-new` documented fallback · C: disable checking | User accepted recommendation: pin; `accept-new` documented; never disable | ✅ Resolved |
| 7 | Feature | Connectivity check script scope | A (rec.): `deploy-ssh-check` test + `--learn`, run on demand, no automatic boot run · B: add boot-time run | User accepted recommendation: on-demand check with `--learn` | ✅ Resolved |
| 8 | Security | `--learn` behavior when the bastion key is not yet pinned | A (rec.): never weaken verification; print bastion `ssh-keyscan` line first, re-run after pinning · B: `accept-new` for the learn hop | User accepted recommendation: strict, print bastion keyscan first | ✅ Resolved |
| 9 | Behavioral | Entrypoint behavior when staging the resolved mount fails | A (rec.): warn and continue; runner stays available · B: fail container start | User accepted recommendation: warn and continue | ✅ Resolved |
| 10 | Technical | How the deploy config is wired into the SSH client | A (rec.): prepend `Include ~/.ssh/deploy.d/config` to `~/.ssh/config` (idempotent) · B: `/etc/ssh/ssh_config.d/` drop-in | User accepted recommendation: user `~/.ssh/config` include | ✅ Resolved |
| 11 | Scope | Operator convenience for running the check | A: also add `fleet.sh check-ssh <org>` · B: script only, raw `docker compose exec` in docs | User accepted recommendation: add `fleet.sh check-ssh` | ✅ Resolved |
| 12 | Security, Behavioral | `deploy_ssh` path validation rules | A (rec.): `context=`-style — relative, resolved inside the repo, reject traversal/symlink escape/absolute/empty · B: allow any host path | User accepted recommendation: `context=`-style validation | ✅ Resolved |
| 13 | Scope, Data | May two or more orgs declare the same deploy folder path? | A (rec.): allow sharing; each declaring runner mounts it read-only · B: enforce uniqueness, one folder per org | User accepted recommendation: allow sharing | ✅ Resolved |
| 14 | Behavioral | Entrypoint re-copy semantics across container boots | A (rec.): when the mount is present, remove `~/.ssh/deploy.d` then copy fresh; when absent, do nothing · B: copy over without removing | User accepted recommendation: remove then copy when present; no-op when absent | ✅ Resolved |
| 15 | Behavioral | When and where `fleet.sh` auto-creates a missing folder | A (rec.): on `up`/`restart`/`update`/`update-runners`/`upgrade-all`; create folder + `keys/` with `0700` + notice · B: only `up` · C: also `generate`/`status` | User accepted recommendation: create on container-starting commands; folder + `keys/` 0700 with notice | ✅ Resolved |
| 16 | Edge case, Security | A `deploy_ssh` path resolving to the repository root itself | A (rec.): reject; require a subdirectory · B: allow (would copy the whole repo into the container home) | User accepted recommendation: reject the repository root | ✅ Resolved |
| 17 | Data, Safety | What happens to host folders when the option is removed or an org is deleted | A (rec.): never delete host files; the folder simply stops being mounted · B: `fleet.sh clean` prunes unused folders | User accepted recommendation: never delete host files | ✅ Resolved |
| 18 | Behavioral, UX | `fleet.sh check-ssh` argument handling | A (rec.): exactly one org argument; unknown org and non-running container produce the standard errors · B: no argument checks every org sequentially | User accepted recommendation: exactly one org argument | ✅ Resolved |
| 19 | Behavioral | Which hosts `deploy-ssh-check` tests without arguments, and `--learn` inputs | A (rec.): literal hostnames from deploy `Host` lines; patterns (`*`, `?`, `!`) listed as skipped; explicit args override; `--learn` requires ≥1 host · B: always require explicit hosts in both modes | User accepted recommendation: literal hosts by default; patterns listed; `--learn` requires explicit hosts | ✅ Resolved |
| 20 | Behavioral, UX | Exit codes of `deploy-ssh-check` | A (rec.): `0` all tested hosts OK · `1` at least one FAIL · `2` usage/config error · B: `0` unless internal error; failures only printed | User accepted recommendation: 0 / 1 / 2 | ✅ Resolved |
| 21 | Scope, UX | Whether `fleet.sh status` displays the deploy-ssh configuration | A (rec.): output unchanged; inspect mounts via Docker when needed · B: add a `DEPLOY SSH` column | User accepted recommendation: status output unchanged | ✅ Resolved |
| 22 | Behavioral, Operations | Updating keys/config after first install | A (rec.): restart the runner (`stop`+`start` or `restart`); docs warn that running jobs are interrupted · B: live re-sync inside the container | User accepted recommendation: restart required; interruption documented | ✅ Resolved |
| 23 | Data & migration | Mixed-version window: new `fleet.sh` with an image built before the entrypoint staging exists | A (rec.): document that the feature activates after an image rebuild; no version gate · B: add a compatibility marker check in `fleet.sh` | User accepted recommendation: document rebuild requirement; no version gate | ✅ Resolved |
| 24 | Technical, Testing | How SSH behavior is tested given no real targets in CI | A (rec.): stub `ssh`/`ssh-keyscan`/`docker`/`dockerd`/`chown` shims + static Dockerfile/compose assertions; smoke workflow unchanged · B: add a loopback sshd fixture | User accepted recommendation: stub-based tests; no sshd fixture; smoke unchanged | ✅ Resolved |
| 25 | Naming | Repository location and install wiring of the check script | A (rec.): `deploy-ssh-check.sh` at the repo root, installed as `/usr/local/bin/deploy-ssh-check`; added to `INSTALL_FILES`, shellcheck list, `verify.sh` · B: new `scripts/` directory | User accepted recommendation: root script wired into install, shellcheck, and verify | ✅ Resolved |
| 26 | Scope, UX | Documentation deliverables | A (rec.): new `docs/guide/deploy-ssh.md` + sidebar; update `files.md`, `security.md`, `upgrades.md`, `troubleshooting.md`, `cli.md` · B: guide page + sidebar only | User accepted recommendation: new guide page plus the listed updates | ✅ Resolved |
| 27 | Scope | Explicit exclusions for this plan | A (rec.): no CI-side setup, no per-repo secrets, no agent forwarding, no SSH certificates, no boot-time check, no `accept-new` default, no live folder sync · B: include some of these | User accepted recommendation: exclusions as listed | ✅ Resolved |

### Resolution Notes

**AR-1:** The user proposed moving the setup out of CI/CD entirely because deployment targets change rarely; a per-org folder on the host, mounted into the runner, matches the fleet's persistent-container model and its documented credentials model (`docs/architecture/security.md:21-27`).

**AR-3:** The option value is a relative path; the documented convention is `deploy-ssh/<slug>` so per-org folders are predictable. **Preflight amendment (PF-003, accepted):** the path must be a strict subdirectory of `deploy-ssh/` (bare `deploy-ssh` is rejected — it would expose every organization's keys), which makes the gitignore/build-context exclusion guarantee unconditional. The `deploy-ssh/` directory is gitignored and excluded from Docker build contexts (necessary hygiene for the keys it holds).

**AR-5:** The image creates the `docker` user at build time (`Dockerfile:9`); a bind mount would otherwise keep the host operator's uid and make `0600` keys unreadable, and a read-only mount cannot be `chown`ed in place.

**AR-7:** `--learn` prints ready-to-paste `known_hosts` lines; it never writes files. Installing keys is an operator action on the host folder followed by a runner restart (AR-22).

**AR-12:** Validation mirrors the `context=` realpath containment rule in `fleet.sh:122-131`, extended with auto-creation (AR-15) and an explicit rejection of glob and mount metacharacters (`*`, `?`, `[`, `:`, `$`). Unlike `context=`, a missing path is valid, so the metacharacter rejection is a first-class rule rather than an existence side effect (PF-003, PF-006).

**AR-14, AR-15, AR-16, AR-17:** Confirmed by bulk acceptance on 2026-10-07; recommendations are reproduced verbatim in the User Decision column.

**AR-19:** Pattern entries cannot be tested or learned directly; the script lists them as skipped and points at explicit hostnames. This keeps the check deterministic instead of guessing pattern expansions.

**AR-22:** Because staging happens at container boot, file changes on the host require a runner restart; the plan documents the interruption of running jobs rather than adding a live-sync mechanism.

**AR-23:** Compatibility is one-directional: an older image ignores the deployment mount and the new option has no effect until `fleet.sh build`/`upgrade-all` rebuilds the image; existing configurations that do not use `deploy_ssh` are unaffected either way.
