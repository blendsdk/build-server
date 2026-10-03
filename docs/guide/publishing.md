# Publishing images from jobs

Workflows running on a runner can build and push images to the co-located private registry with
plain Docker commands — no host-side login, no extra configuration.

## How it works

The runner's own Docker daemon talks to the registry by its Compose service name. Generated runner
services receive these variables:

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `REGISTRY_ADDR` | `registry:5000` | Registry address **inside** the fleet |
| `REGISTRY_USER` | from `.env` | Registry user (seeds the htpasswd file) |
| `REGISTRY_PASS` | from `.env` | Registry password |
| `INSECURE_REGISTRIES` | `registry:5000` | Registries the inner daemon treats as plain HTTP |

`start.sh` logs the inner daemon in at container boot, so a job can push immediately.

## Example workflow

```yaml
jobs:
  publish:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Build and push
        run: |
          REPO="$(echo "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
          IMAGE="$REGISTRY_ADDR/$REPO:$GITHUB_SHA"
          docker build -t "$IMAGE" .
          docker push "$IMAGE"
```

If you prefer an explicit login (for example after changing credentials), the values are already
in the environment:

```yaml
      - run: echo "$REGISTRY_PASS" | docker login "$REGISTRY_ADDR" -u "$REGISTRY_USER" --password-stdin
```

## Keeping credentials out of the job environment

Remove `REGISTRY_USER`/`REGISTRY_PASS` from the host `.env` and the generator injects none; the
automatic login is skipped. Jobs can then authenticate with their own repository secrets:

```yaml
      - run: echo "${{ secrets.REGISTRY_PASS }}" | docker login "$REGISTRY_ADDR" -u "${{ secrets.REGISTRY_USER }}" --password-stdin
```

## Plain HTTP and TLS

The co-located registry serves plain HTTP, so the inner daemon starts with
`--insecure-registry registry:5000`. If you replace it with a TLS registry, point `REGISTRY_ADDR`
at the new address and set `INSECURE_REGISTRIES=` (empty) to disable the flag.

## Outside the fleet

Other machines pull from the host port (`REGISTRY_PORT`). They need TLS or their own
`insecure-registries` configuration, and a reachable hostname or IP — see the
[FAQ](/reference/faq).

## Security

The credentials are visible to every job on the runner, consistent with this project's
trusted-CI model. See the [security model](/architecture/security).
