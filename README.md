# Firefox Win64 cross toolchain

Build and package Firefox for x86-64 Windows on a Linux ARM64 host.

## Requirements

- An ARM64 host or native ARM64 Docker runner
- Docker with `linux/arm64` support
- A Firefox source checkout
- At least 16 GB of memory and 60 GB of free disk space

## Build the image

```sh
./scripts/build-image.sh
```

The default image tag is
`firefox-win64-cross-toolchain:wine-11.10-bookworm-r1`. Set `FXC_IMAGE` to use
a different tag:

```sh
FXC_IMAGE=ghcr.io/example/firefox-win64-cross-toolchain:wine-11.10-bookworm-r1 \
  ./scripts/build-image.sh
```

## Build Firefox

The first build downloads the Mozilla and Microsoft toolchains pinned by the
Firefox checkout. Review the applicable Microsoft terms, then run:

```sh
FXC_ACCEPT_MICROSOFT_LICENSE=1 \
  ./scripts/build-firefox.sh /absolute/path/to/firefox
```

The command configures, builds, and packages Firefox. It stores downloaded
toolchains and the object directory in Docker volumes. The installer, ZIP,
checksums, and Firefox revision are written to `artifacts/`.

For later builds from the same checkout:

```sh
./scripts/build-firefox.sh /absolute/path/to/firefox
```

Set these variables to change the defaults:

| Variable | Purpose |
| --- | --- |
| `FXC_IMAGE` | Container image name |
| `FXC_STATE_VOLUME` | Downloaded toolchain volume |
| `FXC_OBJDIR_VOLUME` | Firefox object directory volume |
| `FXC_ARTIFACTS_DIR` | Host artifact directory |
| `FXC_JOBS` | Parallel build job count |

## Verify the setup

```sh
./scripts/check.sh
./scripts/check-toolchains.sh
```

The first command checks the repository and base image. The second command
executes the hydrated MIDL, FXC, and Microsoft x64 assembler under native ARM64
Wine.

## Image contents

The image contains Debian packages and a patched native ARM64 build of Wine
11.10. The Wine source URL and SHA-256 digest are pinned in
[`docker/Dockerfile`](docker/Dockerfile). The Wine patch is stored in
[`patches/wine-11.10-page-align.patch`](patches/wine-11.10-page-align.patch).

The published image does not contain Firefox source, MSVC, Visual Studio VSIX
files, the Windows SDK, a Wine prefix, `.mozbuild` state, credentials, or build
outputs. Toolchain hydration stores Microsoft files in the local
`FXC_STATE_VOLUME` after license acceptance.

## License

Original source and documentation in this repository are licensed under the
Mozilla Public License 2.0. See [`LICENSE`](LICENSE).

Third-party components retain their own licenses. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
