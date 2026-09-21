#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ensure-image.sh IMAGE

Make IMAGE available locally. Use the local copy when present, otherwise pull
the linux/arm64 image. Exit non-zero when neither is possible.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

if (( $# != 1 )); then
  usage >&2
  exit 2
fi

image=$1

if docker image inspect "$image" >/dev/null 2>&1; then
  exit 0
fi

printf 'Docker image not found locally, pulling: %s\n' "$image" >&2
if ! docker pull --platform linux/arm64 "$image" >&2; then
  printf '%s\n' \
    "Could not pull Docker image: $image" \
    "Run ./scripts/build-image.sh to build it, or set FXC_IMAGE or" \
    "FXC_WINE_IMAGE to an image that exists." >&2
  exit 1
fi
