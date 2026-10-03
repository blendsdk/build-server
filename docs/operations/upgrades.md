# Upgrades and changes

## Routine changes

| Change | Command |
| --- | --- |
| Apply `orgs.conf` edits (add orgs) | `./fleet.sh up` |
| Remove a deleted organization's container | `./fleet.sh restart` |
| Rebuild one organization's image | `./fleet.sh update <org>` |
| Update the Actions runner everywhere | `./fleet.sh update-runners` |
| Rebuild the default image after Dockerfile edits | `./fleet.sh build` then `./fleet.sh restart` |

`update <org>` recreates only that runner; `update-runners` and `restart` recreate the fleet. All
of them **kill running jobs** on the affected runners — schedule them between jobs.

## Updating the host project

```bash
cd ~/build-server
git pull
bash test/verify.sh
./fleet.sh build          # only when the Dockerfile changed
./fleet.sh restart
```

`bootstrap.sh` does the same update when re-run.

## Rolling a runner version

```bash
./fleet.sh update-runners
./fleet.sh status
```

The version is written to `.runner-version` only after every image built successfully. If a build
fails, the pin is unchanged and the fleet keeps running the previous version.

## Renamed services

The generated service names are slug-derived from the organization name. If you migrate from an
older hand-written fleet, run `./fleet.sh restart` once so containers with the old names are removed
as orphans.

## Backups

The only durable state on the host is:

- `.env`, credential files, and `ssh/` — back these up securely;
- `registry/data` — the private image registry (optional; rebuildable);
- `.runner-version` — trivial to recreate.

Runner containers themselves are disposable; their image caches rebuild on demand.
