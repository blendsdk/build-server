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
| `--token` | Clone over HTTPS using `ACCESS_TOKEN` (default) |
| `--ssh` | Clone over SSH using an existing key (`SSH_KEY`, default `~/.ssh/id_rsa`) |
| `--generate-ssh-key` | Generate the key when missing, install the public key on GitHub, then clone over SSH |
| `ACCESS_TOKEN` | GitHub token (required — also used for runner registration) |
| `REGISTRY_USER`, `REGISTRY_PASS` | Registry credentials (`ci` and a generated password by default) |
| `REGISTRY_HTTP_SECRET` | Registry signing secret (generated when absent) |
| `INSTALL_DIR` | Checkout location (default `$HOME/build-server`) |
| `GIT_AUTH` | `token` (default) or `ssh`; flags win over the variable |
| `SSH_KEY` | Key used for the checkout (default `~/.ssh/id_rsa`) |
| `REPO_SSH_URL` | Explicit SSH URL when it differs from the `REPO_URL` derivation |

Re-run the same command any time to update the checkout and fleet.

## Repository access

The private repository can be cloned with the token or with SSH:

```bash
# HTTPS + token (default)
curl -fsSL https://raw.githubusercontent.com/blendsdk/build-server/main/bootstrap.sh | bash -s --

# SSH with your existing key
curl -fsSL https://raw.githubusercontent.com/blendsdk/build-server/main/bootstrap.sh | bash -s -- --ssh

# SSH with a new key that the installer registers on GitHub
curl -fsSL https://raw.githubusercontent.com/blendsdk/build-server/main/bootstrap.sh | bash -s -- \
  --generate-ssh-key
```

Notes:

- `--ssh` uses `SSH_KEY` (default `~/.ssh/id_rsa`) and adds the host to `known_hosts`.
- `--generate-ssh-key` requires a token with the classic `write:public_key` scope (fine-grained:
  **Git SSH keys: Read and write**); without it the installer prints the public key and the manual
  step instead.
- The key lives in `~/.ssh`, which `./fleet.sh build` stages into the runner image so jobs can
  clone private repositories over SSH.
- `ACCESS_TOKEN` is required in every mode: it mints runner registration tokens.

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
