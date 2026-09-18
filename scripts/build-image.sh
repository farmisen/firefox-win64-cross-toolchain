#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r1}

docker build \
  --platform linux/arm64 \
  --tag "$image" \
  --file "$repo_root/docker/Dockerfile" \
  "$repo_root"

printf 'IMAGE=%s\n' "$image"
