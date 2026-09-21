#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-toolchains.sh

Verify the hydrated ARM64 host tools and execute the Windows ARM64 MIDL, FXC,
x64 assembler, and ARM64 assembler tools under native ARM64 Wine. Compile and
link minimal x86-64 and ARM64 Windows binaries.

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

script_dir=$(cd "$(dirname "$0")" && pwd)
image=${FXC_IMAGE:-ghcr.io/farmisen/firefox-win64-cross-toolchain:wine-11.10-bookworm-r2}
state_volume=${FXC_STATE_VOLUME:-firefox-win64-cross-toolchain-state}

"$script_dir/ensure-image.sh" "$image"
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
      "$HOME/.mozbuild/clang/bin/lld-link"
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

    for rust_target in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
      rust_libdir=$("$HOME/.cargo/bin/rustc" \
        --print target-libdir --target "$rust_target")
      test -d "$rust_libdir"
      printf "%s: %s\n" "$rust_target" "$rust_libdir"
    done

    latest_match() {
      local root=$1
      local pattern=$2
      local matches
      mapfile -t matches < <(find "$root" -type f -ipath "$pattern" -print | sort -V)
      if (( ${#matches[@]} == 0 )); then
        printf "No file matches %s under %s\n" "$pattern" "$root" >&2
        return 1
      fi
      printf "%s\n" "${matches[-1]}"
    }

    ml64=$(latest_match "$HOME/.mozbuild/vs/VC/Tools/MSVC" \
      "*/bin/Hostarm64/x64/ml64.exe")
    armasm64=$(latest_match "$HOME/.mozbuild/vs/VC/Tools/MSVC" \
      "*/bin/Hostarm64/arm64/armasm64.exe")
    sdk_bin=$(dirname "$(latest_match "$HOME/.mozbuild/vs/Windows Kits/10/bin" \
      "*/arm64/midl.exe")")
    midl="$sdk_bin/midl.exe"
    fxc="$sdk_bin/fxc.exe"

    for tool in "$ml64" "$armasm64" "$midl" "$fxc"; do
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

    cat > probe-x64.asm <<"EOF"
.code
probe PROC
  ret
probe ENDP
END
EOF

    cat > probe-arm64.asm <<"EOF"
        AREA |.text|, CODE, READONLY
        EXPORT probe
probe PROC
        ret
        ENDP
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

    cat > probe.c <<"EOF"
void mainCRTStartup(void)
{
}
EOF

    /opt/wine/bin/wine "$ml64" \
      -nologo -Cp -Sn -Zi -c -Foprobe-x64.obj probe-x64.asm
    test "$(od -An -tx1 -N2 probe-x64.obj | tr -d " ")" = 6486

    /opt/wine/bin/wine "$armasm64" \
      -nologo -o probe-arm64.obj probe-arm64.asm
    test "$(od -An -tx1 -N2 probe-arm64.obj | tr -d " ")" = 64aa

    for midl_env in x64 arm64; do
      /opt/wine/bin/wine "$midl" \
        -nologo -no_cpp -env "$midl_env" \
        -h "probe_${midl_env}.h" \
        -iid "probe_${midl_env}_i.c" \
        -proxy "probe_${midl_env}_p.c" \
        -dlldata "probe_${midl_env}_d.c" \
        probe.idl
      test -s "probe_${midl_env}.h"
    done

    WINEDLLOVERRIDES=d3dcompiler_47=n \
      /opt/wine/bin/wine "$fxc" \
      -nologo -Tvs_4_0 -Emain -Fhprobe_fxc.h probe.hlsl
    test -s probe_fxc.h

    compile_and_check_pe() {
      local label=$1
      local triple=$2
      local machine=$3
      local expected_arch=$4
      local description

      "$HOME/.mozbuild/clang/bin/clang-cl" \
        --target="$triple" /nologo /c /GS- \
        "/Foprobe-${label}-clang.obj" probe.c
      "$HOME/.mozbuild/clang/bin/lld-link" \
        /nologo /entry:mainCRTStartup /subsystem:console /nodefaultlib \
        "/machine:${machine}" "/out:probe-${label}.exe" \
        "probe-${label}-clang.obj"
      description=$(file "probe-${label}.exe")
      printf "%s\n" "$description"
      case "$description" in
        *"$expected_arch"*) ;;
        *) printf "Unexpected PE architecture: %s\n" "$label" >&2; exit 1 ;;
      esac
    }

    compile_and_check_pe x64 x86_64-pc-windows-msvc x64 x86-64
    compile_and_check_pe arm64 aarch64-pc-windows-msvc arm64 Aarch64

    printf "RESULT=TOOLCHAIN_SMOKE_PASS\n"
  '
