# The School Fighter online server: the same Godot project, run headless.
# Build from the repo root:  docker build -f server/Dockerfile -t school-fighter-server .
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm /tmp/godot.zip

WORKDIR /app
COPY game/ ./game/
RUN godot --headless --path game --import

# Render (and most hosts) tell the server which port to use in $PORT.
ENV PORT=10000
EXPOSE 10000
CMD ["godot", "--headless", "--path", "game", "--", "--server"]
