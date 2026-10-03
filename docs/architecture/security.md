# Security model

This is a **trusted CI** design. Read this page before exposing the fleet to any repository you do
not fully control.

## Trust boundaries

- Runner containers are **privileged** because they run a Docker daemon. A job that runs on a
  runner can control that daemon.
- The host Docker socket is never mounted, so a job cannot control the **host** daemon or other
  runners through it. The host kernel and devices are still shared.
- Runners are registered at **organization level** (`self-hosted` label). Any repository in the
  organization that targets `self-hosted` can reach them.

**Use private repositories only.** Fork pull requests in public repositories must never run on
self-hosted runners. If some repositories are public, keep a separate, isolated runner pool for
them — or use GitHub-hosted runners.

## Credentials

The runner image bakes host credentials so private dependencies work out of the box:

| File | Purpose |
| --- | --- |
| `~/.ssh/id_rsa` | Private git over SSH inside jobs |
| `.npmrc`, `.yarnrc`, `.bunfig.toml` | Private package registries |
| `config.json` | Private Docker registry authentication |
| `.env` | `ACCESS_TOKEN` and `REGISTRY_HTTP_SECRET` for the fleet |

Consequences:

- Any job on a runner can read these files. Do not mix tenants (clients) in one fleet unless they
  trust each other.
- Use least-privilege tokens: the `ACCESS_TOKEN` needs runner management for the organizations in
  `orgs.conf`, nothing more.
- Rotate credentials if an image or host is ever exposed, and keep `.env`/credential files
  `0600` and out of version control (they are gitignored).

## Registry

The default setup serves the private registry over plain HTTP on port 5000 with basic auth. Restrict
it to trusted networks or put TLS in front of it. It is not a vault.

## Recommendations

- Keep the fleet behind a firewall; runners only make outbound connections to GitHub.
- Pin the Actions runner version with `.runner-version` for reproducible builds.
- Run `./fleet.sh update <org>` between jobs; updates recreate containers and kill running jobs.
- Review workflow files that target `self-hosted` as code that runs on your infrastructure.

## Reporting

See [SECURITY.md](https://github.com/blendsdk/build-server/blob/main/SECURITY.md).
