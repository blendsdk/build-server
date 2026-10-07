# Custom images

An organization can build its own runner image from a folder in this repository.

## Configure

1. Create a folder with a `Dockerfile`, for example `orgs/acme/Dockerfile`:

   ```dockerfile
   FROM runner-image
   RUN apt-get update -y && apt-get install -y --no-install-recommends terraform \
       && rm -rf /var/lib/apt/lists/*
   ```

2. Point the organization at it in `orgs.conf`:

   ```
   AcmeTools context=orgs/acme
   ```

3. Build it:

   ```bash
   ./fleet.sh build AcmeTools
   ```

The image is tagged `runner-image-acmetools` and used by that organization's runner. Other
organizations keep the default `runner-image`.

## The base image contract

- Start `FROM runner-image` and add layers. That keeps the entrypoint, the inner Docker engine, and
  the runner user intact.
- A self-contained Dockerfile is possible, but it must provide the same contract: the root
  `/entrypoint.sh` (start `dockerd`, then run `/start.sh` as the `docker` user), an
  `/home/docker/actions-runner`, and `start.sh` in place.
- To support `deploy_ssh=` and `check-ssh`, the image must also run the entrypoint deploy SSH
  staging (copy `/run/deploy-ssh` into the runner user's `~/.ssh/deploy.d/` and prepend
  `Include ~/.ssh/deploy.d/config` to `~/.ssh/config`) and ship `deploy-ssh-check` as
  `/usr/local/bin/deploy-ssh-check`. Inheriting `FROM runner-image` provides both — see
  [Deploy over SSH](/guide/deploy-ssh).
- `update-runners` builds the default image first, then every custom context with
  `--build-arg RUNNER_VERSION=<version>`. Consume that argument if you replace the base:

  ```dockerfile
  ARG RUNNER_VERSION
  ```

## Staging

Custom builds never see your credentials until the build starts:

- The context is copied to a gitignored `.fleet-build/<slug>/` directory.
- `~/.ssh` and the host credential files are copied there with restricted modes.
- The directory is removed afterwards, whether the build succeeds or fails.

Do not put secrets in the context folder — they are refused for staging and would be committed
otherwise.
