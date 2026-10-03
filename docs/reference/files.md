# Files and variables

## File map

| Path | Role |
| --- | --- |
| `bootstrap.sh` | Fresh-host installer |
| `orgs.conf` | Organization registry (source of truth) |
| `fleet.sh` | Admin CLI |
| `docker-compose.yml` | Static base: the private registry |
| `docker-compose.generated.yml` | Generated runner services (gitignored) |
| `.runner-version` | Pinned Actions runner version (gitignored) |
| `.fleet-build/` | Temporary build staging (gitignored) |
| `Dockerfile` | Runner image |
| `entrypoint.sh` | Inner daemon startup and runner supervision |
| `start.sh` | Runner registration and lifecycle |
| `work_queue` | Best-effort lock helper |
| `.env` | Host secrets: `ACCESS_TOKEN`, `REGISTRY_HTTP_SECRET` |
| `.npmrc`, `.yarnrc`, `.bunfig.toml`, `config.json` | Host credentials baked into the image |
| `ssh/` | Staged by `fleet.sh build` from `~/.ssh` |
| `examples/` | Offline playground and smoke-test recipe |
| `test/` | Specification and implementation tests, `verify.sh` |
| `docs/` | This VitePress site |

## Environment variables

| Variable | Used by | Meaning |
| --- | --- | --- |
| `ACCESS_TOKEN` | bootstrap, start.sh, update-runners | GitHub token with runner admin for the configured organizations — see [GitHub token](/guide/github-token) |
| `REGISTRY_USER` / `REGISTRY_PASS` | bootstrap, htpasswd | Registry credentials |
| `REGISTRY_HTTP_SECRET` | registry service | Registry signing secret |
| `REGISTRY_PORT` | registry service | Host port for the registry (default 5000); runners use `registry:5000` inside the fleet |
| `RUNNER_EMAIL_DOMAIN` | start.sh | Domain for the runner's git identity email (default `users.noreply.github.com`) |
| `INSTALL_DIR`, `REPO_URL`, `BRANCH` | bootstrap | Checkout location and source |
| `GIT_AUTH`, `SSH_KEY`, `REPO_SSH_URL` | bootstrap | Checkout auth mode (`token`/`ssh`), key path, and explicit SSH URL — see [Getting started](/guide/getting-started#repository-access) |
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
