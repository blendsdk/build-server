# Path resolution

The reason this project exists.

## The problem

A typical self-hosted runner mounts the host Docker socket:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

Docker commands from a job are then executed by the **host** daemon. When the job runs:

```bash
docker run --rm -v "$PWD:/src" alpine ls /src
```

`$PWD` is a path inside the runner container, but the host daemon resolves it on the **host**
filesystem, where it either does not exist (Docker creates an empty directory) or contains
something else entirely. The build silently sees no files.

The same happens with Compose relative bind mounts and any tool that passes absolute paths to
Docker.

## The fix

Each runner container runs its own `dockerd`. Job commands talk to that daemon, which lives in the
same filesystem namespace as the job. `$PWD`, `/tmp`, and Compose relative paths all resolve where
the workspace actually is.

```
job process ──docker CLI──▶ runner's dockerd ──creates──▶ sibling container
        │                          │
        └──────── same filesystem ─┘
```

## What this gives you

| Action | Result |
| --- | --- |
| `docker run -v "$PWD:/src" …` | The workspace appears at `/src` |
| `docker compose up` with relative volumes | Bind mounts resolve correctly |
| `docker run -p 8080:80 nginx` then `curl localhost:8080` | Works — the job shares the daemon's network namespace |
| `docker ps` on the host | Does not show job containers |

## The one rule

A path handed to Docker must exist **inside the runner container**. The checked-out workspace and
container-local `/tmp` do by default. Host paths do not, unless you bind them into the runner
container with an additional volume in the generated Compose service (for example a host `.env`
file or a cache directory).
