# OpenMP

Source: [`examples/omp/`](https://github.com/miinso/rules_fortran/tree/master/examples/omp)

Link against [`@libomp`](https://github.com/miinso/omp) for OpenMP support.

## Prerequisites

Add libomp to your `MODULE.bazel`:

```starlark
bazel_dep(name = "libomp", version = "21.1.8")
```

## 4.A. Hello OpenMP

```
omp/
├── BUILD.bazel
└── hello_omp.f90
```

<<< @/../examples/omp/hello_omp.f90{fortran}

```starlark
fortran_test(
    name = "hello_omp",
    srcs = ["hello_omp.f90"],
    copts = ["-fopenmp"],
    deps = ["@libomp"],
)
```

```bash
bazel test //omp:hello_omp --test_output=all
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
