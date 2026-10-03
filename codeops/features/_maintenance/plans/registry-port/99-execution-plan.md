# Task T-03: Configurable registry host port

> **Type**: Task (lightweight) · **Feature**: _maintenance · **CodeOps Artifact Schema**: 1
> **Progress**: 5/5 tasks (100%)

## Objective

`fleet.sh up` fails when the host already binds port 5000 (`Bind for 0.0.0.0:5000 failed: port is
already allocated`). Make the registry's **host** port configurable and have the installer pick a
free one automatically. Runner services keep using `registry:5000` over the internal Compose
network, so the fleet never depends on the host port.

**Smallest viable design:** `${REGISTRY_PORT:-5000}:5000` in `docker-compose.yml`; `bootstrap.sh`
checks the port before writing `.env` and, when `5000` is busy and `REGISTRY_PORT` was not given
explicitly, selects the first free port in 5000–5050 and records it in `.env`. No new dependency
(`ss` ships with Ubuntu) and no change to runner networking.

## Tasks

- [x] T-03.1 Spec tests: compose port override; bootstrap auto-selects a free port; explicit busy port fails ✅ (completed: 2026-10-03 14:48)
- [x] T-03.2 Red phase ✅ (completed: 2026-10-03 14:48)
- [x] T-03.3 Implement in `docker-compose.yml`, `bootstrap.sh`, and `.env.example` ✅ (completed: 2026-10-03 14:50)
- [x] T-03.4 Green phase plus docs (getting started, reference, FAQ "does the registry need a domain", troubleshooting) ✅ (completed: 2026-10-03 14:52)
- [x] T-03.5 Full verification: `shellcheck`, `bash test/verify.sh`, `npm run docs:build` ✅ (completed: 2026-10-03 14:52)

**Verify**: `shellcheck -S style bootstrap.sh test/*.sh && bash test/verify.sh && npm run docs:build`
