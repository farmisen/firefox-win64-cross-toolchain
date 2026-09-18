#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-wine-runtime-tools.sh

Execute the hydrated Microsoft x64 assembler, ARM64 assembler, MIDL, and FXC
under the minimal native ARM64 Wine runtime image.

Environment:
  FXC_WINE_IMAGE    Wine runtime image to use
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

image=${FXC_WINE_IMAGE:-firefox-win64-cross-toolchain:wine-runtime-11.10-bookworm-r2}
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

    check_arm64_pe() {
      local binary=$1
      local pe_offset machine
      pe_offset=$(od -An -tu4 -j60 -N4 "$binary" | tr -d " ")
      machine=$(od -An -tx1 -j "$((pe_offset + 4))" -N2 "$binary" | tr -d " ")
      if [[ "$machine" != 64aa ]]; then
        printf "Not a Windows ARM64 executable: %s\n" "$binary" >&2
        exit 1
      fi
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
      test -x "$tool"
      check_arm64_pe "$tool"
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

    printf "RESULT=WINE_RUNTIME_TOOLS_PASS\n"
  '
