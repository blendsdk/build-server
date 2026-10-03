# Example custom runner image for the fleet CLI playground.
#
# A real custom context starts FROM runner-image (built first by `./fleet.sh build`) and adds the
# tools that organization needs. Image tags become runner-image-<org-slug>.
FROM runner-image
RUN apt-get update -y && apt-get install -y --no-install-recommends cowsay \
    && rm -rf /var/lib/apt/lists/*
