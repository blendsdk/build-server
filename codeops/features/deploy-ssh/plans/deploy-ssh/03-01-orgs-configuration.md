# Organizations Configuration: deploy-ssh

> **Document**: 03-01-orgs-configuration.md
> **Parent**: [Index](00-index.md)

## Overview

Adds the `deploy_ssh=` key to `orgs.conf`, validates it with the same safety rules as `context=`,
ensures missing folders exist before runner containers start, and renders a read-only mount for each
declaring organization.

## Architecture

### Current Architecture

`parse_config()` reads `orgs.conf` into parallel arrays (`fleet.sh:62-162`); `render_compose()`
writes `docker-compose.generated.yml` with environment variables and an optional `build_temp`
volume (`fleet.sh:164-209`); lifecycle commands call `parse_config` and `render_compose` before
`compose` operations (`fleet.sh:567-662`).

### Proposed Changes

| Change | Location |
| ------ | -------- |
| New `ORG_DEPLOY_SSH` parallel array + `deploy_ssh` option parsing/validation | `fleet.sh` `parse_config()` |
| New `ensure_deploy_dirs()` creating missing folders with `0700` and printing a notice | `fleet.sh`, called by `up`/`restart`/`update`/`update-runners`/`upgrade-all` |
| Volume rendering for the deploy mount, merged with `build_temp` under one `volumes:` key | `fleet.sh` `render_compose()` |

## Implementation Details

### orgs.conf grammar

```
# <name> [url=...] [context=...] [build_temp=1] [deploy_ssh=<path>]

AcmeTools deploy_ssh=deploy-ssh/acmetools
Globex build_temp=1 deploy_ssh=deploy-ssh/shared
```

`deploy_ssh` takes a relative path that must be a strict subdirectory of `deploy-ssh/` — for
example `deploy-ssh/<slug>` or a folder shared by several organizations (AR #4, AR #13, amended by
PF-003).

### Validation

Validation runs in `parse_config()` in this order and fails with a line-numbered message
(`<message>` below is appended to `orgs.conf:<line>: `):

| Step | Condition | Message | AR |
| ---- | --------- | ------- | -- |
| 1 | Value is empty | `deploy_ssh path must not be empty` | #12 |
| 2 | Value starts with `/` | `deploy_ssh path must be relative` | #12 |
| 3 | Any `/`-separated segment equals `..` | `deploy_ssh path must not contain '..'` | #12 |
| 4 | Value contains any of `*`, `?`, `[`, `:`, `$` | `deploy_ssh path must not contain '*', '?', '[', ':', or '$'` | PF-006 |
| 5 | Path exists but is not a directory | `deploy_ssh '<value>' is not a directory` | #12 |
| 6 | `realpath` (or `realpath -m` when missing) equals the repository root | `deploy_ssh path must not be the repository root` | #16 |
| 7 | Resolved path is not inside the repository | `deploy_ssh '<value>' resolves outside the repository` | #12 |
| 8 | Resolved path is not a strict subdirectory of `<root>/deploy-ssh` | `deploy_ssh path must be inside 'deploy-ssh/'` | PF-003 |
| 9 | Resolved path contains `*`, `?`, `[`, `:`, `$`, or a control character | `deploy_ssh '<value>' resolves to a path with unsupported characters` | SA-001 |

The resolved absolute path is stored in `ORG_DEPLOY_SSH`; rendering and creation use the path
relative to the repository root. Validation never creates the folder; creation happens only in the
commands listed below (AR #15).

### Auto-creation

```bash
# Ensure a declared deploy folder exists, with restricted modes. Only commands that start runner
# containers call this; generate/status never create anything.
ensure_deploy_dirs() {
    # for each org with deploy_ssh:
    #   if the folder is missing:
    #       umask 077; mkdir -p <resolved>/keys
    #       echo "fleet: created <relative> (add config, known_hosts, and keys, then restart the"
    #       echo "runner to apply)"
    #   elif <resolved>/keys is missing:
    #       umask 077; mkdir -p <resolved>/keys   (silent)
}
```

Call sites: `up`, `restart`, `start`, `update`, `update-runners`, `upgrade-all` — each runs after
its own failure points and immediately before its first `compose up` (for `upgrade-all`: after
confirmation and the version fetch; for `update-runners`: after the fetch and rebuilds; for
`update`: after the argument check), so an aborted command creates nothing. `generate`, `down`,
`stop`, `clean`, and `status` do not create folders (AR #15, refined by PF-007 and RV-002). Each
path is re-canonicalized immediately before creation; a path that changed since validation (for
example a swapped symlink) is skipped with a warning (SA-003). Nothing ever deletes a folder
(AR #17).

### Volume rendering

The renderer emits one `volumes:` block per service when any mount applies:

```yaml
    volumes:
      - ./deploy-ssh/acmetools:/run/deploy-ssh:ro
      - /tmp:/build-temp
```

The deploy mount is always read-only (`:ro`, AR #5). Services without `deploy_ssh` and without
`build_temp` emit no `volumes:` key. Rendering stays byte-identical for identical inputs (the
existing idempotence guarantee in `test/fleet.impl.test.sh`).

### Unchanged behavior

- `fleet.sh status` output is unchanged (AR #21).
- `down`/`clean` never touch `deploy-ssh/` folders (AR #17).

## Code Examples

### Example 1: Declaring an org and applying it

```bash
# orgs.conf
AcmeTools deploy_ssh=deploy-ssh/acmetools

./fleet.sh up
# fleet: generated 1 runner(s): acmetools
# fleet: created deploy-ssh/acmetools (add config, known_hosts, and keys, then restart the runner to apply)
```

### Example 2: Rejecting an unsafe path

```bash
# orgs.conf
AcmeTools deploy_ssh=../outside
# ./fleet.sh generate
# fleet: ERROR: orgs.conf:2: deploy_ssh path must not contain '..'
```

## Error Handling

| Error Case | Handling Strategy | AR Ref |
| ---------- | ----------------- | ------ |
| Empty / absolute / `..` / metacharacters / outside `deploy-ssh/` / escaping / root path | Fail `parse_config` with the line-numbered message; no generated file is written (existing atomic-render behavior) | #12, #16, PF-003, PF-006 |
| Existing non-directory at the path | Fail `parse_config` with `is not a directory` | #12 |
| Folder missing on a container-starting command (`up`, `restart`, `start`, `update`, `update-runners`, `upgrade-all`) | Create folder + `keys/` (`0700`) and print a notice; command continues | #15, PF-007 |
| Folder missing while another command runs (`generate`, `status`) | No action; rendering and status are side-effect free | #15 |
| Folder removed by the operator | Nothing recreates it except a container-starting command; nothing deletes it | #17 |

> **Traceability:** Every error-handling strategy and design choice references the Ambiguity
> Register entry (AR #) that resolved it. See `00-ambiguity-register.md`.

## Testing Requirements

- Specification tests (see `07-testing-strategy.md`): ST-1..ST-13, ST-38, ST-41.
- Implementation tests: auto-create coverage for the remaining commands, frozen folders across
  `clean`/`upgrade-all`, idempotent rendering with `deploy_ssh`, and previous-output preservation on
  validation failure.
