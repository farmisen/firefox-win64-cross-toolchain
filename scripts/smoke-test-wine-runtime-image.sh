#!/usr/bin/env bash

set -euo pipefail

image=${FXC_WINE_IMAGE:-firefox-win64-cross-toolchain:wine-runtime-11.10-bookworm-r2}

debug_symbols=$(docker image inspect "$image" \
  --format '{{ index .Config.Labels "org.opencontainers.image.debug-symbols" }}')
if [[ "$debug_symbols" != stripped ]]; then
  printf 'Wine debug symbols are not marked stripped: %s\n' "$debug_symbols" >&2
  exit 1
fi

docker run --rm --platform linux/arm64 "$image" bash -lc '
  set -euo pipefail

  test "$(uname -m)" = aarch64
  test "$(/opt/wine/bin/wine --version)" = wine-11.10

  for binary in /opt/wine/bin/wine /opt/wine/bin/wineserver; do
    test "$(od -An -tx1 -N4 "$binary" | tr -d " ")" = 7f454c46
    test "$(od -An -tx1 -j18 -N2 "$binary" | tr -d " ")" = b700
    if ldd "$binary" | grep -q "not found"; then
      printf "Missing shared library for %s\n" "$binary" >&2
      exit 1
    fi
  done

  for command in 7zz curl file git m4 make msibuild nasm makensis \
      pkg-config python3 unzip zip; do
    if command -v "$command" >/dev/null; then
      printf "Unexpected tool in Wine runtime image: %s\n" "$command" >&2
      exit 1
    fi
  done

  test ! -e /builds
  test ! -e "$HOME/.mozbuild"
  test ! -e "$HOME/.wine"

  for microsoft_file in ml64.exe armasm64.exe midl.exe fxc.exe; do
    if find /opt /home -type f -iname "$microsoft_file" -print -quit | grep -q .; then
      printf "Unexpected Microsoft payload in Wine runtime image: %s\n" \
        "$microsoft_file" >&2
      exit 1
    fi
  done

  printf "RESULT=WINE_RUNTIME_SMOKE_PASS\n"
'
