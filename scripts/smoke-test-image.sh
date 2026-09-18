#!/usr/bin/env bash

set -euo pipefail

image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r1}

docker run --rm --platform linux/arm64 "$image" bash -lc '
  set -euo pipefail

  test "$(uname -m)" = aarch64

  wine_file=$(file -L /opt/wine/bin/wine)
  printf "%s\n" "$wine_file"
  case "$wine_file" in
    *ARM\ aarch64*) ;;
    *) printf "Wine is not an AArch64 ELF executable\n" >&2; exit 1 ;;
  esac

  test "$(/opt/wine/bin/wine --version)" = wine-11.10

  for command in 7zz curl file git m4 make msibuild nasm makensis pkg-config python3 unzip zip; do
    command -v "$command" >/dev/null
  done

  printf "RESULT=IMAGE_SMOKE_PASS\n"
'
