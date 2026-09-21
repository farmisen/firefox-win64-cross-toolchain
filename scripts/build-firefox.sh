#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-firefox.sh FIREFOX_CHECKOUT

Hydrate the Firefox-pinned toolchains, configure an x86-64 or ARM64 Windows
build, build Firefox, package it, and export the installer and ZIP.

Environment:
  FXC_ACCEPT_MICROSOFT_LICENSE  Set to 1 before the first Microsoft download
  FXC_TARGET                    win64 (default) or win64-aarch64
  FXC_IMAGE                     Container image to use
  FXC_STATE_VOLUME              Toolchain state volume
  FXC_OBJDIR_VOLUME             Firefox object directory volume
  FXC_ARTIFACTS_DIR             Host output directory for the selected target
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

target=${FXC_TARGET:-win64}
case "$target" in
  win64)
    target_triple=x86_64-pc-windows-msvc
    assembler_pattern='*/bin/Hostarm64/x64/ml64.exe'
    package_platform=win64
    expected_file_arch=x86-64
    container_objdir=/builds/worker/obj-win64
    default_objdir_volume=firefox-win64-cross-toolchain-objdir
    ;;
  win64-aarch64)
    target_triple=aarch64-pc-windows-msvc
    assembler_pattern='*/bin/Hostarm64/arm64/armasm64.exe'
    package_platform=win64-aarch64
    expected_file_arch=Aarch64
    container_objdir=/builds/worker/obj-win64-aarch64
    default_objdir_volume=firefox-win64-cross-toolchain-objdir-win64-aarch64
    ;;
  *)
    printf 'FXC_TARGET must be win64 or win64-aarch64: %s\n' "$target" >&2
    exit 2
    ;;
esac

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
image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r2}
state_volume=${FXC_STATE_VOLUME:-firefox-win64-cross-toolchain-state}
objdir_volume=${FXC_OBJDIR_VOLUME:-$default_objdir_volume}
artifacts_dir=${FXC_ARTIFACTS_DIR:-$repo_root/artifacts/$target}
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
  --mount "type=volume,src=$objdir_volume,dst=$container_objdir" \
  --env "FXC_OBJDIR=$container_objdir" \
  --env "FXC_TARGET=$target" \
  "$image" \
  bash -lc '
    set -euo pipefail
    marker="$FXC_OBJDIR/.fxc-target"
    if [[ -f "$marker" ]] && [[ "$(<"$marker")" != "$FXC_TARGET" ]]; then
      printf "Object volume belongs to %s, not %s\n" \
        "$(<"$marker")" "$FXC_TARGET" >&2
      exit 1
    fi
    printf "%s\n" "$FXC_TARGET" > "$marker"
    chown builder:builder "$FXC_OBJDIR" "$marker"
  '

mkdir -p "$artifacts_dir"
artifacts_dir=$(cd "$artifacts_dir" && pwd -P)

mozconfig=$(mktemp)
container="firefox-win64-cross-build-$$"

cleanup() {
  docker rm --force "$container" >/dev/null 2>&1 || true
  rm -f "$mozconfig"
}
trap cleanup EXIT INT TERM

cat > "$mozconfig" <<EOF
if test -f "\$topsrcdir/build/mozconfig.common.enterprise"; then
  . "\$topsrcdir/build/mozconfig.common.enterprise"
fi

ac_add_options --target=$target_triple
ac_add_options --enable-project=browser
ac_add_options --enable-bootstrap=no-update,-wine

export CC="\$HOME/.mozbuild/clang/bin/clang-cl --target=$target_triple"
export CXX="\$HOME/.mozbuild/clang/bin/clang-cl --target=$target_triple"
export WINE=/opt/wine/bin/wine
export MAKENSISU=/usr/bin/makensis

mk_add_options MOZ_OBJDIR=$container_objdir
EOF
chmod 0644 "$mozconfig"

docker run --detach \
  --name "$container" \
  --platform linux/arm64 \
  --mount "type=bind,src=$checkout,dst=/src,readonly" \
  --mount "type=bind,src=$mozconfig,dst=/opt/firefox-cross/mozconfig,readonly" \
  --mount "type=bind,src=$artifacts_dir,dst=/artifacts" \
  --mount "type=volume,src=$state_volume,dst=/home/builder" \
  --mount "type=volume,src=$objdir_volume,dst=$container_objdir" \
  --env MOZCONFIG=/opt/firefox-cross/mozconfig \
  --env "FXC_JOBS=$jobs" \
  --env "FXC_ASSEMBLER_PATTERN=$assembler_pattern" \
  --env "FXC_EXPECTED_FILE_ARCH=$expected_file_arch" \
  --env "FXC_OBJDIR=$container_objdir" \
  --env "FXC_PACKAGE_PLATFORM=$package_platform" \
  --env "FXC_TARGET_TRIPLE=$target_triple" \
  "$image" \
  sleep infinity >/dev/null

docker exec "$container" bash -lc '
  set -euo pipefail

  git config --global --add safe.directory /src
  export PATH="$HOME/.cargo/bin:$PATH"
  export WINEDEBUG=-all

  mapfile -t assemblers < <(
    find "$HOME/.mozbuild/vs/VC/Tools/MSVC" -type f \
      -path "$FXC_ASSEMBLER_PATTERN" -print | sort -V
  )
  if (( ${#assemblers[@]} == 0 )); then
    printf "Assembler not found for %s\n" "$FXC_TARGET_TRIPLE" >&2
    exit 1
  fi
  export AS="${assemblers[-1]}"

  cd /src
  ./mach configure
  ./mach build -j "$FXC_JOBS"
  rm -f \
    "$FXC_OBJDIR"/dist/firefox-*."$FXC_PACKAGE_PLATFORM".installer.exe \
    "$FXC_OBJDIR"/dist/firefox-*."$FXC_PACKAGE_PLATFORM".zip
  ./mach package

  for binary in "$FXC_OBJDIR/dist/bin/firefox.exe" "$FXC_OBJDIR/dist/bin/xul.dll"; do
    test -s "$binary"
    description=$(file "$binary")
    printf "%s\n" "$description"
    if [[ "$description" != *"$FXC_EXPECTED_FILE_ARCH"* ]]; then
      printf "Unexpected binary architecture for %s\n" "$binary" >&2
      exit 1
    fi
  done
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
      "$FXC_OBJDIR"/dist/firefox-*."$FXC_PACKAGE_PLATFORM".installer.exe
      "$FXC_OBJDIR"/dist/firefox-*."$FXC_PACKAGE_PLATFORM".zip
    )
    if (( ${#outputs[@]} != 2 )); then
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
printf 'TARGET=%s\n' "$target"
printf 'REVISION=%s\n' "$revision"
printf 'STATE_VOLUME=%s\n' "$state_volume"
printf 'OBJDIR_VOLUME=%s\n' "$objdir_volume"
printf 'ARTIFACTS=%s\n' "$artifacts_dir"
