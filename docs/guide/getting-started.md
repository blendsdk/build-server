# Getting started

## Requirements

- A Linux host (Ubuntu-based recommended) with Docker and the Compose plugin
- `git`, `curl`, `jq`, `shellcheck`, and `htpasswd` (the bootstrap installs them when missing)
- A GitHub token that can manage runners for every organization in `orgs.conf` — see
  [GitHub token](/guide/github-token) for how to create one (classic PAT with `admin:org`, or a
  fine-grained token for a single organization)

## One-command install

On a fresh Ubuntu host:

```bash
curl -fsSL https://raw.githubusercontent.com/blendsdk/build-server/main/bootstrap.sh | bash -s --
```

The installer installs prerequisites, clones the repository to `$HOME/build-server`, asks for the
GitHub token and a registry password (or reads them from the environment), writes `.env`, generates
a deploy SSH key, creates empty credential placeholders, writes the registry htpasswd, builds the
runner image, and starts the fleet.

Useful flags and variables:

| Flag / variable | Effect |
| --- | --- |
| `--no-start` | Configure everything but do not build or start |
| `--non-interactive` | Never prompt; all values must come from the environment |
| `ACCESS_TOKEN` | GitHub token (required) |
| `REGISTRY_USER`, `REGISTRY_PASS` | Registry credentials (`ci` and a generated password by default) |
| `REGISTRY_HTTP_SECRET` | Registry signing secret (generated when absent) |
| `INSTALL_DIR` | Checkout location (default `$HOME/build-server`) |

Re-run the same command any time to update the checkout and fleet.

## Manual setup

```bash
git clone https://github.com/blendsdk/build-server.git
cd build-server

cp .env.example .env          # set ACCESS_TOKEN and REGISTRY_HTTP_SECRET
cp ~/.npmrc .npmrc            # credentials your builds need (optional)
cp ~/.yarnrc .yarnrc
cp ~/.bunfig.toml .bunfig.toml
cp ~/.docker/config.json config.json

mkdir -p registry/auth registry/data
docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$REGISTRY_USER" "$REGISTRY_PASS" \
  > registry/auth/registry.password

./fleet.sh build
./fleet.sh up
./fleet.sh status
```

## Try it without a server

```bash
bash examples/playground.sh              # sandbox with stub docker/curl
bash examples/playground.sh run generate
bash examples/playground.sh run status
```

## Next steps

- [Configure your organizations](/guide/organizations)
- [Learn the admin CLI](/guide/cli)
- [Understand the architecture](/architecture/overview)
