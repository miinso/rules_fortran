# Installation

## Requirements

- Bazel 7.0+
- Bzlmod enabled (default in Bazel 7+)

## Setup

Add to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_fortran")
git_override(
    module_name = "rules_fortran",
    remote = "https://github.com/miinso/rules_fortran.git",
    commit = "76c948c52ee3a735eb4670da885ef3907281c952",
)
```

The Flang toolchain registers automatically. No additional setup required.

::: info Flang Toolchain
rules_fortran downloads prebuilt LLVM Flang binaries from [miinso/flang-releases](https://github.com/miinso/flang-releases). It does not use any system-installed Fortran compiler. No `apt install gfortran`, no "works on my machine."
:::

## Supported Platforms

| Host | Target |
|------|--------|
| Linux x86_64 | x86_64-unknown-linux-gnu |
| Linux ARM64 | aarch64-unknown-linux-gnu |
| macOS x86_64 | x86_64-apple-darwin |
| macOS ARM64 | arm64-apple-darwin |
| Windows x86_64 | x86_64-pc-windows-msvc |

## WebAssembly Cross-Compilation

All host platforms can cross-compile to `wasm32-unknown-emscripten`.

Each Flang release includes `libflang_rt.runtime.wasm32.a`, the Fortran runtime library compiled for WebAssembly. Combined with [emsdk](https://github.com/emscripten-core/emsdk), you can compile Fortran code to run in browsers or Node.js.

See the [WebAssembly example](/examples/wasm) for details.

## WORKSPACE

Not supported. Use Bzlmod.
