# rules_fortran

Fortran rules for Bazel using LLVM Flang.

Builds libraries, binaries, and tests. Cross-compiles to WebAssembly.
Works with C/Fortran interop, from-source BLAS/LAPACK, and OpenMP.

[Documentation](https://miinso.github.io/rules_fortran/) -- [Examples](https://github.com/miinso/rules_fortran/tree/master/examples)

## Platforms

| Host | Native target | Cross-compilation |
|------|---------------|-------------------|
| Linux x86_64 | x86_64-unknown-linux-gnu | wasm32-unknown-emscripten |
| Linux ARM64 | aarch64-unknown-linux-gnu | wasm32-unknown-emscripten |
| macOS x86_64 | x86_64-apple-darwin | wasm32-unknown-emscripten |
| macOS ARM64 | arm64-apple-darwin | wasm32-unknown-emscripten |
| Windows x86_64 | x86_64-pc-windows-msvc | wasm32-unknown-emscripten |

## Setup

Add to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_fortran")
git_override(
    module_name = "rules_fortran",
    remote = "https://github.com/miinso/rules_fortran.git",
    commit = "...",  # see releases
)
```

## Usage

```starlark
load("@rules_fortran//fortran:defs.bzl", "fortran_binary", "fortran_library", "fortran_test")

fortran_library(
    name = "mylib",
    srcs = ["mylib.f90"],
)

fortran_binary(
    name = "myapp",
    srcs = ["main.f90"],
    deps = [":mylib"],
)

fortran_test(
    name = "mytest",
    srcs = ["test.f90"],
    deps = [":mylib"],
)
```

### C interop

Fortran and C targets can depend on each other directly:

```starlark
fortran_library(name = "fortran_math", srcs = ["math.f90"])
cc_binary(name = "app", srcs = ["main.c"], deps = [":fortran_math"])
```

### OpenMP

```starlark
fortran_test(
    name = "hello_omp",
    srcs = ["hello_omp.f90"],
    copts = ["-fopenmp"],
    deps = ["@libomp"],
)
```

### WebAssembly

Cross-compile to wasm32 with Emscripten:

```starlark
fortran_library(name = "hello", srcs = ["hello.f90"])
cc_binary(name = "hello_cc", deps = [":hello"])
wasm_cc_binary(name = "hello_wasm", cc_target = ":hello_cc")
```

See [examples/](https://github.com/miinso/rules_fortran/tree/master/examples) for BLAS/LAPACK, OpenMP+wasm, and more.
