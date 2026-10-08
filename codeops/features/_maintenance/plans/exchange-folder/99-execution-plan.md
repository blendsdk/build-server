# Task T-15: Shared artifact exchange folder

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 0/4 tasks (0%)
> **Reasoning**: medium — user-facing fleet behavior; a world-writable host folder is mounted into privileged runner containers, so the mount and seeding rules must stay predictable
> **Expected changes** (scope: strict): `fleet.sh`, `test/fleet.spec.test.sh`, `.gitignore`, `docs/reference/files.md`, `docs/guide/organizations.md`, `docs/guide/cli.md`, and the plan/roadmap documents (`99-execution-plan.md`, `00-review-report.md`, `codeops/features/_maintenance/00-roadmap.md`, `codeops/00-roadmap.md`)
> **Lenses**: correctness + security (world-writable host folder mounted read-write into privileged containers)

## Objective

Give every organization a shared artifact exchange: the host folder `./exchange/<org-slug>/` is
bind-mounted read-write at `/srv/exchange` in that organization's runner, so jobs, nested job
containers, and the host operator can drop and read artifacts across the projects of one
organization. Commands that start runner containers create a missing folder with mode 0777;
existing folders are never modified, and teardown never deletes the data.

**Smallest viable design:** append one bind mount to every generated runner service in
`render_compose()` (the exchange mount is universal, so the `volumes:` header becomes
unconditional and the `volumes_started` bookkeeping disappears), seed missing folders from a new
`ensure_exchange_dirs()` called from the same six call sites as the deploy-folder seeding, and
ignore `/exchange/` in `.gitignore`. No `orgs.conf` option, no new command, no container changes.

## Pinned behavior

1. Every generated runner service mounts `- ./exchange/<slug>:/srv/exchange` read-write, alongside
   any `deploy_ssh` mount (`:ro`) and `/tmp:/build-temp`.
2. A missing `exchange/<slug>` is created by runner-starting commands (`up`, `start`, `restart`,
   `update`, `update-runners`, `upgrade-all`) with mode 0777 and one notice line:
   `fleet: created exchange/<slug> (shared artifact exchange, mode 0777)`.
3. An existing directory — including a symlink that resolves to a directory — is never modified:
   no chmod, no notice.
4. An entry at the path that is not a directory (regular file, dangling symlink) fails the command
   before any compose call with a clear message.
5. `generate`, `status`, `down`, `stop`, and `clean` never create the folder; `down`, `stop`, and
   `clean` never delete or modify it (it is operator data, not a compose volume).
6. The parent `exchange/` directory is created with the normal host umask (not world-writable).
7. Deploy-SSH behavior is unchanged.

### Specification test cases (in `test/fleet.spec.test.sh`, ST-62..ST-66)

1. ST-62: `generate` mounts `- ./exchange/<slug>:/srv/exchange` for every organization and keeps
   the existing `deploy_ssh` (`:ro`) and `build-temp` mounts.
2. ST-63: `up` creates `exchange/alpha` with mode 0777 and prints the exact notice; after removal,
   `start` recreates it with the same mode and notice.
3. ST-64: an existing folder is never modified (mode and contents survive `up`), and `down` and
   `clean --yes` preserve it.
4. ST-65: `generate`, `status`, `stop`, `down`, and `clean --yes` never create the folder.
5. ST-66: a file at `exchange/<slug>` fails the command with the clear message and no compose call.

## Tasks

- [ ] T-15.1 Add ST-62..ST-66 to `test/fleet.spec.test.sh` (and update the file's coverage comment)
- [ ] T-15.2 Run the fleet spec suite and record the red phase (the new cases fail; existing cases
  stay green)
- [ ] T-15.3 Implement: the exchange bind mount in `render_compose()`, `seed_exchange_folder()` +
  `ensure_exchange_dirs()` wired to the six runner-starting call sites, `/exchange/` in `.gitignore`
- [ ] T-15.4 Update the docs (`docs/reference/files.md`, `docs/guide/organizations.md`,
  `docs/guide/cli.md`) and run the full verification

**Verify**: `bash test/verify.sh`; because docs change, also `npm run docs:build`
