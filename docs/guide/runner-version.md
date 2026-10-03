# Runner versions

The runner image pins the GitHub Actions runner version at build time.

## Update everything

```bash
./fleet.sh update-runners
```

This command:

1. queries `https://api.github.com/repos/actions/runner/releases/latest` (with `ACCESS_TOKEN` when
   set) and surfaces API errors verbatim;
2. builds the **default** image first, then every custom context, passing
   `--build-arg RUNNER_VERSION=<version>`;
3. writes `.runner-version` only after every build succeeds;
4. recreates the fleet with `docker compose up -d`.

## Pin a specific version

Write it to `.runner-version` and rebuild:

```bash
echo 2.337.0 > .runner-version
./fleet.sh build
./fleet.sh update <org>     # or: ./fleet.sh restart
```

Builds use `.runner-version` first and fall back to the Dockerfile `ARG RUNNER_VERSION`.

## GitHub Enterprise

The release lookup is always github.com; GHES instances can require a compatible runner build.
Check the version your GHES instance supports and write it to `.runner-version` before building;
avoid `update-runners` on a GHES-only fleet unless that version matches.

## Why pin at all

Rebuilding an unpinned image at different times silently changes tool behavior between jobs.
The pin makes rebuilds reproducible; `update-runners` is the deliberate way to move forward.
