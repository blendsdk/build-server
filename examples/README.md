# Examples

## Offline playground

Try the whole CLI without Docker, GitHub, or network — `playground.sh` builds a sandbox with stub
`docker`/`curl` commands that record what they were asked to do:

```bash
bash examples/playground.sh              # create the sandbox under /tmp/fleet-playground
bash examples/playground.sh run generate # render the example fleet
bash examples/playground.sh show         # inspect docker-compose.generated.yml
bash examples/playground.sh run build    # default image build (stubbed)
bash examples/playground.sh run build Initech   # custom-context staging (stubbed)
bash examples/playground.sh run update-runners  # version update flow (stubbed API -> v9.9.9)
bash examples/playground.sh run status   # fleet table + pinned version
bash examples/playground.sh trace        # every stub call, in order
bash examples/playground.sh reset        # start over
```

`examples/orgs.conf` demonstrates every option: a plain org, `build_temp=1`, a `context=` custom
image (`examples/runner-custom/Dockerfile`), and a GitHub Enterprise `url=`.

## Real runner smoke test (manual, non-production)

To exercise a real runner end to end, use a **temporary, non-production test organization** — never
the production organizations.

1. Point the registry and token at the test setup. Copy `.env.example` to `.env`, set
   `ACCESS_TOKEN` to a token that can manage that organization's runners, and set
   `REGISTRY_HTTP_SECRET`.
2. Make sure the host credential files exist in the repository root (`.npmrc`, `.yarnrc`,
   `.bunfig.toml`, `config.json`) and prepare `registry/auth/registry.password` (see the main
   README).
3. Back up the production configuration and switch to the test organization only:

   ```bash
   cp orgs.conf /tmp/orgs.conf.production
   printf 'TestOrg\n' > orgs.conf        # replace TestOrg with the temporary test org
   ```

4. Build and start just that runner (leaving the production registry out of the way):

   ```bash
   ./fleet.sh build
   ./fleet.sh generate
   docker compose -f docker-compose.yml -f docker-compose.generated.yml up -d testorg_1
   ./fleet.sh status
   docker compose -f docker-compose.yml -f docker-compose.generated.yml logs -f testorg_1
   ```

5. Dispatch `test/smoke-workflow.yml` (copy it to `.github/workflows/` of a repository in the test
   org) and watch the runner pick up the job.
6. Clean up and restore the production configuration:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.generated.yml down --remove-orphans
   mv /tmp/orgs.conf.production orgs.conf
   ./fleet.sh generate
   ```

> The test organization is temporary. Do not add it to the committed `orgs.conf`, tests, or any
> other shipped artifact.
