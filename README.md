# Firefox Windows cross toolchain

Build and package Firefox for x86-64 or ARM64 Windows on a Linux ARM64 host.

## Requirements

- An ARM64 host or native ARM64 Docker runner
- Docker with `linux/arm64` support
- A Firefox source checkout
- At least 16 GB of memory and 60 GB of free disk space

## Published images

The Firefox build image contains patched native ARM64 Wine and the Linux tools
needed by the Firefox build:

```sh
docker pull \
  ghcr.io/farmisen/firefox-win64-cross-toolchain:wine-11.10-bookworm-r2
```

The minimal runtime image contains the same Wine installation without the
Firefox build tools:

```sh
docker pull \
  ghcr.io/farmisen/firefox-win64-cross-toolchain:wine-runtime-11.10-bookworm-r2
```

Both images support `linux/arm64` only.

## Build the images

```sh
./scripts/build-image.sh
```

The command builds the Wine runtime and Firefox toolchain images. Set
`FXC_WINE_IMAGE` and `FXC_IMAGE` to change their tags:

```sh
FXC_WINE_IMAGE=example/wine-runtime:wine-11.10-bookworm-r2 \
  FXC_IMAGE=example/firefox-toolchain:wine-11.10-bookworm-r2 \
  ./scripts/build-image.sh
```

## Build Firefox for Windows x86-64

The first build downloads the Mozilla and Microsoft toolchains pinned by the
Firefox checkout. Review the applicable Microsoft terms, then run:

```sh
FXC_ACCEPT_MICROSOFT_LICENSE=1 \
  ./scripts/build-firefox.sh /absolute/path/to/firefox
```

The command configures, builds, and packages Firefox. It stores downloaded
toolchains and the object directory in Docker volumes. The installer, ZIP,
checksums, and Firefox revision are written to `artifacts/win64/`.

For later builds from the same checkout:

```sh
./scripts/build-firefox.sh /absolute/path/to/firefox
```

## Build Firefox for Windows ARM64

```sh
FXC_ACCEPT_MICROSOFT_LICENSE=1 \
  FXC_TARGET=win64-aarch64 \
  ./scripts/build-firefox.sh /absolute/path/to/firefox
```

After the toolchains are hydrated, omit `FXC_ACCEPT_MICROSOFT_LICENSE`.
ARM64 artifacts are written to `artifacts/win64-aarch64/`.

The targets use separate object-directory volumes. They share the downloaded
toolchain volume.

Set these variables to change the defaults:

| Variable | Purpose |
| --- | --- |
| `FXC_TARGET` | `win64` (default) or `win64-aarch64` |
| `FXC_IMAGE` | Container image name |
| `FXC_WINE_IMAGE` | Minimal Wine runtime image name |
| `FXC_STATE_VOLUME` | Downloaded toolchain volume |
| `FXC_OBJDIR_VOLUME` | Firefox object directory volume |
| `FXC_ARTIFACTS_DIR` | Host artifact directory |
| `FXC_JOBS` | Parallel build job count |

## Verify the setup

```sh
./scripts/check.sh
./scripts/check-toolchains.sh
./scripts/check-wine-runtime-tools.sh
```

The first command checks the repository and both images. The second checks the
complete hydrated toolchain and compiles minimal Windows binaries for both
targets. The third executes MIDL, FXC, and the Microsoft x64 and ARM64
assemblers using only the minimal Wine runtime image.

## Image contents

Both images contain a patched native ARM64 build of Wine 11.10. The toolchain
image also contains the Debian packages used to build Firefox. The Wine source
URL and SHA-256 digest are pinned in
[`docker/Dockerfile`](docker/Dockerfile). The Wine patch is stored in
[`patches/wine-11.10-page-align.patch`](patches/wine-11.10-page-align.patch).
The `r2` images strip debug sections from Wine runtime binaries and omit static
development archives that still contain debug sections.

The published images do not contain Firefox source, MSVC, Visual Studio VSIX
files, the Windows SDK, a Wine prefix, `.mozbuild` state, credentials, or build
outputs. Toolchain hydration stores Microsoft files in the local
`FXC_STATE_VOLUME` after license acceptance.

## License

Original source and documentation in this repository are licensed under the
Mozilla Public License 2.0. See [`LICENSE`](LICENSE).

Third-party components retain their own licenses. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
