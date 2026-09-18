# Third-party notices

## Wine

The container build downloads Wine 11.10 from WineHQ, verifies its pinned
SHA-256 digest, applies `patches/wine-11.10-page-align.patch`, and builds it
from source. The image includes Wine's `LICENSE` and `COPYING.LIB` files.

The exact source URL and digest are declared in `docker/Dockerfile`.

## Microsoft components

This repository and its base image do not distribute Visual Studio, MSVC,
Windows SDK, MIDL, FXC, or related Microsoft binaries. The hydration command
downloads the versions pinned by the Firefox checkout after the operator
accepts the applicable terms. It stores them in a local Docker volume.
