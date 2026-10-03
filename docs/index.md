---
layout: home
hero:
  name: Build Server
  text: Self-hosted GitHub Actions runners that get Docker right
  tagline: An isolated Docker daemon inside every runner, a file-driven fleet, and one admin CLI.
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Architecture
      link: /architecture/overview
features:
  - title: Correct bind mounts
    details: Jobs run their own dockerd, so "$PWD" and Compose bind mounts resolve inside the runner instead of silently mounting empty host paths.
  - title: One admin CLI
    details: fleet.sh generates Compose from orgs.conf, builds default and per-org images, updates runner versions, and manages the lifecycle.
  - title: No host socket
    details: The host Docker socket is never mounted; each runner is a self-contained build box with its own image cache.
  - title: One-command install
    details: bootstrap.sh sets up a fresh Ubuntu host, collects secrets, builds the image, and starts the fleet.
  - title: Per-org images
    details: Point an organization at a context folder with a Dockerfile and it gets its own runner image.
  - title: Version updates
    details: update-runners resolves the latest Actions runner release, rebuilds every image, and recreates the fleet.
---
