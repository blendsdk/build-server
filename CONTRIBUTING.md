# Contributing

Thanks for considering a contribution. This project is Bash + Docker Compose; keep changes small
and verifiable.

## Setup

```bash
git clone https://github.com/blendsdk/build-server.git
cd build-server
bash examples/playground.sh        # optional: offline CLI playground
```

Requirements for development: Docker with the Compose plugin, `jq`, `shellcheck`, and Node 22
only if you work on the documentation site.

## Before you open a pull request

```bash
bash test/verify.sh                # shellcheck + all spec/impl tests + tree checks
npm ci && npm run docs:build       # only if you changed docs/
```

- Write or update a spec test (`test/*.spec.test.sh`) before changing behavior; a failing spec test
  means the implementation is wrong, never the test.
- Keep shell scripts under `set -euo pipefail` and shellcheck-clean.
- Never commit secrets. `.env`, credentials, `ssh/`, and generated files are gitignored; check
  `git status` before committing.
- Update the documentation under `docs/` when behavior, commands, or the configuration format
  change.

## Commit style

Conventional Commits with a small scope, for example:

```
feat(fleet): add a per-org build timeout
fix(start): quote the registration token
docs(guide): document RUNNER_EMAIL_DOMAIN
```

## Reviews

Pull requests run `bash test/verify.sh` plus a docs build on GitHub-hosted runners. Keep the diff
focused; unrelated cleanups belong in a separate pull request.

## Security

Do not open a public issue for a security problem — see [SECURITY.md](SECURITY.md).
