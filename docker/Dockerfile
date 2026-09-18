# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

FROM debian:bookworm@sha256:6ebd97fa83deb272194a2cf015b3d26a4d538e9ad3a7a79d544c8af5b0a01443 AS wine-builder

ARG WINE_JOBS=8
ARG WINE_VERSION=11.10
ARG WINE_SHA256=e4c35ebe26f4f8eef5f2143e24a1fb9fd103f1d46132ad4755479227d086b8e7
ARG WINE_URL=https://dl.winehq.org/wine/source/11.x/wine-11.10.tar.xz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bison \
        build-essential \
        ca-certificates \
        clang \
        curl \
        file \
        flex \
        lld \
        llvm \
        patch \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

RUN test "$(uname -m)" = aarch64 \
    && curl --fail --location --output wine.tar.xz "$WINE_URL" \
    && printf '%s  %s\n' "$WINE_SHA256" wine.tar.xz | sha256sum --check \
    && mkdir wine-source \
    && tar --extract --file wine.tar.xz --directory wine-source --strip-components=1

COPY patches/wine-11.10-page-align.patch /work/wine-11.10-page-align.patch

RUN patch --directory=/work/wine-source --strip=1 < /work/wine-11.10-page-align.patch

RUN mkdir wine-arm64 /opt/wine \
    && cd wine-arm64 \
    && ../wine-source/configure \
        --enable-win64 \
        --without-freetype \
        --without-x \
        --prefix=/opt/wine \
    && make -j"$WINE_JOBS" \
    && make install

RUN file -L /opt/wine/bin/wine \
    && /opt/wine/bin/wine --version

FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS wine-runtime

ARG WINE_VERSION=11.10

LABEL org.opencontainers.image.title="Patched ARM64 Wine runtime" \
      org.opencontainers.image.description="Minimal Linux ARM64 runtime for patched Wine" \
      org.opencontainers.image.licenses="LGPL-2.1-or-later" \
      org.opencontainers.image.source="https://github.com/farmisen/firefox-win64-cross-toolchain" \
      org.opencontainers.image.version="wine-${WINE_VERSION}-bookworm-r1"

COPY --from=wine-builder /opt/wine /opt/wine
COPY --from=wine-builder /work/wine-source/LICENSE /usr/share/doc/wine/LICENSE
COPY --from=wine-builder /work/wine-source/COPYING.LIB /usr/share/doc/wine/COPYING.LIB
COPY patches/wine-11.10-page-align.patch /usr/share/doc/wine/wine-11.10-page-align.patch

RUN useradd --create-home --uid 1000 builder

ENV PATH="/opt/wine/bin:${PATH}" \
    WINEDEBUG=-all

USER builder
WORKDIR /home/builder

CMD ["bash"]

FROM wine-runtime AS firefox-toolchain

ARG WINE_VERSION=11.10

LABEL org.opencontainers.image.title="Firefox Windows cross toolchain" \
      org.opencontainers.image.description="Linux ARM64 base for cross-compiling Firefox to Windows x86-64 or ARM64" \
      org.opencontainers.image.version="wine-${WINE_VERSION}-bookworm-r1"

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        7zip \
        ca-certificates \
        curl \
        file \
        git \
        m4 \
        make \
        msitools \
        nasm \
        nsis \
        pkg-config \
        python3 \
        python3-venv \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /builds/worker/checkouts \
    && chown -R builder:builder /builds/worker/checkouts

USER builder
WORKDIR /builds/worker/checkouts

CMD ["bash"]
