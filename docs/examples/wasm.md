# WebAssembly

Source: [`examples/wasm/`](https://github.com/miinso/rules_fortran/tree/master/examples/wasm)

Cross-compile Fortran to WebAssembly using Emscripten.

## Prerequisites

Add emsdk to your `MODULE.bazel`:

```starlark
bazel_dep(name = "emsdk", version = "4.0.17")
```

## 3.A. Hello World

```
wasm/
├── BUILD.bazel
└── hello.f90
```

<<< @/../examples/wasm/hello.f90{fortran}

```starlark
fortran_library(
    name = "hello",
    srcs = ["hello.f90"],
)

cc_binary(
    name = "hello_cc",
    srcs = [],
    deps = [":hello"],
)

wasm_cc_binary(
    name = "hello_wasm",
    cc_target = ":hello_cc",
    outputs = ["hello_cc.js", "hello_cc.wasm"],
)
```

```bash
bazel build //wasm:hello_wasm
node bazel-bin/wasm/hello_cc.js
```

```
Hello from wasm32 with rules_fortran!
```

The `cc_binary` target works as a native executable. Wrapping it with `wasm_cc_binary` produces WebAssembly output instead.

## 3.B. LAPACK

```
wasm/
├── BUILD.bazel
└── full.c
```

<<< @/../examples/wasm/full.c{c}

```starlark
cc_binary(
    name = "full",
    srcs = ["full.c"],
    deps = [
        "@blas//:single",
        "@lapack//:single",
        "@lapacke//:single",
    ],
)

wasm_cc_binary(
    name = "full_wasm",
    cc_target = ":full",
    outputs = ["full.js", "full.wasm"],
)
```

```bash
bazel build //wasm:full_wasm
node bazel-bin/wasm/full.js
```

```
OK
    3.00     0.33     0.67
    6.00     2.00     0.50
   10.00     3.67    -0.50
```

## 3.C. OpenMP (pthreads)

OpenMP parallel region running in wasm32 with emscripten pthreads.

```
wasm/
├── BUILD.bazel
└── omp_hello.f90
```

<<< @/../examples/wasm/omp_hello.f90{fortran}

```starlark
fortran_library(
    name = "omp_hello",
    srcs = ["omp_hello.f90"],
    copts = ["-fopenmp", "-pthread"],
    deps = ["@libomp"],
)

cc_binary(
    name = "omp_hello_cc",
    srcs = [],
    linkopts = ["-pthread"],
    deps = [":omp_hello"],
)

wasm_cc_binary(
    name = "omp_hello_wasm",
    cc_target = ":omp_hello_cc",
    outputs = ["omp_hello_cc.js", "omp_hello_cc.wasm"],
    threads = "emscripten",
)
```

```bash
bazel build //wasm:omp_hello_wasm
node bazel-bin/wasm/omp_hello_cc.js
```

```
 thread 0 of 16
 thread 2 of 16
 thread 1 of 16
 thread 3 of 16
 thread 8 of 16
 thread 9 of 16
 thread 11 of 16
 thread 7 of 16
 thread 4 of 16
 thread 10 of 16
 thread 5 of 16
 thread 12 of 16
 thread 13 of 16
 thread 14 of 16
 thread 6 of 16
 thread 15 of 16
```
