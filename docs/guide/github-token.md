# GitHub token

The fleet uses **one** token, `ACCESS_TOKEN`, to mint runner registration tokens. It must be able
to **manage self-hosted runners for every organization in `orgs.conf`**.

## Which token type?

| Option | Works for | Required scope / permission |
| --- | --- | --- |
| **Classic PAT** (recommended for multiple orgs) | Every organization you administer | `admin:org` |
| Fine-grained PAT | **One** organization per token | Organization permissions → **Self-hosted runners: Read and write** |
| GitHub App installation token | One organization; short-lived | Self-hosted runners: Read and write (not supported by the CLI yet) |

Fine-grained tokens are scoped to a single resource owner (you or one organization), while the fleet
takes one token for all organizations. Use a classic PAT with `admin:org` when `orgs.conf` has more
than one organization; to use fine-grained tokens, run one build server (one `orgs.conf`) per
organization.

## Create a classic PAT

1. GitHub → your avatar → **Settings** → **Developer settings** → **Personal access tokens** →
   **Tokens (classic)**.
2. **Generate new token (classic)** and name it, for example `build-server runners`.
3. Set an expiration you will remember (see [Expiry and rotation](#expiry-and-rotation)).
4. Select the **`admin:org`** scope.
5. **Generate token** and copy it now — GitHub shows it only once.
6. If an organization uses **SAML SSO**, open the token and click **Configure SSO** →
   **Authorize** for each organization in `orgs.conf`.

Store it on the build host:

```bash
cp .env.example .env
# edit .env
ACCESS_TOKEN=ghp_...
```

`.env` is gitignored; keep it `0600`. `bootstrap.sh` asks for the token and writes this file.

## Fine-grained alternative (one organization)

1. Settings → Developer settings → Personal access tokens → **Fine-grained tokens**.
2. **Resource owner**: the organization (it must allow fine-grained tokens).
3. **Repository access**: none required for runner registration; set an expiration.
4. **Organization permissions** → **Self-hosted runners: Read and write**.
5. Generate the token and use it in `.env` exactly like a classic one.

## GitHub Enterprise Server

Perform the same steps on your GHES instance. The generator derives the API base from the
organization's `url=` (`https://<host>/api/v3`), so no extra configuration is needed.

## Verify the token

```bash
curl -fsS -X POST -H "Authorization: token $ACCESS_TOKEN" \
  https://api.github.com/orgs/<org>/actions/runners/registration-token
```

A JSON body with a `token` field means the fleet can register runners for that organization.
`404` usually means the token cannot see the organization; `401` means it is invalid or expired.

## Cloning over SSH instead

`ACCESS_TOKEN` mints runner registration tokens, but the repository checkout can use SSH:

```bash
bash bootstrap.sh --ssh                 # reuse ~/.ssh/id_rsa
bash bootstrap.sh --generate-ssh-key    # create a key and install it on GitHub
```

To let the installer upload the new public key, the token also needs the classic
`write:public_key` scope (fine-grained: **Git SSH keys: Read and write**). Without it, the
installer prints the public key and the URL to add it manually.

## Expiry and rotation

- Registration tokens are minted each time a runner container starts, so an expired `ACCESS_TOKEN`
  breaks runners only after a container restart. Put a reminder on the expiration date.
- To rotate: create the replacement, update `.env`, then run `./fleet.sh restart`.
- Treat the token as the fleet's most sensitive credential: it is present in every runner
  container's environment, where any job can read it. Use private repositories only — see the
  [Security model](/architecture/security).
