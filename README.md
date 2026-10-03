# build-server

Self-hosted GitHub Actions runner fleet with a co-located private Docker registry. Each runner
container runs its **own Docker daemon**, so Docker commands issued by jobs resolve file paths
inside the runner container instead of on the host.

The fleet is driven by `orgs.conf` and managed with `./fleet.sh`.

## How it works

- `orgs.conf` lists the organizations; `./fleet.sh generate` renders one privileged runner service
  per organization into `docker-compose.generated.yml`.
- `docker-compose.yml` is the static base and contains only the private registry.
- Each runner starts a private `dockerd` (`entrypoint.sh`) and then runs the GitHub Actions runner
  as the unprivileged `docker` user.
- Jobs talk to that private daemon. `docker run -v "$PWD:/src"`, `docker compose` bind mounts, and
  `docker run -p 8080:80` followed by `curl localhost:8080` all behave as on a normal machine.
- The host Docker socket is **never** mounted, and runners do not use the host network namespace.
- Runners are persistent (not ephemeral): a container registers once with `--replace`, keeps its
  local image cache between jobs, and deregisters on shutdown.

## Files

| Path | Purpose |
| ---- | ------- |
| `orgs.conf` | Organization registry: `url=` (GitHub Enterprise), `context=` (custom image), `build_temp=1` |
| `./fleet.sh` | Admin CLI: generate, build, up/down/stop/start/restart, update, update-runners, status |
| `docker-compose.yml` | Static base: the private registry |
| `docker-compose.generated.yml` | Generated runner services (gitignored; never edit by hand) |
| `.runner-version` | Pinned Actions runner version written by `update-runners` (gitignored) |
| `Dockerfile` | Runner image: Ubuntu 24.04, inner Docker engine, Actions runner, Node via nvm |
| `entrypoint.sh` | Starts the private daemon, supervises the runner, stops the daemon |
| `start.sh` | Registers the runner, runs it, deregisters on SIGINT/SIGTERM |
| `work_queue` | Best-effort lock utility for build steps |
| `test/verify.sh` | Lint and test everything; run this before committing |
| `test/smoke-workflow.yml` | Manual end-to-end checks for a deployed runner |
| `examples/` | Offline playground and a non-production smoke-test recipe |

## Commands

```bash
./fleet.sh generate                  # render docker-compose.generated.yml from orgs.conf
./fleet.sh build [org]               # build the default image, or one org's custom context
./fleet.sh up | down | stop | start | restart
./fleet.sh update <org>              # rebuild one org's image, recreate only that runner
./fleet.sh update-runners            # newest Actions runner version; rebuild all; recreate fleet
./fleet.sh status                    # organizations, services, images, container state, version
```

## Try it without Docker or GitHub

```bash
bash examples/playground.sh              # sandbox with stub docker/curl under /tmp/fleet-playground
bash examples/playground.sh run generate # render the example fleet
bash examples/playground.sh run status   # fleet table + pinned version
bash examples/playground.sh trace        # every stub call that was made
```

See `examples/README.md` for the full command list and a manual smoke-test recipe for a temporary,
non-production organization.

## Fresh server install

On a new Ubuntu machine:

```bash
curl -fsSL https://raw.githubusercontent.com/TrueSoftwareNL/build-server/v1-rebuild/bootstrap.sh | bash -s --
```

The installer installs Docker, git, curl, jq, shellcheck, and htpasswd (using sudo), clones the
repository to `$HOME/build-server` (override with `INSTALL_DIR`), asks for `ACCESS_TOKEN` and a
registry password (or reads them from the environment), writes `.env`, generates a deploy SSH key,
creates empty credential placeholders, writes the registry htpasswd, then builds the runner image
and starts the fleet. Re-run the same command any time to update the checkout and fleet.

- Private repository? Fetch the script with a token:
  `curl -fsSL -H "Authorization: token $ACCESS_TOKEN" <raw url> | bash -s --`
