# Troubleshooting

## A runner exits immediately

```bash
docker compose -f docker-compose.yml -f docker-compose.generated.yml logs -f <service>
```

Common causes:

| Log line | Cause | Fix |
| --- | --- | --- |
| `indicates a registration token` / token error | `ACCESS_TOKEN` missing, expired, or lacks runner admin for the org | Fix `.env`, re-run `./fleet.sh restart` |
| `Docker daemon failed to start` | The inner `dockerd` cannot start (host kernel/storage driver) | Check the printed daemon log; try `vfs` storage if nested overlay fails |
| `context ... has no Dockerfile` | Bad `context=` in `orgs.conf` | Fix the path; see [Organizations](/guide/organizations) |
| `already exists; remove the leftover staging directory` | A killed build left `.fleet-build/` or `./ssh` | `rm -rf .fleet-build ./ssh` and rebuild |
| `image 'runner-image-<slug>' is missing` or `pull access denied for runner-image-<slug>` | The custom-context image was never built; it is local-only and never pulled | `./fleet.sh build <org>` (or `./fleet.sh update-runners`), then `./fleet.sh up` |
| `Bind for 0.0.0.0:5000 failed: port is already allocated` | Another service on the host already uses the registry's host port | Set `REGISTRY_PORT=<free port>` in `.env` and rerun `./fleet.sh up`; a fresh `bootstrap.sh` install picks a free port automatically |
| `failed to mount .../containerd-mount…: ... invalid argument` | The host cannot nest the default overlay storage driver inside the runner container | The entrypoint detects this at boot and falls back to `vfs` with a warning (containers run, slower storage); pin `DOCKERD_STORAGE_DRIVER=vfs` in `.env` to skip detection, or investigate the host filesystem |

## Jobs cannot reach the registry

The default registry is plain HTTP on host port 5000. Ensure jobs use the same hostname/credentials
and that the host firewall allows the connection.

## A bind mount is empty

Only paths inside the runner container exist for the inner daemon. Check
[Path resolution](/architecture/path-resolution); host paths need an extra volume in the generated
service.

## `fleet.sh` says Docker is not accessible

After the installer adds you to the `docker` group, log out and back in, then run:

```bash
./fleet.sh build && ./fleet.sh up
```

## `generate` rejects my configuration

Errors name the file and line. Frequent cases: `url=` is not `https`, unknown key, duplicate
organization, duplicate/empty slug, missing `context` folder, empty file.

## Reset everything

```bash
./fleet.sh down
rm -rf .fleet-build ./ssh docker-compose.generated.yml
./fleet.sh up
```
