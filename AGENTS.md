# firefox-windows-cross-toolchain project guide

Docker tooling for building x86-64 and ARM64 Windows Firefox on Linux ARM64 hosts.

## Critical rules

- Never `git commit` or `git push` without explicit approval for that change.
- Never force-push or merge a pull request.
- Ask before adding a dependency.
- Never commit Microsoft toolchain payloads, Firefox Enterprise source, credentials, `.env` files, Docker volumes, or build outputs.
- Published images must not contain MSVC, Visual Studio VSIX files, the Windows SDK, a Wine prefix, or hydrated `.mozbuild` state.

## Commands

- Build images: `./scripts/build-image.sh`
- Check Wine runtime image: `./scripts/smoke-test-wine-runtime-image.sh`
- Check Microsoft tools under the Wine runtime: `./scripts/check-wine-runtime-tools.sh`
- Hydrate toolchains: `FXC_ACCEPT_MICROSOFT_LICENSE=1 ./scripts/hydrate-toolchains.sh /path/to/firefox`
- Build Firefox x86-64: `./scripts/build-firefox.sh /path/to/firefox`
- Build Firefox ARM64: `FXC_TARGET=win64-aarch64 ./scripts/build-firefox.sh /path/to/firefox`
- Run all checks: `./scripts/check.sh`
- Run the image smoke test: `./scripts/smoke-test-image.sh`
- Run the toolchain smoke test: `./scripts/check-toolchains.sh`

Run `./scripts/check.sh` before declaring a change complete.

## Layout

- `docker/`: publishable container definitions.
- `patches/`: exact source patches applied by container builds.
- `scripts/`: non-interactive build and verification entry points.
- `docs/`: verified results and operator documentation.

## Container rules

- Pin upstream versions and SHA-256 hashes. Do not use `latest` in scripts or documentation.
- Keep compiler dependencies in build stages and copy only runtime outputs into final images.
- Build and test this image as `linux/arm64`; do not add another platform to a manifest until it has its own native verification.
- Keep stdout usable by scripts and send diagnostics to stderr.

## Tracker and status

Use GitHub Issues for planned work and status. Do not maintain a separate status document.

## Verification boundary

Image checks prove the Linux ARM64 base and Wine runtime. They do not prove that Firefox builds, packages, installs, launches, signs, or updates. Record those results separately with the Firefox revision and artifact hashes.

<!-- bootstrap-project v1 · axes: other + infra-devops + cli · 2026-09-17 -->
