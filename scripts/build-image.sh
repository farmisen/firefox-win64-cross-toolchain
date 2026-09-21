#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
toolchain_image=${FXC_IMAGE:-ghcr.io/farmisen/firefox-win64-cross-toolchain:wine-11.10-bookworm-r2}
wine_runtime_image=${FXC_WINE_IMAGE:-ghcr.io/farmisen/firefox-win64-cross-toolchain:wine-runtime-11.10-bookworm-r2}
revision=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)

docker build \
  --platform linux/arm64 \
  --label "org.opencontainers.image.revision=$revision" \
  --target wine-runtime \
  --tag "$wine_runtime_image" \
  --file "$repo_root/docker/Dockerfile" \
  "$repo_root"

docker build \
  --platform linux/arm64 \
  --label "org.opencontainers.image.revision=$revision" \
  --target firefox-toolchain \
  --tag "$toolchain_image" \
  --file "$repo_root/docker/Dockerfile" \
  "$repo_root"

printf 'WINE_RUNTIME_IMAGE=%s\n' "$wine_runtime_image"
printf 'TOOLCHAIN_IMAGE=%s\n' "$toolchain_image"
