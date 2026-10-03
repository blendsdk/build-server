# Admin CLI

`fleet.sh` is the only administrative entry point. It changes into the repository root, loads
`.env` when present, and regenerates the Compose model before every composition command.

| Command | What it does |
| --- | --- |
| `./fleet.sh generate` | Renders `docker-compose.generated.yml` from `orgs.conf` |
| `./fleet.sh build [org]` | Builds the default `runner-image`, or one org's custom image |
| `./fleet.sh up` | Starts the registry and every runner (`up -d`) |
| `./fleet.sh down` | Stops and removes the fleet, including orphan containers |
| `./fleet.sh stop` / `start` | Pauses and resumes containers without removing them |
| `./fleet.sh restart` | Recreates the fleet; removes containers of deleted organizations |
| `./fleet.sh update <org>` | Rebuilds one org's image and recreates only that runner |
| `./fleet.sh update-runners` | Rebuilds every image with the latest Actions runner version |
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
- A SIGKILL can leave staging behind; remove `.fleet-build/<slug>/` or `./ssh` before rebuilding.

## Version pinning

The version used for builds is, in order: `.runner-version`, then the Dockerfile `ARG
RUNNER_VERSION`. `update-runners` writes `.runner-version` only after every build succeeds.

## Operational notes

- `update <org>` and `update-runners` recreate containers and kill any job running on the affected
  runners. Run them between jobs.
- Admin commands are not designed for concurrent invocation.
- `status` and `generate` are read-mostly; the playground exercises all of them safely.
