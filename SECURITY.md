# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's
[security advisories](https://github.com/blendsdk/build-server/security/advisories/new) instead of a
public issue. Include the affected file or command, a reproduction, and the impact you see.

## Design expectations

This project runs a **privileged Docker daemon inside each runner container** and bakes host
credentials into the runner image. Deploy it accordingly:

- Use self-hosted runners with **private repositories only**. Workflows from untrusted
  contributors must never reach them.
- Treat every CI job as trusted: a job can control its runner's Docker daemon and read the
  credentials baked into the image.
- Keep the private registry on trusted networks; the default setup serves it over plain HTTP with
  basic auth.
- Treat `.env`, `.npmrc`, `.yarnrc`, `.bunfig.toml`, `config.json`, `ssh/`, and the generated files
  as host-local secrets. They are gitignored — never commit or containerize them into public images.

Reports that amount to "a privileged CI job can control the host" are accepted by design; the
maintainers focus on accidental exposure, injection through configuration, and unsafe defaults.
