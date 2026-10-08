# Organizations

`orgs.conf` is the single source of truth for the fleet. Each line declares one organization:

```
# <name> [url=...] [context=...] [build_temp=1] [deploy_ssh=<path>]

AcmeTools
Globex build_temp=1
Initech context=examples/runner-custom
Contoso url=https://ghe.example.com/Contoso
# Contoso deploy_ssh=deploy-ssh/contoso
```

| Field | Rules |
| --- | --- |
| `<name>` | Required, unique, `[A-Za-z0-9._-]+` |
| `url=` | Optional GitHub or GitHub Enterprise base URL, `https://` only, default `https://github.com/<name>` |
| `context=` | Optional folder inside the repository containing a `Dockerfile` for a custom image |
| `build_temp=1` | Optional; mounts the host `/tmp` at `/build-temp` for this runner |
| `deploy_ssh=` | Optional folder holding deploy SSH material (`config`, `known_hosts`, `keys/`), relative to the repository and inside `deploy-ssh/` (for example `deploy-ssh/acmetools`); created with `keys/` when missing — see [Deploy over SSH](/guide/deploy-ssh) |

Blank lines and `#` comments are ignored. Unknown keys, malformed lines, duplicate names, duplicate
or empty slugs, and an empty file all fail `generate` with the offending line.

## Generated names

The service name is derived from the organization: lowercase and alphanumeric only. Container names
are prefixed with the Compose project name (`COMPOSE_PROJECT_NAME` in `.env`; the install user by
default), so several installations can share one Docker host.

| Organization | Service | Container | Hostname | Runner name |
| --- | --- | --- | --- | --- |
| `AcmeTools` | `acmetools` | `<project>-acmetools-1` | `acmetools_runner_1` | `AcmeTools_acmetools_runner_1` |
| `Initech` | `initech` | `<project>-initech-1` | `initech_runner_1` | `Initech_initech_runner_1` |

Be aware of slug collisions (`Foo.Bar` and `Foo-Bar` both become `foobar`); `generate` rejects
them.

## Shared exchange folder

Every organization gets a shared artifact folder: the host folder `exchange/<slug>/` is mounted
read-write at `/srv/exchange` in that organization's runner, so jobs and the host operator can
drop and read files that outlive a runner recreation. Nested job containers can mount it too:

```bash
docker run -v /srv/exchange:/exchange ...
```

`up`, `restart`, `start`, `update`, `update-runners`, and `upgrade-all` create a missing folder
with mode `0777`; an existing folder is never modified. `generate`, `status`, `down`, `stop`, and
`clean` never create the folder, and teardown never deletes or modifies it. An entry that is not a
directory (for example a stray file) stops the command with a clear message before any container
starts.

Treat the folder as a shared zone: every local account on the host — not only the organization's
jobs — can read, replace, or delete its contents, and nested containers may create files owned by
root or arbitrary user IDs. Do not store secrets there.

## Adding and removing organizations

```bash
./fleet.sh up        # apply a new organization
./fleet.sh restart   # also remove containers of deleted organizations
```

## GitHub Enterprise

`url=` sets both the web URL used for registration and the API base:

| `url=` | `GITHUB_URL` | `GITHUB_API_URL` |
| --- | --- | --- |
| default | `https://github.com/<name>` | `https://api.github.com` |
| `https://ghe.example.com/Contoso` | as given | `https://ghe.example.com/api/v3` |
