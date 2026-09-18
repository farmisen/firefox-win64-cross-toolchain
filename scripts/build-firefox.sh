#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-firefox.sh FIREFOX_CHECKOUT

Hydrate the Firefox-pinned toolchains, configure a Windows x86-64 build, build
Firefox, package it, and export the installer and ZIP.

Environment:
  FXC_ACCEPT_MICROSOFT_LICENSE  Set to 1 before the first Microsoft download
  FXC_IMAGE                     Container image to use
  FXC_STATE_VOLUME              Toolchain state volume
  FXC_OBJDIR_VOLUME             Firefox object directory volume
  FXC_ARTIFACTS_DIR             Host output directory
  FXC_JOBS                      Parallel build job count
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

checkout=$1
if [[ ! -d "$checkout" ]]; then
  printf 'Firefox checkout does not exist: %s\n' "$checkout" >&2
  exit 1
fi
checkout=$(cd "$checkout" && pwd -P)

for path in mach build/moz.configure; do
  if [[ ! -e "$checkout/$path" ]]; then
    printf 'Firefox checkout is missing %s: %s\n' "$path" "$checkout" >&2
    exit 1
  fi
done

repo_root=$(cd "$(dirname "$0")/.." && pwd)
image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r1}
state_volume=${FXC_STATE_VOLUME:-firefox-win64-cross-toolchain-state}
objdir_volume=${FXC_OBJDIR_VOLUME:-firefox-win64-cross-toolchain-objdir}
artifacts_dir=${FXC_ARTIFACTS_DIR:-$repo_root/artifacts}
jobs=${FXC_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '8')}

case "$jobs" in
  ''|*[!0-9]*|0)
    printf 'FXC_JOBS must be a positive integer: %s\n' "$jobs" >&2
    exit 1
    ;;
esac

"$repo_root/scripts/hydrate-toolchains.sh" "$checkout"

docker volume create "$objdir_volume" >/dev/null
docker run --rm \
  --platform linux/arm64 \
  --user root \
  --mount "type=volume,src=$objdir_volume,dst=/builds/worker/obj-win64" \
  "$image" \
  chown builder:builder /builds/worker/obj-win64

mkdir -p "$artifacts_dir"
artifacts_dir=$(cd "$artifacts_dir" && pwd -P)

mozconfig=$(mktemp)
container="firefox-win64-cross-build-$$"

cleanup() {
  docker rm --force "$container" >/dev/null 2>&1 || true
  rm -f "$mozconfig"
}
trap cleanup EXIT INT TERM

cat > "$mozconfig" <<'EOF'
if test -f "$topsrcdir/build/win64/mozconfig.enterprise"; then
  . "$topsrcdir/build/win64/mozconfig.enterprise"
else
  ac_add_options --target=x86_64-pc-windows-msvc
  ac_add_options --enable-project=browser
fi

ac_add_options --enable-bootstrap=no-update,-wine

export WINE=/opt/wine/bin/wine
export MAKENSISU=/usr/bin/makensis

mk_add_options MOZ_OBJDIR=/builds/worker/obj-win64
EOF
chmod 0644 "$mozconfig"

docker run --detach \
  --name "$container" \
  --platform linux/arm64 \
  --mount "type=bind,src=$checkout,dst=/src,readonly" \
  --mount "type=bind,src=$mozconfig,dst=/opt/firefox-cross/mozconfig,readonly" \
  --mount "type=bind,src=$artifacts_dir,dst=/artifacts" \
  --mount "type=volume,src=$state_volume,dst=/home/builder" \
  --mount "type=volume,src=$objdir_volume,dst=/builds/worker/obj-win64" \
  --env MOZCONFIG=/opt/firefox-cross/mozconfig \
  --env "FXC_JOBS=$jobs" \
  "$image" \
  sleep infinity >/dev/null

docker exec "$container" bash -lc '
  set -euo pipefail

  git config --global --add safe.directory /src
  export PATH="$HOME/.cargo/bin:$PATH"
  export WINEDEBUG=-all

  mapfile -t assemblers < <(
    find "$HOME/.mozbuild/vs/VC/Tools/MSVC" -type f \
      -path "*/bin/Hostarm64/x64/ml64.exe" -print | sort -V
  )
  if (( ${#assemblers[@]} == 0 )); then
    printf "HostARM64 x64 assembler not found\n" >&2
    exit 1
  fi
  export AS="${assemblers[-1]}"

  cd /src
  ./mach configure
  ./mach build -j "$FXC_JOBS"
  ./mach package

  test -s /builds/worker/obj-win64/dist/bin/firefox.exe
  test -s /builds/worker/obj-win64/dist/bin/xul.dll
  file /builds/worker/obj-win64/dist/bin/firefox.exe
  file /builds/worker/obj-win64/dist/bin/xul.dll
'

revision=$(git -C "$checkout" rev-parse HEAD 2>/dev/null || printf unknown)
host_uid=$(id -u)
host_gid=$(id -g)

docker exec \
  --user root \
  --env "FXC_REVISION=$revision" \
  --env "FXC_HOST_UID=$host_uid" \
  --env "FXC_HOST_GID=$host_gid" \
  "$container" \
  bash -lc '
    set -euo pipefail
    shopt -s nullglob

    outputs=(
      /builds/worker/obj-win64/dist/firefox-*.win64.installer.exe
      /builds/worker/obj-win64/dist/firefox-*.win64.zip
    )
    if (( ${#outputs[@]} < 2 )); then
      printf "Expected an installer and ZIP in the object directory\n" >&2
      exit 1
    fi

    for output in "${outputs[@]}"; do
      cp -f "$output" /artifacts/
    done
    cd /artifacts
    sha256sum "${outputs[@]##*/}" > SHA256SUMS
    printf "%s\n" "$FXC_REVISION" > FIREFOX_REVISION
    chown -R "$FXC_HOST_UID:$FXC_HOST_GID" /artifacts
  '

printf 'RESULT=FIREFOX_BUILD_PASS\n'
printf 'REVISION=%s\n' "$revision"
printf 'STATE_VOLUME=%s\n' "$state_volume"
printf 'OBJDIR_VOLUME=%s\n' "$objdir_volume"
printf 'ARTIFACTS=%s\n' "$artifacts_dir"
