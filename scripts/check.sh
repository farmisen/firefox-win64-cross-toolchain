#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root"/scripts/*.sh

for file in \
  LICENSE \
  README.md \
  AGENTS.md \
  CLAUDE.md \
  docker/Dockerfile \
  patches/wine-11.10-page-align.patch \
  scripts/hydrate-toolchains.sh \
  scripts/check-toolchains.sh \
  scripts/check-wine-runtime-tools.sh \
  scripts/smoke-test-wine-runtime-image.sh \
  scripts/build-firefox.sh; do
  test -s "$repo_root/$file"
done

"$repo_root/scripts/hydrate-toolchains.sh" --help >/dev/null
"$repo_root/scripts/check-toolchains.sh" --help >/dev/null
"$repo_root/scripts/check-wine-runtime-tools.sh" --help >/dev/null
"$repo_root/scripts/build-firefox.sh" --help >/dev/null

if target_error=$(
  FXC_TARGET=unsupported "$repo_root/scripts/build-firefox.sh" "$repo_root" 2>&1
); then
  printf 'unsupported FXC_TARGET unexpectedly succeeded\n' >&2
  exit 1
fi
test "$target_error" = \
  'FXC_TARGET must be win64 or win64-aarch64: unsupported'

if command -v rg >/dev/null; then
  scan_command=(
    rg -n '/Users/farmisen|2026091[0-9]T|fxe-win-cross' "$repo_root"
    --glob '!scripts/check.sh'
    --glob '!docs/verified-run.md'
  )
else
  scan_command=(
    grep -R -nE
    --exclude=check.sh
    --exclude=verified-run.md
    --exclude-dir=.git
    '/Users/farmisen|2026091[0-9]T|fxe-win-cross'
    "$repo_root"
  )
fi

if "${scan_command[@]}"; then
  printf 'personal or experiment-specific path found\n' >&2
  exit 1
fi

"$repo_root/scripts/smoke-test-image.sh"
"$repo_root/scripts/smoke-test-wine-runtime-image.sh"
