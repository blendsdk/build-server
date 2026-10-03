# FAQ

**Is this a replacement for GitHub-hosted runners?**

It is for builds that need a specific host, private network access, or custom hardware. For
untrusted public repositories, use GitHub-hosted runners.

**Why are runners privileged?**

Each runner runs a Docker daemon. That requires privileges; the alternative would be mounting the
host socket, which is the problem this project fixes. See
[Security model](/architecture/security).

**Can one organization have several runners?**

This version generates exactly one runner per organization. Scale a busy organization by deploying
a second build server, or open an issue if in-fleet replicas matter to you.

**Do runners keep state between jobs?**

Yes — they are persistent, so image layers and caches stay warm. Jobs can still leave files in the
workspace; workflows that need pristine state should clean up, or prefer ephemeral design later.

**Where do credentials live?**

Host-local and gitignored: `.env`, `.npmrc`, `.yarnrc`, `.bunfig.toml`, `config.json`, `ssh/`.
`fleet.sh build` stages them into the image with restricted modes and removes staged copies
afterwards.

**How do I add a second organization?**

Add one line to `orgs.conf` and run `./fleet.sh up`.

**How do I update the Actions runner version?**

`./fleet.sh update-runners`. See [Runner versions](/guide/runner-version).

**What if a build fails mid-way?**

`.runner-version` is only written after all builds succeed, and staging directories are removed on
failure. A SIGKILL can leave `.fleet-build/` behind; remove it manually.

**Does the private registry need to be reachable from outside?**

No. Runners reach it over the host network. Only other machines that pull your images need access.
