# Upgrades and changes

## Routine changes

| Change | Command |
| --- | --- |
| Apply `orgs.conf` edits (add orgs) | `./fleet.sh up` |
| Remove a deleted organization's container | `./fleet.sh restart` |
| Rebuild one organization's image | `./fleet.sh update <org>` |
| Update the Actions runner everywhere | `./fleet.sh update-runners` |
| Apply Dockerfile or fleet changes to a running fleet | `./fleet.sh upgrade-all` |
| Reclaim disk without changing the fleet | `./fleet.sh clean` |

`update <org>` recreates only that runner; `update-runners` and `restart` recreate the fleet. All
of them **kill running jobs** on the affected runners — schedule them between jobs.

## Updating the host project

Re-run the installer; it fetches a fresh temporary clone and installs the runtime files:

```bash
cd ~/build-server
bash bootstrap.sh --keep-orgs
```

Or use the one-liner from [Getting started](/guide/getting-started). `.env`, `orgs.conf`, registry
data, credentials, SSH material, and user context directories are preserved. The installed revision
is recorded in `.build-server-version` and shown by `./fleet.sh status`.

A production install contains only the runtime files. If the host still holds an older full
checkout, add `--slim` once to remove `.git` and the development files:

```bash
bash bootstrap.sh --keep-orgs --slim
```

## Full fleet upgrade

After the installer updated the host files (for example a Dockerfile fix), apply everything with
one command:

```bash
./fleet.sh upgrade-all
```

It fetches the latest Actions runner release, stops the fleet, removes this installation's unused
images and the host build cache, rebuilds the default and every custom image with the fetched
version, and starts the fleet again. `orgs.conf`, `.env`, credentials, SSH material, and the
registry data are never touched. The version is written to `.runner-version` only after every
build succeeds, and it is fetched before the teardown, so an API failure leaves the running fleet
unchanged.

The command asks for confirmation before the destructive part; use `--yes` in scripts. During the
upgrade, running jobs are killed. Use `./fleet.sh clean --yes` to reclaim disk without rebuilding
or restarting anything.

The build cache is shared by every Docker project on the host, so purging it also slows the next
build of other projects. Automatic cleanup runs after `down`, after successful builds, and in
`upgrade-all`; `restart` deliberately keeps images and cache because it only recreates containers.

## Rolling a runner version

```bash
./fleet.sh update-runners
./fleet.sh status
```

The version is written to `.runner-version` only after every image built successfully. If a build
fails, the pin is unchanged and the fleet keeps running the previous version.

## Container names

Container names are prefixed with the Compose project name (`COMPOSE_PROJECT_NAME` in `.env`; the
install user by default), and services are named after the organization slug (`acmetools`).
Compose derives each container name as `<project>-<service>-1`, so two installations on one Docker
host never collide.

Older versions used global names (`<slug>_runner_1` and the install directory for the registry).
`up`, `down`, `restart`, and `update` remove those leftovers automatically — they are matched by
their Compose project label — so the first start after an upgrade needs no manual cleanup.

## Backups

The only durable state on the host is:

- `.env`, credential files, and `ssh/` — back these up securely;
- `registry/data` — the private image registry (optional; rebuildable);
- `.runner-version`, `.build-server-version`, `.build-server-manifest` — trivial to recreate.

Runner containers themselves are disposable; their image caches rebuild on demand.
