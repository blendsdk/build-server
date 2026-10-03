# Files and variables

## File map

`bootstrap.sh` installs only the runtime files into the install directory. `test/`, `docs/`,
`codeops/`, and the other development material exist only in a development checkout.

| Path | Role |
| --- | --- |
| `bootstrap.sh` | Fresh-host installer (also the update entry point) |
| `orgs.conf` | Organization registry (source of truth) |
| `fleet.sh` | Admin CLI |
| `docker-compose.yml` | Static base: the private registry |
| `docker-compose.generated.yml` | Generated runner services (gitignored) |
| `.runner-version` | Pinned Actions runner version (gitignored) |
| `.build-server-version` | Installed revision recorded by `bootstrap.sh` |
| `.build-server-manifest` | Files installed by `bootstrap.sh`, used to clean up renames |
| `.fleet-build/` | Temporary build staging (gitignored) |
| `Dockerfile` | Runner image |
| `entrypoint.sh` | Inner daemon startup and runner supervision |
| `start.sh` | Runner registration and lifecycle |
| `work_queue` | Best-effort lock helper |
| `.env` | Host secrets: `ACCESS_TOKEN`, `REGISTRY_HTTP_SECRET` |
| `.npmrc`, `.yarnrc`, `.bunfig.toml`, `config.json` | Host credentials baked into the image |
| `ssh/` | Staged by `fleet.sh build` from `~/.ssh` |
| `examples/` | Offline playground with stub `docker`/`curl` (development only) |
| `test/` | Specification and implementation tests, `smoke-workflow.yml`, `verify.sh` (development only) |
| `docs/` | This VitePress site (development only) |

## Environment variables

| Variable | Used by | Meaning |
| --- | --- | --- |
| `ACCESS_TOKEN` | bootstrap, start.sh, update-runners | GitHub token with runner admin for the configured organizations — see [GitHub token](/guide/github-token) |
| `REGISTRY_USER` / `REGISTRY_PASS` | bootstrap, htpasswd | Registry credentials |
| `REGISTRY_HTTP_SECRET` | registry service | Registry signing secret |
| `REGISTRY_PORT` | registry service | Host port for the registry (default 5000); runners use `registry:5000` inside the fleet |
| `REGISTRY_ADDR` | generated runner services | Registry address inside the fleet (default `registry:5000`) — see [Publishing images](/guide/publishing) |
| `REGISTRY_USER`, `REGISTRY_PASS` | generated runner services | Registry credentials injected for job pushes (from `.env`) |
| `COMPOSE_PROJECT_NAME` | fleet.sh, `docker compose` | Container name prefix for this installation (default: install user) |
| `INSECURE_REGISTRIES` | inner Docker daemon | Plain-HTTP registries (default `registry:5000`; empty disables) |
| `DOCKERD_STORAGE_DRIVER` | inner Docker daemon | Optional storage-driver override (e.g. `vfs`); empty means detect and fall back automatically |
| `RUNNER_EMAIL_DOMAIN` | start.sh | Domain for the runner's git identity email (default `users.noreply.github.com`) |
| `INSTALL_DIR`, `REPO_URL`, `BRANCH` | bootstrap | Install location and fetch source |
| `GIT_AUTH`, `SSH_KEY`, `REPO_SSH_URL` | bootstrap | Fetch auth mode (`token`/`ssh`), key path, and explicit SSH URL — see [Getting started](/guide/getting-started#repository-access) |
| `ORGS` | bootstrap | Space- or comma-separated organizations; validated before `orgs.conf` is written |
| `ORGANIZATION`, `GITHUB_URL`, `GITHUB_API_URL` | start.sh | Per-runner registration scope (set by the generator) |

## Generated service environment

Each generated runner service receives:

- `ORGANIZATION` — the organization name
- `ACCESS_TOKEN` — from `.env`
- `GITHUB_URL` — the web URL used by `config.sh`
- `GITHUB_API_URL` — the API base used for the registration token

## Exit codes

`fleet.sh` and `bootstrap.sh` exit non-zero on validation failures, API failures, and failed
builds. `fleet.sh status` and `generate` exit zero on success.
