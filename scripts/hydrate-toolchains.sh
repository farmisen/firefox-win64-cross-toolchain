#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: hydrate-toolchains.sh FIREFOX_CHECKOUT

Download the Firefox-pinned Mozilla and Microsoft toolchains for x86-64 and
ARM64 Windows builds into a Docker volume. Set
FXC_ACCEPT_MICROSOFT_LICENSE=1 before the first Microsoft download.

Environment:
  FXC_IMAGE         Container image to use
  FXC_STATE_VOLUME  Toolchain state volume
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

for path in mach build/moz.configure taskcluster/scripts/misc/get_vs.py; do
  if [[ ! -e "$checkout/$path" ]]; then
    printf 'Firefox checkout is missing %s: %s\n' "$path" "$checkout" >&2
    exit 1
  fi
done

image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r2}
state_volume=${FXC_STATE_VOLUME:-firefox-win64-cross-toolchain-state}
accept_microsoft_license=${FXC_ACCEPT_MICROSOFT_LICENSE:-0}

# Pinned rustup installer for the Linux ARM64 build container. Keep in sync
# with RUSTUP_VERSION and RUSTUP_HASHES in python/mozboot/mozboot/rust.py.
rustup_version=1.29.0
rustup_host=aarch64-unknown-linux-gnu
rustup_sha256=9732d6c5e2a098d3521fca8145d826ae0aaa067ef2385ead08e6feac88fa5792

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Docker image not found: %s\nRun ./scripts/build-image.sh first.\n' "$image" >&2
  exit 1
fi

docker volume create "$state_volume" >/dev/null
docker run --rm \
  --platform linux/arm64 \
  --user root \
  --mount "type=volume,src=$state_volume,dst=/home/builder" \
  "$image" \
  chown builder:builder /home/builder

docker run --rm \
  --platform linux/arm64 \
  --mount "type=bind,src=$checkout,dst=/src,readonly" \
  --mount "type=volume,src=$state_volume,dst=/home/builder" \
  --env "FXC_ACCEPT_MICROSOFT_LICENSE=$accept_microsoft_license" \
  --env "FXC_STATE_VOLUME=$state_volume" \
  --env "FXC_RUSTUP_VERSION=$rustup_version" \
  --env "FXC_RUSTUP_HOST=$rustup_host" \
  --env "FXC_RUSTUP_SHA256=$rustup_sha256" \
  "$image" \
  bash -lc '
    set -euo pipefail

    test "$(uname -m)" = aarch64
    git config --global --add safe.directory /src

    cd /src
    ./mach --no-interactive bootstrap \
      --application-choice browser \
      --no-system-changes

    # mach bootstrap --no-system-changes never installs Rust. Install rustup
    # the same way mozboot does; the version and digest match
    # python/mozboot/mozboot/rust.py in the Firefox checkout.
    rustup="$HOME/.cargo/bin/rustup"
    if [[ ! -x "$rustup" ]]; then
      printf "Installing rustup %s\n" "$FXC_RUSTUP_VERSION" >&2
      # rustup-init selects its mode from its file name, so keep the prefix.
      rustup_init=$(mktemp "${TMPDIR:-/tmp}/rustup-init.XXXXXX")
      curl --fail --silent --show-error --location --retry 3 \
        --output "$rustup_init" \
        "https://static.rust-lang.org/rustup/archive/$FXC_RUSTUP_VERSION/$FXC_RUSTUP_HOST/rustup-init"
      printf "%s  %s\n" "$FXC_RUSTUP_SHA256" "$rustup_init" | sha256sum --check --quiet -
      chmod 0700 "$rustup_init"
      "$rustup_init" -y --no-modify-path \
        --default-toolchain stable \
        --default-host "$FXC_RUSTUP_HOST" \
        --component rustfmt
      rm -f "$rustup_init"
    fi
    "$rustup" target add \
      x86_64-pc-windows-msvc \
      aarch64-pc-windows-msvc

    shopt -s nullglob
    manifests=(build/vs/vs*-aarch64.yaml)
    if (( ${#manifests[@]} != 1 )); then
      printf "Expected one ARM64 Visual Studio manifest, found %s\n" \
        "${#manifests[@]}" >&2
      exit 1
    fi

    manifest=${manifests[0]}
    manifest_hash=$(sha256sum "$manifest" | awk "{print \$1}")
    marker="$HOME/.mozbuild/firefox-win64-cross-vs.sha256"
    vs_dir="$HOME/.mozbuild/vs"

    vs_is_complete() {
      local root=$1
      local ml64 armasm64 midl fxc
      ml64=$(find "$root/VC/Tools/MSVC" -type f -executable \
        -path "*/bin/Hostarm64/x64/ml64.exe" -print -quit 2>/dev/null || true)
      armasm64=$(find "$root/VC/Tools/MSVC" -type f -executable \
        -path "*/bin/Hostarm64/arm64/armasm64.exe" -print -quit 2>/dev/null || true)
      midl=$(find "$root/Windows Kits/10/bin" -type f -executable \
        -path "*/arm64/midl.exe" -print -quit 2>/dev/null || true)
      fxc=$(find "$root/Windows Kits/10/bin" -type f -executable \
        -path "*/arm64/fxc.exe" -print -quit 2>/dev/null || true)
      [[ -n "$ml64" && -n "$armasm64" && -n "$midl" && -n "$fxc" ]]
    }

    installed_hash=
    if [[ -f "$marker" ]]; then
      installed_hash=$(<"$marker")
    fi

    if [[ "$installed_hash" == "$manifest_hash" ]] && vs_is_complete "$vs_dir"; then
      printf "Visual Studio sysroot is current.\n"
    else
      if [[ "$FXC_ACCEPT_MICROSOFT_LICENSE" != 1 ]]; then
        printf "%s\n" \
          "Microsoft toolchains are required." \
          "Review the applicable Microsoft terms, then rerun with:" \
          "  FXC_ACCEPT_MICROSOFT_LICENSE=1 ./scripts/hydrate-toolchains.sh /path/to/firefox" >&2
        exit 1
      fi

      tmp_dir="$HOME/.mozbuild/vs.fxc-tmp.$$"
      backup_dir="$HOME/.mozbuild/vs.fxc-backup.$$"
      rm -rf "$tmp_dir" "$backup_dir"

      restore_vs() {
        status=$?
        if (( status != 0 )) && [[ ! -d "$vs_dir" && -d "$backup_dir" ]]; then
          mv "$backup_dir" "$vs_dir"
        fi
        rm -rf "$tmp_dir"
        exit "$status"
      }
      trap restore_vs EXIT

      cd /tmp
      /src/mach --no-interactive python --virtualenv build \
        /src/taskcluster/scripts/misc/get_vs.py \
        "$manifest" \
        "$tmp_dir"
      vs_is_complete "$tmp_dir"

      if [[ -d "$vs_dir" ]]; then
        mv "$vs_dir" "$backup_dir"
      fi
      mv "$tmp_dir" "$vs_dir"
      printf "%s\n" "$manifest_hash" > "$marker"
      rm -rf "$backup_dir"
      trap - EXIT
    fi

    printf "STATE_VOLUME=%s\n" "$FXC_STATE_VOLUME"
  '

FXC_STATE_VOLUME=$state_volume \
  "$(cd "$(dirname "$0")" && pwd)/check-toolchains.sh"
