#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root"/scripts/*.sh

for file in LICENSE README.md AGENTS.md CLAUDE.md docker/Dockerfile patches/wine-11.10-page-align.patch; do
  test -s "$repo_root/$file"
done

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
