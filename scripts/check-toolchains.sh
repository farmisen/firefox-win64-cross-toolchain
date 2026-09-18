#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-toolchains.sh

Verify the hydrated ARM64 host tools and execute the Windows ARM64 MIDL, FXC,
and x64 assembler tools under native ARM64 Wine.

Environment:
  FXC_IMAGE         Container image to use
  FXC_STATE_VOLUME  Toolchain state volume
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

if (( $# != 0 )); then
  usage >&2
  exit 2
fi

image=${FXC_IMAGE:-firefox-win64-cross-toolchain:wine-11.10-bookworm-r1}
state_volume=${FXC_STATE_VOLUME:-firefox-win64-cross-toolchain-state}

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Docker image not found: %s\n' "$image" >&2
  exit 1
fi
if ! docker volume inspect "$state_volume" >/dev/null 2>&1; then
  printf 'Toolchain state volume not found: %s\n' "$state_volume" >&2
  exit 1
fi

docker run --rm \
  --platform linux/arm64 \
  --mount "type=volume,src=$state_volume,dst=/home/builder,readonly" \
  "$image" \
  bash -lc '
    set -euo pipefail

    test "$(uname -m)" = aarch64
    test "$(/opt/wine/bin/wine --version)" = wine-11.10

    native_tools=(
      "$HOME/.mozbuild/clang/bin/clang-cl"
      "$HOME/.cargo/bin/rustc"
      "$HOME/.mozbuild/cbindgen/cbindgen"
      "$HOME/.mozbuild/node/bin/node"
      "$HOME/.mozbuild/dump_syms/dump_syms"
    )
    for tool in "${native_tools[@]}"; do
      description=$(file -L "$tool")
      printf "%s\n" "$description"
      case "$description" in
        *ARM\ aarch64*) ;;
        *) printf "Not a native ARM64 tool: %s\n" "$tool" >&2; exit 1 ;;
      esac
    done

    latest_match() {
      local root=$1
      local pattern=$2
      local matches
      mapfile -t matches < <(find "$root" -type f -path "$pattern" -print | sort -V)
      if (( ${#matches[@]} == 0 )); then
        printf "No file matches %s under %s\n" "$pattern" "$root" >&2
        return 1
      fi
      printf "%s\n" "${matches[-1]}"
    }

    ml64=$(latest_match "$HOME/.mozbuild/vs/VC/Tools/MSVC" \
      "*/bin/Hostarm64/x64/ml64.exe")
    sdk_bin=$(dirname "$(latest_match "$HOME/.mozbuild/vs/Windows Kits/10/bin" \
      "*/arm64/midl.exe")")
    midl="$sdk_bin/midl.exe"
    fxc="$sdk_bin/fxc.exe"

    for tool in "$ml64" "$midl" "$fxc"; do
      description=$(file -L "$tool")
      printf "%s\n" "$description"
      case "$description" in
        *Aarch64*) ;;
        *) printf "Not a Windows ARM64 tool: %s\n" "$tool" >&2; exit 1 ;;
      esac
    done

    work=$(mktemp -d)
    export WINEDEBUG=-all
    export WINEPREFIX="$work/wine"
    export XDG_CACHE_HOME="$work/cache"
    cd "$work"

    cat > probe.asm <<"EOF"
.code
probe PROC
  ret
probe ENDP
END
EOF

    cat > probe.idl <<"EOF"
[uuid(01234567-89ab-cdef-0123-456789abcdef), version(1.0)]
interface Arm64Probe
{
  void Ping();
};
EOF

    cat > probe.hlsl <<"EOF"
float4 main(float4 position : POSITION) : SV_Position
{
    return position;
}
EOF

    /opt/wine/bin/wine "$ml64" \
      -nologo -Cp -Sn -Zi -c -Foprobe.obj probe.asm
    test "$(od -An -tx1 -N2 probe.obj | tr -d " ")" = 6486

    /opt/wine/bin/wine "$midl" \
      -nologo -no_cpp -env x64 \
      -h probe_midl.h -iid probe_i.c -proxy probe_p.c -dlldata probe_d.c \
      probe.idl
    test -s probe_midl.h

    WINEDLLOVERRIDES=d3dcompiler_47=n \
      /opt/wine/bin/wine "$fxc" \
      -nologo -Tvs_4_0 -Emain -Fhprobe_fxc.h probe.hlsl
    test -s probe_fxc.h

    printf "RESULT=TOOLCHAIN_SMOKE_PASS\n"
  '
