# Deploy over SSH

Runner containers can deploy files and run commands on internal servers over SSH, including through
a bastion (jump) host. The capability is operator-managed: you keep the keys and SSH configuration
in a folder on the host, and jobs use them with plain `ssh`, `scp`, `rsync`, and `git` — no
repository-side setup and no CI secrets.

## When to use it

- A workflow must deploy to a private or internal server.
- The targets change rarely, so a host-managed folder suits them.
- Some targets are only reachable through a bastion.

The feature is opt-in per organization. Organizations that do not declare it get no mount.

## How it works

| Step | Where |
| --- | --- |
| Host folder `deploy-ssh/<slug>/` holds `config`, `known_hosts`, and `keys/` | Host |
| The generated service mounts the folder read-only at `/run/deploy-ssh` | Compose |
| The entrypoint copies it to the runner user's `~/.ssh/deploy.d/` (`0600` files, `0700` directories, owned by `docker`) | Container boot |
| The entrypoint prepends `Include ~/.ssh/deploy.d/config` to `~/.ssh/config`, exactly once | Container boot |
| Jobs run `ssh`, `scp`, `rsync`, and `git` normally | Job |

The host mount is read-only, so jobs cannot change the folder. The copy inside the container is
rebuilt at every boot, so host changes apply after a runner restart — see
[Apply and refresh](#apply-and-refresh).

## Host folder layout

Create `deploy-ssh/<slug>/` at the repository root, for example `deploy-ssh/acmetools/`:

```
deploy-ssh/acmetools/
├── config          # OpenSSH client config (Host blocks)
├── known_hosts     # pinned host keys
└── keys/           # private keys referenced by IdentityFile
```

- Keep the folder `0700` and the keys `0600` on the host.
- `config` is optional, but a folder without it gets no `Include` line — a keys-only folder is
  valid.
- The whole `deploy-ssh/` tree is gitignored and excluded from Docker build contexts. Never commit
  keys.

## Declare the option

Add one key to the organization's line in `orgs.conf`:

```
AcmeTools deploy_ssh=deploy-ssh/acmetools
```

Rules:

| Rule | Detail |
| --- | --- |
| Relative path | Must not start with `/` |
| Inside `deploy-ssh/` | Must be a strict subdirectory such as `deploy-ssh/<slug>`; bare `deploy-ssh` is rejected |
| Safe characters | No `..`, `*`, `?`, `[`, `:`, `$`, and the resolved path must stay inside the repository |
| Auto-created | When missing, a container-starting command creates the folder and `keys/` at `0700` and prints a notice |

See [Organizations](/guide/organizations) for the full field list. `generate` and `status` never
create folders; `up`, `restart`, `start`, `update`, `update-runners`, and `upgrade-all` do. Host
folders are never deleted, even when the option is removed.

## The config template

Write the `config` file as ordinary OpenSSH client configuration. Use the absolute container paths
shown below: the file is staged at `~/.ssh/deploy.d/`.

```
# Target hosts (private; reachable only through the bastion)
Host app-prod app-worker-01
    HostName 10.20.1.5
    User deploy
    Port 22
    IdentityFile ~/.ssh/deploy.d/keys/prod
    UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
    StrictHostKeyChecking yes
    ProxyJump deploy@bastion.corp:22

# The bastion is a separate SSH session and needs its own Host block.
Host bastion.corp
    HostName bastion.corp
    User deploy
    IdentityFile ~/.ssh/deploy.d/keys/bastion
    UserKnownHostsFile ~/.ssh/deploy.d/known_hosts
    StrictHostKeyChecking yes
```

> **The bastion block is not optional.** A `ProxyJump` opens the bastion as its own SSH connection.
> The target's options — including `UserKnownHostsFile` and `StrictHostKeyChecking` — do not apply
> to it. Without a matching bastion `Host` block that pins its key and sets
> `StrictHostKeyChecking yes`, the jump cannot be verified and the check fails the host.

Notes:

- The entrypoint adds `Include ~/.ssh/deploy.d/config` for you; do not add it yourself.
- Several `Host` patterns and several keys in `keys/` are fine; each target only needs its own
  `IdentityFile`.
- Keys must be keyed to the name SSH verifies. When you set `HostKeyAlias`, key the entry to that
  alias.

## Collect and pin host keys

SSH must recognize each target's host key, or a non-interactive job fails with
`Host key verification failed.` Pin the keys in `known_hosts`.

### Learn the keys

Run the checker's learn mode inside the runner. It resolves each target and its bastion and prints
ready-to-paste `known_hosts` lines:

```bash
docker compose -f docker-compose.yml -f docker-compose.generated.yml \
  exec -u docker acmetools deploy-ssh-check --learn app-prod
```

Run this from the repository root, so Docker Compose reads the same project name as `fleet.sh`.

For a private target behind a bastion, the command collects the key **on the bastion** and prints
it, because the runner cannot reach the target directly. `--learn` never writes files.

If the bastion's own key is not pinned yet, the command prints the exact `ssh-keyscan` line to run
on the bastion, plus the reminder that the config needs a matching bastion `Host` block. Pin the
bastion key first, restart the runner, then re-run `--learn`.

### Or collect manually

```bash
# On the runner, for a directly reachable target — use the resolved HostName, not a Host alias
# (ssh-keyscan does not read the SSH config):
ssh-keyscan -t ed25519,rsa -p 22 10.20.1.5

# On the bastion, for a private target:
ssh-keyscan -t ed25519,rsa -p 22 10.20.1.5
```

Append the output to `deploy-ssh/acmetools/known_hosts` on the host, restart the runner, and re-run
the check.

### The `accept-new` fallback

Pinning is the recommended path. If you choose `StrictHostKeyChecking accept-new` for a target,
SSH learns the key on first contact, and writes it into the staged `known_hosts` inside the
container. A `PASS` from the check can then rest on a key learned at runtime rather than a key in
your host folder, because the staged copy is replaced at every boot. To get a real pinning verdict:

1. Restart the runner, so the staged copy is rebuilt from the host folder.
2. Run the check immediately.

The check forces strict host-key checking for the connection it makes; it never weakens
verification.

## Apply and refresh

| Action | Command |
| --- | --- |
| Apply a new or changed `deploy_ssh` declaration | `./fleet.sh up` |
| Apply changed `config`, `known_hosts`, or `keys/` | `./fleet.sh restart` (or `stop` + `start`, or `update <org>`) |
| Check connectivity | `./fleet.sh check-ssh <org>` |

Staging happens at container boot, so **file changes need a runner restart**. A restart recreates
the container and interrupts any job running on it — do it between jobs.

## Check connectivity

```bash
./fleet.sh check-ssh AcmeTools
```

This runs `deploy-ssh-check` in that organization's runner as the `docker` user and propagates its
exit code. The script is also installed at `/usr/local/bin/deploy-ssh-check` inside the container.

Without arguments, the check tests every literal hostname in the `Host` lines of your config.
Pattern entries (`*`, `?`, `!`) are listed once as skipped, because a pattern can match many hosts.
Pass explicit hostnames to test a pattern:

```bash
docker compose -f docker-compose.yml -f docker-compose.generated.yml \
  exec -u docker acmetools deploy-ssh-check app-worker-01 app-worker-02
```

Output:

```
PASS app-prod (jump deploy@bastion.corp:22)
PASS app-worker-01 (jump deploy@bastion.corp:22)
FAIL app-worker-02 - Host key verification failed. (jump deploy@bastion.corp:22)
deploy-ssh-check: 2 of 3 hosts passed
hint: run 'deploy-ssh-check --learn <host>' to collect a failing host key
```

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Every tested host passed |
| `1` | At least one host failed |
| `2` | Usage or configuration error (missing config, invalid SSH configuration, unsupported values) |

The check fails a host whose bastion hop is not strictly verified. That is deliberate: a `PASS`
means every hop was pinned.

## Use it from a job

After staging, plain tools work with no wrapper:

```yaml
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: rsync -az --delete ./dist/ app-prod:/var/www/app/
      - run: ssh app-prod 'systemctl reload app'
```

`scp`, `rsync`, and `git` all use the same `Host` blocks, including `ProxyJump`.

## Multiple targets, keys, and bastions

- One folder serves several targets: add one `Host` block per target and put each private key in
  `keys/`.
- Each bastion needs its own `Host` block, even when several targets share it.
- Only single-hop jumps are supported. Chained jumps (`ProxyJump a,b`) cannot be learned by
  `deploy-ssh-check --learn`; collect those keys manually with `ssh-keyscan` on the last hop.

## Share a folder across organizations

Two organizations may declare the same path:

```
One deploy_ssh=deploy-ssh/shared
Two deploy_ssh=deploy-ssh/shared
```

Each runner mounts it read-only. Remember that this shares every key in the folder with every job
of both organizations — see [Security](#security).

## Rotation and backups

- **Rotate a key:** add the new key to `keys/`, point `IdentityFile` at it, restart the runner, then
  remove the old key.
- **A target's host key changed:** remove the old `known_hosts` line and add the new one. `--learn`
  prints a replacement instruction when it detects a changed key. Never keep both lines — SSH
  refuses a host that has two different keys.
- **Back up the folder:** `deploy-ssh/` is host-local and gitignored, so include it with your other
  credentials when you back up the host — see [Upgrades and changes](/operations/upgrades).

## Manual live-fleet checklist

CI cannot reach a real bastion, so verify a new setup by hand once:

- [ ] Declare `deploy_ssh=deploy-ssh/<slug>` and run `./fleet.sh up`; the notice confirms the
  folder was created.
- [ ] Add `config`, `known_hosts`, and `keys/` (folder `0700`, keys `0600`).
- [ ] Pin the bastion key, then pin each target key with `deploy-ssh-check --learn <host>` through
  the bastion.
- [ ] Restart the runner so the folder is staged.
- [ ] `./fleet.sh check-ssh <org>` reports `PASS` for every host, and `echo $?` prints `0`.
- [ ] Force a failure (for example a key that is not pinned) and confirm the check reports `FAIL`
  with exit `1`.
- [ ] Run a deploy step in a repository of the organization: `rsync`/`scp` a file to a target, `ssh`
  a command, and fetch over `git` — all through the bastion.

## Troubleshooting

| Symptom | First step |
| --- | --- |
| `Host key verification failed.` | Run `deploy-ssh-check --learn <host>`, pin the printed key, restart the runner |
| `deploy-ssh-check: no deploy-ssh configuration at ...` | Check the `deploy_ssh` option, run `./fleet.sh up`, and restart the runner |
| The target works but the bastion fails | Add the bastion `Host` block with `UserKnownHostsFile ~/.ssh/deploy.d/known_hosts` and `StrictHostKeyChecking yes` |
| Host changes have no effect | Restart the runner; staging happens only at boot |

More entries: [Troubleshooting](/operations/troubleshooting).

## Security

The deploy material follows the same trust model as the baked `~/.ssh/id_rsa`:

- **Keys are readable by every job of the organization's runner.** Do not mix tenants in one fleet,
  and use [private repositories only](/architecture/security).
- **Never commit keys.** `deploy-ssh/` is gitignored and excluded from Docker build contexts, and
  only a subdirectory of `deploy-ssh/` can be mounted.
- **Least privilege:** give a deploy key only the access its deployment needs.
- **Pin keys; treat `accept-new` as a fallback.** Pinned keys protect deploy sessions from
  redirection. Disabling verification is never produced by the tooling and is unsafe.
- **No secret output:** `deploy-ssh-check` prints public key data only; `known_hosts` is not secret.
