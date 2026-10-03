# Build Server

[![ci](https://github.com/blendsdk/build-server/actions/workflows/ci.yml/badge.svg)](https://github.com/blendsdk/build-server/actions/workflows/ci.yml)
[![docs](https://github.com/blendsdk/build-server/actions/workflows/docs.yml/badge.svg)](https://github.com/blendsdk/build-server/actions/workflows/docs.yml)

Self-hosted **GitHub Actions runner fleet** with an **isolated Docker daemon inside every runner**
and a co-located private registry.

Self-hosted runners normally mount the host Docker socket, so bind mounts from a job
(`docker run -v "$PWD:/src"`, Compose bind mounts) resolve on the **host** filesystem and silently
mount empty directories. This project runs a private `dockerd` inside each runner container: paths
resolve where the job actually lives, `curl localhost:8080` works after a published port, and the
host Docker socket is never shared.

## Features

- **One admin CLI** — `fleet.sh` manages organizations, images, versions, and the lifecycle.
- **File-driven fleet** — `orgs.conf` is the single source of truth; Compose is generated.
- **Persistent, cache-warm runners** — one privileged container per organization.
- **Per-organization custom images** — add a `context=` folder with a Dockerfile.
- **Runner version updates** — `./fleet.sh update-runners` pins and deploys the latest release.
- **One-command install** — `bootstrap.sh` sets up a fresh Ubuntu host.

## Quick start

On a fresh Ubuntu host:

```bash
curl -fsSL https://raw.githubusercontent.com/blendsdk/build-server/main/bootstrap.sh | bash -s --
```

The installer asks for your GitHub token and the organizations to serve (each verified against
GitHub), builds the runner image plus any custom-context images, and starts the fleet. Add `--ssh`
to clone with your existing SSH key, or `--generate-ssh-key` to create and register a new one. Or
manually:

```bash
git clone https://github.com/blendsdk/build-server.git
cd build-server
cp .env.example .env          # set ACCESS_TOKEN (see the token guide) and REGISTRY_HTTP_SECRET
./fleet.sh build              # build the runner image
./fleet.sh up                 # start the registry and one runner per organization
./fleet.sh status
```

Want to try it without Docker or GitHub? `bash examples/playground.sh` runs the whole CLI against
stubbed commands.

## Documentation

Full documentation lives at **https://blendsdk.github.io/build-server/** — start with the
[getting started guide](https://blendsdk.github.io/build-server/guide/getting-started), create a
[GitHub token](https://blendsdk.github.io/build-server/guide/github-token), then read the
[architecture overview](https://blendsdk.github.io/build-server/architecture/overview).

## Security

Use these runners with **private repositories only**; jobs are trusted and privileged by design.
Read [SECURITY.md](SECURITY.md) and the
[security notes](https://blendsdk.github.io/build-server/architecture/security) before deploying.

## License

[MIT](LICENSE). Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
