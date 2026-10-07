# Testing Strategy: deploy-ssh

> **Document**: 07-testing-strategy.md
> **Parent**: [Index](00-index.md)

## Testing Overview

### Coverage Goals

| Code type | Target |
| --------- | ------ |
| Shell scripts (`fleet.sh`, `entrypoint.sh`, `deploy-ssh-check.sh`) | Every specified behavior covered by an ST case; edges in impl tests |
| Packaging/static files (`Dockerfile`, `bootstrap.sh`, ignore files, docs) | Static assertions where behavior exists; docs build for docs |
| UI / glue / configuration | n/a — no UI |

- Test names state behavior: `should [expected behavior] when [condition]` in the style of the
  existing stub-based suites.
- Integration tests exercise the components through their real entry points with stubbed external
  commands, matching the repository's existing harnesses (`test/*.spec.test.sh`,
  `test/*.impl.test.sh`).
- End-to-end tests with a real SSH target are **N/A** for CI: no bastion or target is available, and
  the repository deliberately avoids a loopback `sshd` fixture (AR #24). The guide includes a
  short manual checklist for a live fleet instead.

## 🚨 Specification Test Cases (MANDATORY — NON-NEGOTIABLE)

> These test cases are derived EXCLUSIVELY from requirements (`01-requirements.md`), component
> specs (`03-01`..`03-04`), and the Ambiguity Register (`00-ambiguity-register.md`). They define
> expected behavior BEFORE any implementation exists.
>
> **IMMUTABLE ORACLE RULE:** Do NOT modify these expectations to match the implementation. If the
> implementation does not match a spec test case, the implementation is wrong — not the test.

### Fleet configuration (03-01) — `test/orgs.spec.test.sh`, `test/fleet.spec.test.sh`

| # | Input / Scenario | Expected Output / Behavior | Source |
| --- | ---------------- | -------------------------- | ------ |
| ST-1 | `AcmeTools deploy_ssh=deploy-ssh/acmetools`; run `generate`; normalize with `docker compose config --format json` | Service `acmetools` has exactly one bind volume with target `/run/deploy-ssh`, `read_only: true`, and a source path ending in `/deploy-ssh/acmetools` | Req R3 / 03-01 §Volume rendering |
| ST-2 | Org without `deploy_ssh`; render | Its service has no `/run/deploy-ssh` volume | Req R3 |
| ST-3 | `Globex build_temp=1 deploy_ssh=deploy-ssh/globex`; render | The service lists both `/build-temp` and `/run/deploy-ssh` volumes | Req R3 / 03-01 §Volume rendering |
| ST-4 | `One deploy_ssh=deploy-ssh/shared` and `Two deploy_ssh=deploy-ssh/shared`; render | Both services mount the same path at `/run/deploy-ssh` | AR #13 |
| ST-5 | `BadOrg deploy_ssh=`; run `generate` | Exit non-zero; message `deploy_ssh path must not be empty`; no generated file written | AR #12 |
| ST-6 | `deploy_ssh=/etc/deploy` | Message `deploy_ssh path must be relative` | AR #12 |
| ST-7 | `deploy_ssh=../escape` | Message `deploy_ssh path must not contain '..'` | AR #12 |
| ST-8 | Symlink `escape` in the repo pointing outside; `deploy_ssh=escape` | Message `deploy_ssh 'escape' resolves outside the repository` | AR #12 |
| ST-9 | `deploy_ssh=.` | Message `deploy_ssh path must not be the repository root` | AR #16 |
| ST-10 | A regular file exists at the declared path | Message `deploy_ssh 'x' is not a directory` | AR #12 |
| ST-11 | Sandbox with `Alpha deploy_ssh=deploy-ssh/alpha`, stubbed docker; run `up`, then delete the folder and run `start` | `deploy-ssh/alpha/` and `deploy-ssh/alpha/keys/` exist with mode `0700` after both commands; a creation notice is printed each time the folder is missing; the compose calls still happen | AR #15, PF-007 |
| ST-12 | Same sandbox; run `generate` and `status` | `deploy-ssh/alpha/` is NOT created by either command, and both commands exit 0 | AR #15, PF-016, RV-004 |
| ST-13 | Folder contains `keep.txt`; run `down` with stubbed docker/curl | The folder and `keep.txt` still exist afterwards | AR #17 |
| ST-38 | `deploy_ssh=ops/keys` and `deploy_ssh=deploy-ssh` (bare) | Message `deploy_ssh path must be inside 'deploy-ssh/'`; no generated file written | PF-003 |
| ST-41 | `deploy_ssh` values containing each of `*`, `?`, `[`, `:`, `$` | Message `deploy_ssh path must not contain '*', '?', '[', ':', or '$'` for every case | PF-006, SA-002 |
| ST-42 | A symlink inside `deploy-ssh/` whose target directory name contains `:` (and a newline variant); `deploy_ssh` points at the symlink | Message `deploy_ssh '<value>' resolves to a path with unsupported characters`; no generated file written | SA-001 |

### Container staging (03-02) — `test/entrypoint.spec.test.sh`

| # | Input / Scenario | Expected Output / Behavior | Source |
| --- | ---------------- | -------------------------- | ------ |
| ST-14 | Source fixture with `config`, `known_hosts`, `keys/prod` created with permissive modes (0644 files / 0755 dirs); run the entrypoint with `DEPLOY_SSH_SOURCE`/`RUNNER_USER_HOME` overrides and PATH stubs | `~/.ssh/deploy.d/` contains all files; files are exactly `600`, directories exactly `700`; the recording `chown` stub saw `-R docker:docker <target>`; the staging success line is printed | Req R4, PF-004 |
| ST-15 | Same as ST-14, with a pre-existing `~/.ssh/config` block (`Host github.com`); inspect after one and after two entrypoint runs | The first line is `Include ~/.ssh/deploy.d/config`, it appears exactly once, and the pre-existing block is preserved | Req R5 / AR #10, RV-101 |
| ST-16 | Source with keys but no `config`; run | No include line is added to `~/.ssh/config` | Req R5 |
| ST-17 | No source directory (`DEPLOY_SSH_SOURCE` missing); run | No `~/.ssh/deploy.d` is created; the runner starts normally | AR #14 |
| ST-18 | Making the target parent unwritable so staging fails; run | A warning is printed; the runner still starts (`setpriv` invoked); exit status unchanged | AR #9 |
| ST-19 | Target home pre-contains `deploy.d/stale` not present in the source; run | `stale` is gone after the run (fresh copy) | AR #14 |
| ST-43 | Source contains a symlink to a file outside the folder; run staging | The link is staged as a link (not dereferenced) and the pointed-at file is unchanged | SA-103 |
| ST-44 | `~/.ssh/config.new` is pre-planted as a symlink to a victim file; run staging with a config present | The victim is unchanged; the Include line is added and remains the first line | SA-101 |
| ST-45 | Fresh `RUNNER_USER_HOME` without `.ssh`; run staging | `.ssh` exists at `700` and a `chown docker:docker` for it was recorded; staging succeeds | SA-102 |

### Connectivity check (03-03) — `test/deploy-ssh-check.spec.test.sh`, `test/fleet.spec.test.sh`

| # | Input / Scenario | Expected Output / Behavior | Source |
| --- | ---------------- | -------------------------- | ------ |
| ST-20 | Config with `Host app-prod` and `Host app-*`; run with no arguments | Only `app-prod` is tested; a skipped-pattern note names `app-*` | AR #19 |
| ST-21 | Stub `ssh` exits 0 | Output contains `PASS app-prod`; exit code `0` | Req R7 |
| ST-22 | Stub `ssh` exits 255 with stderr `Host key verification failed.` | Output contains `FAIL app-prod - Host key verification failed.`; exit code `1` | Req R7 / AR #20 |
| ST-23 | No deploy config present | Exit code `2`; message names the missing path and the mount/restart hint | AR #20 |
| ST-24 | `--learn` with no host arguments | Exit code `2`; usage message | AR #19 |
| ST-25 | `--learn app-prod`; `ssh -G` reports no `proxyjump` and `port 22` | `ssh-keyscan -t ed25519,rsa -p 22 app-prod` runs; its lines are printed; exit code `0` | Req R8 |
| ST-26 | `--learn app-prod`; `ssh -G` reports `proxyjump deploy@bastion.corp:2222`; the bastion connection fails with a host-key error | The diagnostic names the bastion `Host`-block requirement and prints `ssh-keyscan -t ed25519,rsa -p 2222 bastion.corp`; no target keyscan runs; exit code `1` | AR #8, PF-001 |
| ST-27 | `--learn app-prod`; `ssh -G` reports the bastion; the bastion connection succeeds | `ssh -p 2222 deploy@bastion.corp "ssh-keyscan -t ed25519,rsa -p 22 app-prod"` runs; its lines are printed; exit code `0` | Req R8 |
| ST-28 | `ssh -G` fails for a host | Exit code `2`; the host is named | AR #20 |
| ST-29 | `fleet.sh check-ssh alpha` with a stubbed docker | The trace contains `exec -u docker alpha deploy-ssh-check` (under the merged compose invocation); exit code `0` | Req R9 / AR #18 |
| ST-30 | `fleet.sh check-ssh` with no organization | Exit non-zero; usage message | AR #18 |
| ST-31 | `fleet.sh check-ssh NoSuchOrg` | Exit non-zero; `unknown organization` message | AR #18 |
| ST-32 | Stubbed docker exits 7 for the exec | `fleet.sh` exits `7` | Req R9 |
| ST-36 | `--learn app-prod` with `Host app-prod` + `Hostname 10.20.1.5` (no jump); keyscan stub records argv | Keyscan runs against the resolved `10.20.1.5`; printed entries are keyed to the resolved name; exit code `0` | PF-002 |
| ST-37 | `--learn` with `HostName` and `HostKeyAlias` set | Printed first fields use the `HostKeyAlias` value; keyscan targets the resolved `hostname`; exit code `0` | PF-002 |
| ST-39 | Config contains `Host foo # comment` and `Host baz#qux`; run with no arguments | Only `foo` and `baz#qux` are tested; `#` and `comment` are not tested | PF-019 |
| ST-40 | `fleet.sh check-ssh Alpha` where `Alpha` declares no `deploy_ssh` | Exit non-zero; `organization 'alpha' has no deploy_ssh configured`; no `compose exec` in the trace | AR #18, PF-008 |

### Packaging (03-04) — `test/dockerfile.spec.test.sh`, `test/bootstrap.spec.test.sh`

| # | Input / Scenario | Expected Output / Behavior | Source |
| --- | ---------------- | -------------------------- | ------ |
| ST-33 | Static Dockerfile inspection | The Dockerfile installs `deploy-ssh-check.sh` as `/usr/local/bin/deploy-ssh-check` and marks it executable | Req R10 / AR #25 |
| ST-34 | Bootstrap spec with the fake repository providing `deploy-ssh-check.sh` | The script is installed into the install directory and listed in `.build-server-manifest` | Req R10 / AR #25 |
| ST-35 | Static inspection of `.gitignore` and `.dockerignore` | `.gitignore` excludes `/deploy-ssh/` (root-anchored) and `.dockerignore` excludes `deploy-ssh` (build context) | AR #5, AR #28 |

> **⚠️ AUTHORING RULE:** Derive expectations from the specification documents above. Do NOT
> imagine or infer what the implementation will produce. If the expected output cannot be
> determined from the spec, that is an ambiguity — add it to the Ambiguity Register and resolve it
> with the user before defining the test case.

## Test Categories

### Specification Tests (from ST-cases above)

> Written BEFORE implementation. Filed as `[feature].spec.test.sh`.

| Test File | ST Cases Covered | Component |
| --------- | ---------------- | --------- |
| `test/orgs.spec.test.sh` | ST-1..ST-10, ST-38, ST-41 | Fleet configuration / rendering |
| `test/fleet.spec.test.sh` | ST-11..ST-13, ST-29..ST-32, ST-40 | CLI behavior |
| `test/entrypoint.spec.test.sh` | ST-14..ST-19, ST-43..ST-45 | Container staging |
| `test/deploy-ssh-check.spec.test.sh` *(new)* | ST-20..ST-28, ST-36, ST-37, ST-39 | Check script |
| `test/dockerfile.spec.test.sh` | ST-33, ST-35 | Packaging and hygiene |
| `test/bootstrap.spec.test.sh` | ST-34 | Installer |

### Implementation Tests (edge cases, internals)

> Written AFTER implementation. Filed as `[feature].impl.test.sh`.

| Test File | Description | Priority |
| --------- | ----------- | -------- |
| `test/fleet.impl.test.sh` | Auto-create on `restart`/`update`/`update-runners`/`upgrade-all`; byte-identical generation with `deploy_ssh`; a validation failure preserves the previous generated file; sentinel files survive `clean --yes` and `upgrade-all --yes` (PF-016); the creation notice is silent on repeat runs or when only `keys/` is missing (RV-004) | High |
| `test/entrypoint.impl.test.sh` | Mode/ownership failures warn and continue; keys-only source without include; full re-copy when the source changes between boots; staging runs before the runner user starts (the `setpriv` stub records `deploy.d` existence); config-only source; a pre-existing `~/.ssh/config` is preserved (RV-101, RV-103) | High |
| `test/deploy-ssh-check.impl.test.sh` *(new)* | `Host` line parsing edge cases (inline comments, blank lines, mixed case, duplicates, multiple tokens); `-`-prefixed token rejection; empty `ssh-keyscan` output → FAIL; bastion authentication failure → `FAIL`, continue, exit 1; chained-jump unsupported message; multiple hosts with mixed results | Medium |

### Integration Tests

| Test | Components | Description |
| ---- | ---------- | ----------- |
| `verify.sh` runs the full suite | all | Every suite runs in order on each change (existing behavior) |

### End-to-End Tests

| Scenario | Steps | Expected Result |
| -------- | ----- | --------------- |
| Live-fleet deploy check (manual, documented in the guide) | Declare `deploy_ssh=`, add config/keys/known_hosts, `./fleet.sh up`, `./fleet.sh check-ssh <org>`, run a deploy step in a repository of the org | Check reports PASS; `scp`/`rsync`/`ssh` work through the bastion. Not automated in CI (AR #24) |

## Test Data

### Fixtures Needed

- Sandbox orgs.conf files and a symlink escape fixture (existing `new_sandbox` helpers).
- Entrypoint source fixture: `config`, `known_hosts`, `keys/prod` created with permissive modes
  (0644/0755), plus a stale-file variant. Permissive modes make ST-14 prove normalization.
- Stub `ssh` that records argv and emits a configurable `ssh -G` dump; it exits with `SSH_EXIT`
  and emits `SSH_STDERR` for connection attempts.
- Stub `ssh-keyscan` that records argv and prints `KEYS_CAN_OUTPUT`.

### Mock Requirements

- External commands (`ssh`, `ssh-keyscan`, `docker`, `dockerd`, `setpriv`, `curl`) are stubbed on
  PATH, exactly as the existing suites do — they are true externals in unit tests.
- Entrypoint staging harness (PF-004): the `chown` stub **records argv and never delegates** (it
  cannot succeed unprivileged); the `chmod` stub records argv and delegates to the real binary
  **only for paths under the test sandbox** — never for `/var/run/docker.sock` — so the suite keeps
  its "never touches the host Docker socket" property. The `setpriv` stub additionally records
  whether `~/.ssh/deploy.d` exists at the moment the runner user would start.

## Verification Checklist

- [ ] All specification test cases (ST-*) defined with concrete input/output pairs
- [ ] Every ST case traces to a requirement, spec doc, or AR entry
- [ ] Specification tests written BEFORE implementation
- [ ] Specification tests verified to FAIL before implementation (red phase)
- [ ] All specification tests pass after implementation (green phase)
- [ ] Implementation tests written for edge cases and internals
- [ ] All unit / integration tests pass
- [ ] No regressions in existing tests
- [ ] `bash test/verify.sh` passes; `npm ci && npm run docs:build` passes
