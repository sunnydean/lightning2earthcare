# Pixi's documented multi-stage build: https://pixi.prefix.dev/latest/deployment/container/
# Pin the official Pixi 0.79.0 image to its multi-platform registry digest.
FROM ghcr.io/prefix-dev/pixi:0.79.0@sha256:80a5b1e06fa988cc22554e8bf9e6b4bae87597771c568873691335667055c87d AS build

WORKDIR /app

# Cache the environment separately from application changes.
COPY pixi.toml pixi.lock ./
RUN pixi install --locked -e default

# Save activation as a standalone entrypoint so the runtime does not need Pixi.
RUN pixi shell-hook -e default -s bash > /shell-hook
RUN echo "#!/bin/bash" > /app/entrypoint.sh
RUN cat /shell-hook >> /app/entrypoint.sh
# extend the shell-hook script to run the command passed to the container
RUN echo 'exec "$@"' >> /app/entrypoint.sh

COPY lightning2ec/ ./lightning2ec/

# Check imports and CLI setup without fetching satellite data.
RUN pixi run --locked check

FROM ubuntu:24.04 AS production

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    MPLBACKEND=Agg \
    LIGHTNING2EC_CREDENTIALS_FILE=/run/secrets/credentials.txt

# Preserve the environment's absolute path from the build stage.
COPY --from=build /app/.pixi/envs/default /app/.pixi/envs/default
COPY --from=build --chmod=0755 /app/entrypoint.sh /app/entrypoint.sh
COPY lightning2ec/ ./lightning2ec/

# Run the CLI in the activated environment.
ENTRYPOINT ["/app/entrypoint.sh", "python", "-m", "lightning2ec.cli"]
CMD ["--help"]
