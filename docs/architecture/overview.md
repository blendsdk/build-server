# Architecture overview

```
Host
├── registry (:5000, htpasswd)        docker-compose.yml (static base)
├── acmetools_1   ─┐
├── globex_1       │  privileged runner containers
├── initech_1      │  (one per organization)
└── contoso_1     ─┘        docker-compose.generated.yml
      │
      ├── dockerd          private daemon inside the container
      ├── actions-runner   runs as the unprivileged "docker" user
      └── job containers   created by the private daemon
```

## Components

| Component | Role |
| --- | --- |
| `bootstrap.sh` | Prepares a fresh host: prerequisites, temporary fetch, runtime files, secrets, keys, htpasswd, build, start |
| `orgs.conf` | Organization registry: names, GitHub URLs, custom-image contexts, build-temp flag |
| `fleet.sh` | Renders Compose from `orgs.conf` and runs builds, updates, and lifecycle commands |
| `docker-compose.yml` | Static base with the private registry |
| `docker-compose.generated.yml` | Generated runner services (gitignored) |
| `Dockerfile` | Runner image: Ubuntu 24.04, inner Docker engine, Actions runner, Node via nvm |
| `entrypoint.sh` | Starts `dockerd`, runs the runner as `docker`, stops the daemon on exit |
| `start.sh` | Registers the runner (with `--replace`), runs it, deregisters on shutdown |
| `work_queue` | Best-effort lock helper for build steps |

## Why an inner Docker daemon

Mounting the host Docker socket makes the **host** daemon resolve job paths. A job that runs
`docker run -v "$PWD:/src"` mounts a directory that exists only inside the runner, so the host
daemon creates an empty host directory instead. The same applies to Compose bind mounts and any
tool that computes absolute paths.

Each runner therefore starts its own `dockerd`:

- paths resolve in the runner's own filesystem;
- ports published by a job are reachable from that job via `localhost`;
- the host daemon and socket stay untouched;
- image layers and build caches live per runner and survive between jobs (runners are persistent).

At boot the entrypoint verifies the daemon can actually mount a container filesystem; on hosts
that forbid nested overlay mounts it restarts with the `vfs` storage driver and logs a warning
(pin `DOCKERD_STORAGE_DRIVER` to skip detection).

Trade-offs: runners are privileged, and each keeps its own image cache and consumes memory/disk
even while idle.

## Lifecycle

1. `entrypoint.sh` starts `dockerd` and waits for it.
2. It runs `start.sh` as the `docker` user.
3. `start.sh` fetches a registration token and registers with `--replace`.
4. The runner picks up jobs. `run.sh` is supervised by the entrypoint, which forwards signals.
5. On SIGTERM the runner deregisters; the entrypoint stops the daemon as root.
6. `restart: unless-stopped` brings the container back after a crash or reboot.

## Compose layout

`fleet.sh` never edits YAML by hand: it renders one service per organization into
`docker-compose.generated.yml` and merges it with the static registry base. `generate` is
idempotent and writes atomically.

## Next

- [Path resolution](/architecture/path-resolution)
- [Security model](/architecture/security)
