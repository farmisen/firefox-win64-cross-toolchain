# Firefox Win64 cross toolchain

Build tooling for compiling x86-64 Windows Firefox on Linux ARM64 hosts.

The repository currently contains the publishable base image proven by the
initial cross-build. It does not include Firefox source, Microsoft toolchains,
Windows SDK files, build outputs, credentials, or hydrated Docker volumes.

## Requirements

- Docker with `linux/arm64` support
- An ARM64 host or native ARM64 Docker runner
- About 16 GB of memory for a full Firefox build
- About 60 GB of free disk space for source, toolchains, and build outputs

## Build the base image

```sh
./scripts/build-image.sh
```

Override the local image name when needed:

```sh
FXC_IMAGE=ghcr.io/example/firefox-win64-cross-toolchain:wine-11.10-bookworm-r1 \
  ./scripts/build-image.sh
```

## Verify the image

```sh
./scripts/check.sh
```

The smoke test checks that the container is ARM64, Wine is the patched native
ARM64 Wine 11.10 build, and the Linux packaging commands are present.

## Current status

The toolchain has configured, built, and packaged Firefox Enterprise revision
`d09ed62da3ece870611d1928b4828e3b46bc9e66` for Windows x86-64. See
[`docs/verified-run.md`](docs/verified-run.md) for the recorded result.

The next repository unit will add clean-machine hydration of Mozilla and
Microsoft toolchains, the Firefox build command, and artifact export. Until
that is verified, this repository should not claim a one-command Firefox
build from empty Docker state.

## Distribution boundary

The image contains Debian packages and the patched Wine build only. Do not add
MSVC, Visual Studio VSIX files, the Windows SDK, Firefox Enterprise source, or
`.mozbuild` state to a published image without an approved licensing and
source-handling review.

Wine source is downloaded from WineHQ at build time and verified against a
pinned SHA-256 digest. The exact patch is stored in `patches/`.

## License

Original source and documentation in this repository are licensed under the
Mozilla Public License 2.0. See [`LICENSE`](LICENSE).

Third-party components retain their own licenses. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
