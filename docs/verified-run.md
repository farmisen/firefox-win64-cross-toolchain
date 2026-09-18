# Verified Firefox cross-build

This record captures the successful experiment that established the repository's
initial toolchain design. It is evidence for that source revision, not a promise
that every later Firefox revision will build unchanged.

## Environment

- Host architecture: Apple Silicon using a native `linux/arm64` Docker VM
- Container distribution: Debian Bookworm ARM64
- Firefox Enterprise revision: `d09ed62da3ece870611d1928b4828e3b46bc9e66`
- Target: `x86_64-pc-windows-msvc`
- Wine: native ARM64 Wine 11.10 with `wine-11.10-page-align.patch`
- Assembler: Microsoft ARM64-hosted, x64-targeting `ml64.exe` 14.51.36231

Mozilla's ARM64 Linux `clang-cl`, Rust, Node, cbindgen, `dump_syms`, MIDL,
FXC, and Microsoft assembler components all ran on the ARM64 host. The output
executables were Windows x86-64 COFF files.

## Results

```text
[packages] PASS
[native-tools] PASS
[configure] PASS
[configure-check] PASS
[build] PASS
[build-check] PASS
[package] PASS
[artifacts] PASS
RESULT=FIREFOX_ARM64_NATIVE_RUN_PASS
```

The build produced:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `firefox-157.0a1.en-US.win64.installer.exe` | 88 MB | `f74a4cf2a406a2169a3e376c76fec1d618f1fb253dcf3820032be05fd5eb1138` |
| `firefox-157.0a1.en-US.win64.zip` | 133 MB | `e1508e85379179e14971da0dc7a2dbbcb07856303245396a9fc3dc2e4ac98ff8` |

The build and packaging checks do not prove Windows installation, launch,
signing, update behavior, or release suitability.
