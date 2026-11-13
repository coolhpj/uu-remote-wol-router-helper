# syntax=docker/dockerfile:1
# GPL-3.0-or-later standalone diagnostic: source is fetched and patched at build time.
# This is NOT the MIT router-identity Docker image or a published Release.
FROM rust:1-bookworm AS builder
ARG GPL_SOURCE_COMMIT=0e1e935fb41c2aac2bdd5eebdd4b38a7476d14bc
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      ca-certificates git python3 pkg-config build-essential \
      libx11-dev libxext-dev libxtst-dev libxfixes-dev \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v0.2.58 https://github.com/VallierDev/uu-remote-linux.git /opt/gpl-source \
    && test "$(git -C /opt/gpl-source rev-parse HEAD)" = "$GPL_SOURCE_COMMIT" \
    && grep -q 'GPL-3.0-or-later' /opt/gpl-source/Cargo.toml
COPY labs/gpl-isolation/apply-wol-only.py /opt/patch/apply-wol-only.py
RUN python3 /opt/patch/apply-wol-only.py /opt/gpl-source \
    && cd /opt/gpl-source && git diff --check \
    && UU_NO_GTK=1 CARGO_BUILD_JOBS=2 CARGO_INCREMENTAL=0 cargo build --locked --bin uuremote-server \
    && test -s target/debug/uuremote-server

FROM debian:bookworm-slim
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      ca-certificates libgcc-s1 libstdc++6 libx11-6 libxext6 libxtst6 libxfixes3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data /usr/share/doc/uu-wol-only \
    && chown 10001:10001 /data
COPY --from=builder /opt/gpl-source/target/debug/uuremote-server /usr/local/bin/uuremote-server
COPY --from=builder /opt/gpl-source/LICENSE /usr/share/doc/uu-wol-only/LICENSE
# No host Docker socket, no remote control ports; runtime capabilities are limited in Compose.
ENV HOME=/tmp UU_CONFIG=/data/config.json UU_DESKTOP_BACKEND=none UU_NO_GTK=1 \
    UU_WOL_ONLY=1 UU_WOL_HELPER=1 UU_REMOTE_ASSIST=0 UU_PORT_MAPPING=0
USER 10001:10001
WORKDIR /data
ENTRYPOINT ["/usr/local/bin/uuremote-server"]
