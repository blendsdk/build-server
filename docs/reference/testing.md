# Testing

## The verify command

```bash
bash test/verify.sh
```

It runs, in order:

1. `shellcheck -S style` over every shell file (including `examples/playground.sh`);
2. the specification and implementation tests;
3. a check that no shipped file references removed scripts.

CI runs the same command on GitHub-hosted runners.

## Test layout

| File | Covers |
| --- | --- |
| `test/orgs.spec.test.sh` | Configuration parsing, validation, and Compose generation |
| `test/compose.spec.test.sh` | The generated Compose model (privileges, sockets, secrets, mapping) |
| `test/start.spec.test.sh` | Runner registration, URLs, email domain, shutdown ordering |
| `test/dockerfile.spec.test.sh` | Image package availability and required contents |
| `test/fleet.spec.test.sh` | CLI build/update/lifecycle behavior with stubbed externals |
| `test/fleet.impl.test.sh` | Internal behavior: atomic writes, staging modes, version precedence |
| `test/bootstrap.spec.test.sh` | Fresh-host installer with stubbed commands |
| `test/work_queue.spec.test.sh` | The lock helper |
| `test/entrypoint.spec.test.sh` / `entrypoint.impl.test.sh` | Inner daemon startup and supervision |

Rules: specification tests (`*.spec.test.sh`) describe documented behavior and are written before
implementation; a failing spec test means the implementation is wrong, never the test.

## Offline playground

No Docker or GitHub required:

```bash
bash examples/playground.sh
bash examples/playground.sh run generate
bash examples/playground.sh run update-runners
bash examples/playground.sh trace
```

## Documentation site

```bash
npm ci
npm run docs:build     # output in docs/.vitepress/dist
npm run docs:dev       # live preview
```

## Manual end-to-end

`test/smoke-workflow.yml` is the smoke suite for a deployed fleet. Copy it to
`.github/workflows/smoke.yml` in any repository served by the fleet and dispatch it from the
Actions tab — run it after a fleet upgrade and before a release.

It verifies, in order:

1. an environment report (runner, registry address, Docker version);
2. a public image is pulled and run;
3. the checked-out workspace is visible in job containers and writable from both sides;
4. a container published by the inner daemon is reachable from the job at `localhost`;
5. the registry rejects anonymous access and accepts the configured credentials;
6. a custom image is built, pushed, pulled back, and run with run-specific content;
7. host isolation (optional): dispatch with the `host_check` input enabled to pause while you
   run `docker ps` on the build host — the job's sleeper container must not appear.

Results are written to the step summary and uploaded as the `smoke-results` artifact.
