# Task T-05: Inner daemon storage fallback

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 5/5 tasks (100%)

## Objective

The E2E run on an external host failed with
`failed to mount /tmp/containerd-mount…: … err: invalid argument` — the inner daemon's default
overlay storage cannot run containers on hosts that forbid nested overlay mounts. The runner must
detect this at boot and fall back instead of failing every job.

**Smallest viable design:** after the daemon is ready, run a storage self-test with an empty
imported image: exit `127` means the mount worked (the command is simply missing) and `125` means
the mount failed. On failure, restart `dockerd` with `--storage-driver vfs` on a fresh data root.
An explicit `DOCKERD_STORAGE_DRIVER` skips detection. `DOCKER_DATA_ROOT` is overridable for tests.

## Tasks

- [x] T-05.1 Spec test: entrypoint falls back to vfs when the storage self-test fails ✅ (completed: 2026-10-03 15:18)
- [x] T-05.2 Red phase ✅ (completed: 2026-10-03 15:18)
- [x] T-05.3 Implement detection, fallback, and the pass-through env in `entrypoint.sh`, `fleet.sh`, `.env.example` ✅ (completed: 2026-10-03 15:22)
- [x] T-05.4 Green phase plus docs (troubleshooting, reference) ✅ (completed: 2026-10-03 15:25)
- [x] T-05.5 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 15:25)

**Verify**: `shellcheck -S style entrypoint.sh test/entrypoint.spec.test.sh test/entrypoint.impl.test.sh && bash test/entrypoint.spec.test.sh && bash test/entrypoint.impl.test.sh && bash test/verify.sh`
