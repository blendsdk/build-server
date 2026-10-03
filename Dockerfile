FROM ubuntu:24.04

ARG RUNNER_VERSION="2.337.0"
ARG NVM_VERSION="0.40.3"

SHELL ["/bin/bash", "-c"]

# Update the base system and create the unprivileged user the runner runs as.
RUN apt-get update -y && apt-get upgrade -y && useradd -m docker

# Base toolchain: git backs the runner and actions/checkout, OpenSSH serves the staged keys for
# private repositories, and jq parses the JSON the runner entrypoint reads.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl jq git openssh-client build-essential libssl-dev libffi-dev python3 python3-venv \
    python3-dev python3-pip mc liblttng-ust1t64 unzip rsync upx-ucl

# Browser runtime libraries for the Chrome build that Puppeteer downloads.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    vim libx11-xcb1 libxcomposite1 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcairo2 libcups2t64 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libglib2.0-0t64 \
    libgtk-3-0t64 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libxcb1 \
    libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
    libxtst6 libnss3

# Docker engine used by the private daemon inside each runner container.
RUN curl -sSL https://get.docker.com | bash

# GitHub Actions runner, pinned so image rebuilds are reproducible.
RUN cd /home/docker && \
    mkdir actions-runner && \
    cd actions-runner && \
    curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    chown -R docker ~docker && /home/docker/actions-runner/bin/installdependencies.sh && \
    rm ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# PostgreSQL client and the legacy docker-compose wrapper used by existing jobs.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-client docker-compose

RUN ln -sf /bin/bash /bin/sh

# Container entrypoint and the lock utility jobs invoke.
COPY start.sh entrypoint.sh /
COPY work_queue /bin/work_queue
RUN chmod +x /start.sh /entrypoint.sh /bin/work_queue

# Host-provided package-manager credentials and Docker registry configuration.
COPY ./.npmrc /home/docker/.npmrc
COPY ./.yarnrc /home/docker/.yarnrc
COPY ./.bunfig.toml /home/docker/.bunfig.toml
COPY ./config.json /home/docker/.docker/config.json

# SSH material for private repositories; fleet.sh stages it in the build context.
RUN mkdir -p /home/docker/.ssh
COPY ./ssh/id_rsa /home/docker/.ssh/id_rsa
COPY ./ssh/id_rsa.pub /home/docker/.ssh/id_rsa.pub
COPY ./ssh/config /home/docker/.ssh/config
RUN chmod 0700 /home/docker/.ssh && \
    chmod 0600 /home/docker/.ssh/id_rsa /home/docker/.ssh/id_rsa.pub /home/docker/.ssh/config && \
    chown -R docker ~docker

USER docker

# Node is installed once at build time; the runner entrypoint re-sources the nvm profile.
ENV NVM_DIR=/home/docker/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    npm install -g npm@latest yarn pnpm

USER root

ENTRYPOINT ["/entrypoint.sh"]
