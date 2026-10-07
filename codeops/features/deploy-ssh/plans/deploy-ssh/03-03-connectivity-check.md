# Connectivity Check: deploy-ssh

> **Document**: 03-03-connectivity-check.md
> **Parent**: [Index](00-index.md)

## Overview

Two operator tools close the loop:

- `deploy-ssh-check.sh` (installed as `/usr/local/bin/deploy-ssh-check`) tests the deploy SSH
  configuration from inside the runner, with optional host-key learning.
- `fleet.sh check-ssh <org>` runs the script in one organization's runner as the `docker` user.

Both are on-demand; nothing runs automatically at container boot (AR #7).

## Architecture

### Current Architecture

There is no deployment-related tooling. `fleet.sh` offers lifecycle commands and executes Compose
under the project name (`fleet.sh:212-215`).

### Proposed Changes

| Change | Location |
| ------ | -------- |
| New script implementing test and `--learn` modes | `deploy-ssh-check.sh` (new, repo root) |
| New `check-ssh <org>` subcommand + usage line | `fleet.sh` `usage()`, command `case` |
| Image installation and installer wiring | `Dockerfile`, `bootstrap.sh` (see `03-04-packaging-and-docs.md`) |

## Implementation Details

### Configuration discovery

The script reads `${HOME}/.ssh/deploy.d/config` — the staged copy produced by the entrypoint
(`03-02-container-staging.md`). When the file is missing it prints

```
deploy-ssh-check: no deploy-ssh configuration at <path> (mount the folder and restart the runner)
```

and exits `2`. `fleet.sh check-ssh` runs the script with `-u docker`, so `HOME` is the runner user's
home; the guide documents the same user requirement for manual `docker compose exec` usage.

### Test mode (default)

Host selection:

- With explicit arguments, only those hosts are tested.
- Without arguments, the script parses `Host` lines (case-insensitive keyword, leading whitespace
  allowed) from the deploy config; literal tokens are tested, tokens containing `*`, `?`, or `!` are
  listed once as `skipped pattern '<pattern>' (pass explicit hostnames to test it)`.
- Duplicates are tested once. No literal hosts and no arguments is a usage/config error (exit `2`).
- Tokenization stops at the first token beginning with `#` (an OpenSSH inline comment); a `#` inside
  a token is a literal character (`Host baz#qux` is one token). Blank lines and full-line comments
  are ignored.
Host tokens and explicit arguments must not start with `-` (a defensive guard so a config entry can
never be interpreted as an SSH option); a violating token is a usage/config error (exit `2`).

Per host:

1. Resolve the effective configuration with `ssh -G <host>` (needed for the jump annotation).
   A failure here means the SSH configuration is invalid: print an error and exit `2` (AR #20).
2. Run `ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes <host> true` and
   capture stderr.
3. Print `PASS <host>` (plus ` (jump <proxyjump>)` when a jump applies) or
   `FAIL <host> - <last non-empty stderr line>` (plus the jump annotation).

The forced `StrictHostKeyChecking=yes` is deliberate: the check verifies that host keys are pinned;
it never weakens verification (AR #6). Under the documented `accept-new` fallback, a PASS may rest
on a key SSH learned at runtime: the host folder remains the source of truth, and the staged copy
is replaced at every boot, so run the check right after a runner restart for a pinning verdict
(AR #8, PF-013).

When a target uses a jump, the implicit bastion connection cannot inherit command-line options, so
the check resolves every hop through `ssh -G` and requires `StrictHostKeyChecking yes` in each
hop's effective configuration; a host whose bastion is not strictly verified reports
`FAIL <host> - bastion '<hop>' host-key checking is not strict (set StrictHostKeyChecking yes for it)`
(SA-302).

After all hosts, the script prints `deploy-ssh-check: <ok> of <total> hosts passed`; when any host
failed it also prints the hint `hint: run 'deploy-ssh-check --learn <host>' to collect a failing
host key`. Exit code: `0` all passed, `1` at least one failed, `2` usage/config error (AR #20).

### Learn mode (`--learn <host>...`)

At least one host is required; zero hosts is a usage error (exit `2`). For each host:

1. Resolve the target through `ssh -G <host>` and use its effective `hostname`, `hostkeyalias`
   (when set), `port`, and `proxyjump`. A failure exits `2`.
2. **No jump:** run `ssh-keyscan -t ed25519,rsa -p <port> <resolved-name>` from the runner and print
   its output, keyed to the resolved name (rewrite the first field to the `HostKeyAlias` value when
   one is configured).
3. **Jump:** parse the `[user@]host[:port]` jump specification first (inline jump ports are not
   resolved by `ssh -G`), then resolve the bastion through `ssh -G [-p <jump-port>] <jump-host>`
   and use its effective hostname/port/user. The bastion's own key must already be pinned (AR #8).
   - First attempt `ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes
     [-p <jump-port>] [<user>@]<jump-host> true`.
   - When it fails with host-key verification, print the actionable diagnostic naming both required
     pieces (the bastion `Host`-block wiring and the keyscan), for example:
     ```
     The bastion '<effective jump spec>' is not covered by the deploy known_hosts. Check that:
       1) the deploy config contains a Host block for the bastion (or the target pattern) setting
          UserKnownHostsFile ~/.ssh/deploy.d/known_hosts and StrictHostKeyChecking yes, and
       2) its key is pinned. To collect it:
          ssh-keyscan -t ed25519,rsa -p <effective jump port> <effective jump host>
     Append the output to the deploy folder's known_hosts on the host, restart the runner, then re-run --learn.
     ```
     (The bastion is a separate SSH session: the target block's options do not apply to it — PF-001.)
   - When it fails with `REMOTE HOST IDENTIFICATION HAS CHANGED`, print an instruction to replace the
     pinned entry (remove the old line) instead of appending a new one.
   - Any other bastion failure prints `FAIL <bastion> - <last stderr line>` and skips that host.
   - On success, run
     `ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes [-p <effective jump port>] [<user>@]<effective jump host> 'ssh-keyscan -t ed25519,rsa -p <target port> <resolved target name>'`
     and print the collected lines (keyed per step 2). Successful output ends with the install
     instruction: `Append the lines above to the deploy folder's known_hosts on the host, restart the runner, then re-run --learn.`
4. Chained jumps (`proxyjump` containing `,`) are unsupported: print
   `deploy-ssh-check: --learn does not support chained jumps ('<proxyjump>'); collect the keys manually`
   and exit `2` (AR #27). Manual `ssh-keyscan` on the last hop still works and is documented.
5. Failures are per host: the remaining hosts are still processed, and the run exits `1` when any
   host failed (PF-012).

`--learn` never writes files; output is ready-to-paste `known_hosts` content followed by the
install/restart instruction (AR #7, #19). Exit code: `0` when every requested host produced keys,
`1` when any host failed, `2` for usage/config errors (AR #20).

The `[user@]host[:port]` parser handles the optional user and optional numeric port. Resolved
target and bastion hostnames, users, and ports are validated against a strict allowlist
(`A-Za-z0-9._-`, no leading `-`; ports decimal) before use, because they feed ssh argv and a remote
shell command; unsupported values are configuration errors (exit `2`). Bracketed IPv6 literals are
not supported by `--learn`; collect those keys manually with `ssh-keyscan` on the bastion (PF-018,
SA-301, SA-303).

### `fleet.sh check-ssh <org>`

```
usage line:   check-ssh <org>         Run the deploy SSH connectivity check in one runner
behavior:     parse_config; render_compose;
              require exactly one argument (otherwise: die "usage: fleet.sh check-ssh <org>");
              resolve the org slug (unknown org -> the standard "unknown organization" error);
              require ORG_DEPLOY_SSH for the slug (otherwise:
                  die "organization '<slug>' has no deploy_ssh configured" — PF-008);
              compose exec -u docker <slug> deploy-ssh-check
```

The Compose exit status propagates. A stopped or missing container produces Compose's own error
(AR #18). No arguments are forwarded to the script; `--learn` is run directly inside the container
(documented in the guide).

## Code Examples

### Example 1: Healthy check

```
$ ./fleet.sh check-ssh AcmeTools
PASS app-prod (jump deploy@bastion.corp:22)
PASS app-worker-01 (jump deploy@bastion.corp:22)
FAIL app-worker-02 - Host key verification failed.
deploy-ssh-check: 2 of 3 hosts passed
hint: run 'deploy-ssh-check --learn <host>' to collect a failing host key
$ echo $?
1
```

### Example 2: Learning through a bastion

```
$ docker compose -f docker-compose.yml -f docker-compose.generated.yml \
    --project-name example exec -u docker acmetools deploy-ssh-check --learn app-worker-02
app-worker-02 ssh-ed25519 AAAAC3Nza...
Append the lines above to the deploy folder's known_hosts on the host, restart the runner, then re-run --learn.
```

## Error Handling

| Error Case | Handling Strategy | AR Ref |
| ---------- | ----------------- | ------ |
| Deploy config missing | Exit `2` with the mount/restart hint | #4, #20 |
| No literal hosts and no arguments | Exit `2` with a pass-hostnames hint | #19, #20 |
| A host token starts with `-` | Usage/config error (exit `2`); never passed to `ssh` as an option | #19, #20 |
| Pattern-only `Host` entries | Listed as skipped; explicit hosts supported | #19 |
| `ssh -G` fails | Exit `2` naming the host (invalid configuration) | #20 |
| Host key unknown or changed | `FAIL` with SSH's reason; strict checking is never relaxed | #6, #8 |
| Bastion key not pinned during `--learn` | Print the bastion `Host`-block + `ssh-keyscan` diagnostic; skip the host; exit `1` | #8, PF-001 |
| Bastion authentication or network failure during `--learn` | `FAIL <bastion> - <reason>`; skip the host; exit `1` | PF-012 |
| Bastion presents a changed key | Replacement instruction (remove the old pinned line); skip the host; exit `1` | PF-012 |
| Aliased target or bastion (`HostName` / `HostKeyAlias`) | Keyscan targets and printed entries use the resolved name | PF-002 |
| A resolved value contains unsupported characters (host, user, or port) | Configuration error (exit `2`); values are validated before they reach ssh or a remote shell | SA-301, SA-303 |
| Test mode with a jump whose effective configuration is not `StrictHostKeyChecking yes` | `FAIL` naming the hop; the host counts as failed | SA-302 |
| Bracketed IPv6 learn target | Configuration error (exit `2`) with the manual-keyscan note | PF-018 |
| `Host` line with an inline comment | Tokenization stops at `#`; `#` inside a token is literal | PF-019 |
| Chained jumps in `--learn` | Unsupported message; exit `2` | #27 |
| `check-ssh` without a valid org / extra arguments | Usage error; unknown org uses the standard error | #18 |
| `check-ssh` for an org without `deploy_ssh` | Fail fast before `compose exec`: `organization '<slug>' has no deploy_ssh configured` | #18, PF-008 |
| Container not running | Compose's own error is propagated | #18 |

> **Traceability:** Every error-handling strategy and design choice references the Ambiguity
> Register entry (AR #) that resolved it. See `00-ambiguity-register.md`.

## Testing Requirements

- Specification tests (see `07-testing-strategy.md`): ST-20..ST-32, ST-36, ST-37, ST-39, ST-40.
- Implementation tests: `Host` parsing edge cases (inline comments, blank lines, mixed case,
  duplicates), `-`-prefixed token rejection, `ssh-keyscan` empty output, bastion authentication
  failure, chained-jump message, and exit-code propagation through `fleet.sh`.
