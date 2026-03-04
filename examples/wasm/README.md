# wasm32 cross-compilation examples

Fortran -> wasm32 via emsdk + rules_fortran.

## build

```
cd examples && bazel build //wasm:hello_wasm //wasm:full_wasm //wasm:omp_hello_wasm
```

## hello

```
$ node bazel-bin/wasm/hello_cc.js
 Hello from wasm32 with rules_fortran!
```

## full

Links against blas, lapack, and lapacke (single precision). Solves a 3x3 linear system with DGESV.

```
$ node bazel-bin/wasm/full.js
OK
    3.00     0.33     0.67
    6.00     2.00     0.50
   10.00     3.67    -0.50
```

## omp_hello

OpenMP parallel region with emscripten pthreads.

```
$ node bazel-bin/wasm/omp_hello_cc.js
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
