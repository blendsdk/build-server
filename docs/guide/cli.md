# Admin CLI

`fleet.sh` is the only administrative entry point. It changes into the repository root, loads
`.env` when present, and regenerates the Compose model before every composition command.

| Command | What it does |
| --- | --- |
| `./fleet.sh generate` | Renders `docker-compose.generated.yml` from `orgs.conf` |
| `./fleet.sh build [org]` | Builds the default `runner-image`, or one org's custom image |
| `./fleet.sh up` | Starts the registry and every runner (`up -d`) |
| `./fleet.sh down` | Stops and removes the fleet including orphan containers, removes this installation's runner registrations from GitHub, then removes unused fleet images and the build cache |
| `./fleet.sh stop` / `start` | Pauses and resumes containers without removing them |
| `./fleet.sh restart` | Recreates the fleet; removes containers of deleted organizations |
| `./fleet.sh update <org>` | Rebuilds one org's image and recreates only that runner |
| `./fleet.sh update-runners` | Rebuilds every image with the latest Actions runner version |
| `./fleet.sh clean [--yes]` | Removes this installation's unused images, containers, networks, and volumes, plus the host build cache |
| `./fleet.sh upgrade-all [--yes]` | Fetches the latest Actions runner, stops the fleet, cleans unused resources, rebuilds every image, and restarts |
| `./fleet.sh status` | Prints organizations, services, images, container state, and the pinned version |

## How the files fit together

- `orgs.conf` → `docker-compose.generated.yml` (gitignored) via `generate`.
- `docker-compose.yml` is the static base and holds only the private registry.
- Every command that touches containers runs with both files:
  `docker compose -f docker-compose.yml -f docker-compose.generated.yml …`.

## Build staging

`build` never leaves credentials in your repository:

- The default build stages only `~/.ssh` at the repository root and removes it afterwards.
- A custom-context build copies the context into `.fleet-build/<slug>/`, stages `~/.ssh` and your
  credential files there with `0600`/`0700` modes, builds, and removes the directory — on success
  and on failure.
- A SIGKILL can leave staging behind; the next `build`, `clean`, `down`, or `upgrade-all` clears
  it before staging again.

## Version pinning

The version used for builds is, in order: `.runner-version`, then the Dockerfile `ARG
RUNNER_VERSION`. `update-runners` writes `.runner-version` only after every build succeeds.

## Images are local-only

Runner images (`runner-image`, `runner-image-<slug>`) are built locally and generated services
declare `pull_policy: never`, so Compose never tries to pull them from a registry. Every image
carries the `com.build-server.fleet` label with the Compose project name as its value, so cleanup
removes only this installation's images. `up` and `restart` check the images first and stop with a
precise message instead of a registry error:

```
image 'runner-image-initech' is missing; run './fleet.sh build Initech'
```

Build the default image once (`./fleet.sh build`) and each custom-context image after adding a
`context=` to `orgs.conf` (`./fleet.sh build <org>`). `update-runners` builds them all.

`down` and `clean` remove the runner images when no container uses them, so run `./fleet.sh build`
(or `./fleet.sh upgrade-all`) after a `down` before `up` starts the fleet again. `restart` keeps
the images and the build cache, because it only recreates containers.

## Operational notes

- `update <org>` and `update-runners` recreate containers and kill any job running on the affected
  runners. Run them between jobs.
- `down` removes the runner registrations for the configured organizations through the GitHub API,
  so the organizations do not list offline runners afterwards. `up` registers them again. Without
  `ACCESS_TOKEN`, `down` warns and keeps the registrations.
- Admin commands are not designed for concurrent invocation.
- `status` and `generate` are read-mostly; the playground exercises all of them safely.
