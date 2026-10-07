# deploy-ssh Implementation Plan

> **Feature**: Host-mounted deploy SSH material for runner containers, with an in-container connectivity check
> **Status**: Planning Complete
> **Created**: 2026-10-07
> **Implements**: — (standalone plan; no upstream RD — [`01-requirements.md`](01-requirements.md) owns the requirements)
> **CodeOps Artifact Schema**: 1

## Overview

Runner jobs must deploy artifacts to internal servers over SSH, sometimes through a jump (bastion)
host, and a private target may be reachable only from that bastion. Today the fleet cannot provide
this material: the image bakes only the host's GitHub key (`Dockerfile:52-59`), the host's
`known_hosts` never reaches the container, and a non-interactive job has no way to accept a host key
it has never seen. Plain `scp`/`ssh` to a new internal host therefore fails at host-key
verification.

This plan adds an operator-managed folder per organization, `deploy-ssh/<slug>/`, declared with
`deploy_ssh=` in `orgs.conf` and mounted read-only into that organization's runner at
`/run/deploy-ssh`. The container entrypoint copies the folder to the runner user's home with correct
ownership, modes, and known-hosts wiring, so plain `ssh`, `scp`, `rsync`, and `git` work without any
per-repository CI setup (AR #1, AR #2). A `deploy-ssh-check` script plus `fleet.sh check-ssh` test
connectivity and print ready-to-paste host keys for pinning (AR #6–#8).

The design deliberately keeps the smallest viable shape: it reuses the Compose volume pattern of
`build_temp`, the entrypoint's root-side staging pattern, and the repository's stub-based test
harnesses. No new dependency, layer, or background mechanism is introduced.

## Minimum-Sufficient Baseline

**Original goal:** Let jobs use `ssh`/`scp`/`rsync` to reach internal deployment servers, including
through a jump host, without adding setup steps to every repository's workflows.

**Smallest viable design:** A per-org folder on the host, declared in `orgs.conf` and validated like
`context=`, rendered as a read-only Compose volume (the `build_temp` pattern), staged at container
boot by the rootside entrypoint (the baked-`~/.ssh` pattern), and consumed by plain OpenSSH. One
small check/learn script plus a thin `fleet.sh` command complete the operator loop.

**Excluded machinery:** CI-side per-job setup script (AR #2), live folder re-sync (AR #22),
system-wide `ssh_config.d` drop-in (AR #10), compatibility/version gate (AR #23), loopback sshd
test fixture (AR #24).

**Approved complexity:** None — the Complexity Escalation Gate found no material support surface
beyond the requested feature; every artifact reuses an existing project pattern.

## Document Index

| #   | Document                                                     | Description                                    |
| --- | ------------------------------------------------------------ | ---------------------------------------------- |
| AR  | [Ambiguity Register](00-ambiguity-register.md)               | Zero-Ambiguity Gate decisions (audit trail)    |
| 00  | [Index](00-index.md)                                         | This document — overview and navigation        |
| 01  | [Requirements](01-requirements.md)                           | Feature requirements, scope, and acceptance    |
| 02  | [Current State](02-current-state.md)                         | Analysis of the current implementation         |
| 03-01 | [Organizations configuration](03-01-orgs-configuration.md) | `deploy_ssh=` option, validation, auto-create, Compose mount |
| 03-02 | [Container staging](03-02-container-staging.md)            | Entrypoint staging, ownership, include wiring  |
| 03-03 | [Connectivity check](03-03-connectivity-check.md)          | `deploy-ssh-check` script and `fleet.sh check-ssh` |
| 03-04 | [Packaging and documentation](03-04-packaging-and-docs.md) | Image install, bootstrap manifest, docs set    |
| 07  | [Testing Strategy](07-testing-strategy.md)                   | Specification test cases and verification      |
| 99  | [Execution Plan](99-execution-plan.md)                       | Phases, sessions, and task checklist           |

## Quick Reference

### Usage Examples

Host preparation (once per organization):

```
deploy-ssh/acmetools/
├── config          # SSH config fragment, included by the runner
├── known_hosts     # pinned bastion and target host keys
└── keys/
    └── prod        # 0600 private key
```

`orgs.conf`:

```
AcmeTools deploy_ssh=deploy-ssh/acmetools
```

`deploy-ssh/acmetools/config`:

```
Host app-prod app-* 10.20.*
    User deploy
    ProxyJump deploy@bastion.corp:22
    IdentityFile ~/.ssh/deploy.d/keys/prod
    UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
    StrictHostKeyChecking yes

# The jump host is a separate SSH session: it needs its own known-hosts wiring.
Host bastion.corp
    UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
    StrictHostKeyChecking yes
```

A workflow step in any repository of the organization — no setup step, no secrets:

```yaml
- name: Deploy
  run: |
    rsync -az --delete dist/ app-prod:/srv/app/
    ssh app-prod 'systemctl restart app'
```

Operator commands:

```bash
./fleet.sh up                        # applies the mount; creates the folder if missing
./fleet.sh check-ssh AcmeTools       # tests every literal host in the deploy config
```

### Key Decisions

| Decision | Outcome | AR |
| -------- | ------- | -- |
| Delivery model | Host-mounted per-org folder; no CI-side setup | #1, #2 |
| Enablement | Opt-in `deploy_ssh=` path; folder auto-created | #3, #15 |
| Container staging | Read-only mount + entrypoint copy with ownership/modes | #4, #5, #14 |
| Host keys | Pinned once; `--learn` prints keys; `accept-new` documented fallback | #6, #8 |
| Verification | `deploy-ssh-check` + `fleet.sh check-ssh`; exit codes 0/1/2 | #7, #11, #18, #20 |
| Safety | Never delete host folders; reject root/traversal paths | #16, #17 |

## Specialist Agents

**None** — the capability-gap check ran against this repository's evidence and found no gap a
standing specialist would close.

_Detection evidence: the project is bash/Docker/CI infrastructure (`fleet.sh`, `entrypoint.sh`,
`test/*.spec.test.sh`); the SSH semantics involved (config precedence, `ProxyJump`, `known_hosts`)
are covered by the catalog `security-auditor` plus dynamic packets and by this plan's ST-cases; there
is no specialized framework/DSL and no recorded review rework in this area (`codeops/features/_maintenance`
history contains only completed tasks)._

## Related Files

| File | Change |
| ---- | ------ |
| `fleet.sh` | `deploy_ssh=` parsing/validation, auto-create, mount rendering, `check-ssh` command |
| `entrypoint.sh` | Deploy mount staging, ownership/modes, `Include` wiring |
| `deploy-ssh-check.sh` | New connectivity check and host-key learning script |
| `Dockerfile` | Install `deploy-ssh-check` into the image |
| `bootstrap.sh` | `deploy-ssh-check.sh` added to the installed runtime files |
| `.gitignore`, `.dockerignore` | Exclude the `deploy-ssh/` folder from git and build contexts |
| `test/` | Extended and new spec/impl tests; `verify.sh` and shellcheck wiring |
| `docs/` | New guide page, sidebar entry, and updates to reference/operations/security pages |
