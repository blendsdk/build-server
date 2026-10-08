# Task T-03: Pass extra arguments through check-ssh

> **Type**: Task (lightweight) · **Feature**: deploy-ssh · **CodeOps Artifact Schema**: 1
> **Progress**: 4/4 tasks (100%)
> **Reasoning**: medium — user-facing CLI change; the passthrough must stay argv-based
> **Phase baseline tree**: 755f5cac7f37b8820950311990ab62c8c24fa770
> **Expected changes** (scope: strict): `fleet.sh`, `test/fleet.spec.test.sh`, `docs/guide/deploy-ssh.md`, `docs/guide/cli.md`, and the plan/roadmap documents (`99-execution-plan.md`, `00-review-report.md`, `codeops/features/deploy-ssh/00-roadmap.md`, `codeops/00-roadmap.md`)
> **Lenses**: correctness (no added risk lens: arguments are forwarded as argv, never shell-evaluated)

## Objective

Let operators use the short `./fleet.sh check-ssh <org> [args...]` form instead of a long
`docker compose ... exec` line when they need the checker's extra modes: focused host lists and
`--learn` for collecting host keys.

**Smallest viable design:** forward every argument after the organization verbatim — as separate
argv entries, never through a shell string — to `deploy-ssh-check` in the existing `compose exec`
invocation. The checker remains the sole validator of its own arguments; `fleet.sh` only resolves
the organization and the container. No new commands, flags, or files.

## Pinned behavior

- `check-ssh <org>` behaves exactly as today: tests every literal host from the staged config.
- Extra arguments are passed through unchanged, for example `check-ssh AcmeTools --learn app-prod`
  or `check-ssh AcmeTools app-worker-01 app-worker-02`.
- The organization is still required; an unknown organization or an organization without
  `deploy_ssh` fails before any compose call (unchanged).
- The usage text becomes `check-ssh <org> [args...]`; the usage error matches.
- The checker's exit codes pass through unchanged (0 = all passed, 1 = a host failed, 2 = usage or
  configuration error).
- `deploy-ssh-check` itself is not changed.

### Specification test cases (in `test/fleet.spec.test.sh`, ST-60..ST-61)

1. ST-60: `check-ssh Alpha --learn app-prod` forwards both arguments to `deploy-ssh-check`.
2. ST-61: `check-ssh Alpha app-worker-01 app-worker-02` forwards the host list in order.
3. Existing ST-29 (docker user, merged compose invocation), ST-30 (missing organization), and
   ST-31 (unknown organization) stay green.

## Tasks

- [x] T-03.1 Add ST-60..ST-61 to `test/fleet.spec.test.sh` ✅ (completed: 2026-10-08 09:47)
- [x] T-03.2 Run the fleet spec suite and record the red phase (the forwarding cases fail; existing
  cases stay green) ✅ (completed: 2026-10-08 09:47 — 45 existing sections green, then FAIL at
  ST-60 as expected)
- [x] T-03.3 Implement the forwarding in `fleet.sh`: drop the extra-argument guard, pass the
  remaining arguments verbatim, and update the usage text and messages ✅ (completed: 2026-10-08 09:49
  — full verify passes; ST-60/ST-61 green)
- [x] T-03.4 Update the docs (`docs/guide/deploy-ssh.md` learn and explicit-host examples,
  `docs/guide/cli.md` row) and run the full verification ✅ (completed: 2026-10-08 09:50 — full
  verify and docs build pass)

**Verify**: `bash test/verify.sh`; because docs change, also `npm ci && npm run docs:build`
