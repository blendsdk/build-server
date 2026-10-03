# Task T-04: Publishing images from jobs to the co-located registry

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 6/6 tasks (100%)

## Objective

Let a workflow running inside a runner container build and push images to the co-located private
registry with plain `docker build`/`docker push`, without host-side configuration.

**Smallest viable design:** the inner daemon is started with
`--insecure-registry registry:5000` (the registry is plain HTTP; non-localhost registries need this
or TLS); generated runner services receive `REGISTRY_ADDR`, `REGISTRY_USER`, `REGISTRY_PASS`, and
`INSECURE_REGISTRIES`; `start.sh` logs the inner daemon in once at boot so jobs can push
immediately; `bootstrap.sh` records the registry credentials in `.env`; all values are
overridable. No new dependencies.

## Tasks

- [x] T-04.1 Spec tests: entrypoint passes insecure-registry flags; start.sh auto-login; compose injects registry env ✅ (completed: 2026-10-03 14:56)
- [x] T-04.2 Bootstraps records REGISTRY_USER/REGISTRY_PASS (and regenerates htpasswd for an explicit password) ✅ (completed: 2026-10-03 14:56)
- [x] T-04.3 Red phase ✅ (completed: 2026-10-03 14:57)
- [x] T-04.4 Implement in `entrypoint.sh`, `start.sh`, `fleet.sh`, `bootstrap.sh`, `.env.example` ✅ (completed: 2026-10-03 15:00)
- [x] T-04.5 Green phase plus docs: "Publishing images from jobs" page, sidebar, reference, security, FAQ ✅ (completed: 2026-10-03 15:03)
- [x] T-04.6 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 15:03)

**Verify**: `shellcheck -S style entrypoint.sh start.sh fleet.sh bootstrap.sh test/*.sh && bash test/verify.sh && npm run docs:build`