- Unattended: `ACCESS_TOKEN=... REGISTRY_PASS=... curl ... | bash -s -- --non-interactive`
- Configure only, no start: add `--no-start`.
- Afterwards: `cd ~/build-server && ./fleet.sh status`, and edit `orgs.conf` for your organizations.

## Setup

Host requirements: Linux with Docker and the Compose plugin, plus `curl`, `jq`, and `shellcheck`
for `update-runners` and the verification command.

1. Create the host configuration and credential files (all gitignored):

   ```bash
   cp .env.example .env          # fill in ACCESS_TOKEN and REGISTRY_HTTP_SECRET
   cp ~/.npmrc .npmrc            # private package registries used by your builds
   cp ~/.yarnrc .yarnrc
   cp ~/.bunfig.toml .bunfig.toml
   cp ~/.docker/config.json config.json
   ```

2. Choose a registry user and password and prepare the htpasswd file (the registry will not start
   without it). Jobs authenticate to the registry with the same pair:

   ```bash
   export REGISTRY_USER=ci
   export REGISTRY_PASS='change-me-to-a-strong-password'
   mkdir -p registry/auth registry/data
   docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$REGISTRY_USER" "$REGISTRY_PASS" \
     > registry/auth/registry.password
   ```

3. Build the runner image and start the fleet:

   ```bash
   ./fleet.sh build
   ./fleet.sh up
   ```

4. Verify: `bash test/verify.sh`.

## Day-to-day

- Add or remove an organization: edit `orgs.conf`, then `./fleet.sh up`. Use `./fleet.sh restart` to
  also remove the containers of deleted organizations.
- Give an organization a custom image: add `context=orgs/<name>` (a folder containing a
  `Dockerfile`) and run `./fleet.sh build <name>`.
- Update one runner without touching the rest: `./fleet.sh update <name>`.
- Update the Actions runner everywhere: `./fleet.sh update-runners` (writes `.runner-version`).
- Inspect the fleet: `./fleet.sh status`; logs: `docker compose -f docker-compose.yml -f
  docker-compose.generated.yml logs -f <service>`.

## The one path rule

A path handed to Docker must exist **inside the runner container**. The checked-out workspace and
container-local `/tmp` do. Host paths do not, unless you bind them into the runner container with
an extra volume in the generated compose file.

## Operational notes

- `./fleet.sh update <org>` and `./fleet.sh update-runners` recreate containers and therefore kill any
  job running on the affected runner(s). Run them between jobs.
- Admin commands are not designed to run concurrently: overlapping runs can delete each other's
  staged build files.
- The slug-derived service names (`<org-slug>_1`) differ from the old hand-written names; one
  `./fleet.sh restart` applies the new names.
- A build killed with SIGKILL can leave `.fleet-build/<slug>/` or `./ssh` behind. Remove the
  leftover directory before rebuilding.
- `update-runners` resolves the version from github.com. A GitHub Enterprise organization may
  require a compatible version: write it to `.runner-version` yourself and run `./fleet.sh build`.

## Security notes

- Use these runners with **private repositories only**. Any workflow that runs on a self-hosted
  runner can read the credentials baked into the image.
- Runner containers are privileged because they run a Docker daemon. Treat every job as trusted.
- The registry serves plain HTTP on port 5000 with basic auth and should be reachable only from
  trusted networks.

## Known follow-ups

- Rotate the credentials exposed in the legacy system and move npm/SSH/registry credentials out of
  the image in favor of runtime mounts.
- TLS for the registry; resource limits and log rotation for the fleet.
- Make `work_queue` atomic (stale-lock recovery) or replace it with a real queue.
- Pin Node instead of installing the floating LTS at startup.
- Automate rebuilding the image when GitHub releases a new runner version.
- Handle registration-token expiry in the shutdown cleanup.

## Verify

```bash
bash test/verify.sh     # shellcheck + all tests + removed-script reference check
```
