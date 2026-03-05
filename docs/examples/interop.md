# Interop

Source: [`examples/interop/`](https://github.com/miinso/rules_fortran/tree/master/examples/interop)

`fortran_library` provides `CcInfo`, enabling bidirectional linking between Fortran and C/C++ targets.

## 2.A. Fortran Calls C

```
interop/
├── BUILD.bazel
├── c_math.c
├── c_math.h
└── fortran_calls_c.f90
```

<<< @/../examples/interop/c_math.h{c}

<<< @/../examples/interop/c_math.c{c}

<<< @/../examples/interop/fortran_calls_c.f90{fortran}

```starlark
cc_library(
    name = "c_math",
    srcs = ["c_math.c"],
    hdrs = ["c_math.h"],
)

fortran_test(
    name = "fortran_calls_c",
    srcs = ["fortran_calls_c.f90"],
    deps = [":c_math"],
)
```

```bash
bazel test //interop:fortran_calls_c --test_output=all
```

```
PASS: c_add_doubles(2.0, 3.0) = 5.0
```

## 2.B. C Calls Fortran

```
interop/
├── BUILD.bazel
├── c_calls_fortran.c
└── fortran_math.f90
```

<<< @/../examples/interop/fortran_math.f90{fortran}

<<< @/../examples/interop/c_calls_fortran.c{c}

```starlark
fortran_library(
    name = "fortran_math",
    srcs = ["fortran_math.f90"],
)

cc_test(
    name = "c_calls_fortran",
    srcs = ["c_calls_fortran.c"],
    deps = [":fortran_math"],
)
```

```bash
bazel test //interop:c_calls_fortran --test_output=all
```

```
PASS: fortran_square(5.0) = 25.0
```

## 2.C. Fortran Runtime Features

C calling Fortran subroutines that use runtime features -- I/O, intrinsics, dynamic arrays, formatted output, strings.

```
interop/
├── BUILD.bazel
├── c_calls_fortran_runtime.c
└── fortran_runtime_features.f90
```

<<< @/../examples/interop/fortran_runtime_features.f90{fortran}

<<< @/../examples/interop/c_calls_fortran_runtime.c{c}

```starlark
fortran_library(
    name = "fortran_runtime_features",
    srcs = ["fortran_runtime_features.f90"],
)

cc_test(
    name = "c_calls_fortran_runtime",
    srcs = ["c_calls_fortran_runtime.c"],
    deps = [":fortran_runtime_features"],
)
```

```bash
bazel test //interop:c_calls_fortran_runtime --test_output=all
```

```
Test 1: Fortran I/O
PASS: test_io(42.0) = 84.0

Test 2: Fortran intrinsic functions (sqrt, exp, log, sin, cos)
PASS: test_intrinsics(4.0) returned finite value 0.614300

Test 3: Dynamic array allocation and operations
PASS: test_array_ops(10) = 38.500000

Test 4: Formatted I/O
PASS: test_formatted_io = 5.859870

Test 5: String operations
PASS: test_string_ops = 11

Test 6: Runtime checks (positive value)
PASS: test_runtime_checks(16.0) = 4.0

Test 7: Runtime checks (negative value)
PASS: test_runtime_checks(-5.0) = 0.0
```

## 2.D. LAPACKE from C

Pure C client using LAPACKE to call LAPACK routines (LU factorization). Requires `@blas`, `@lapack`, and `@lapacke` repos -- see [`examples/MODULE.bazel`](https://github.com/miinso/rules_fortran/tree/master/examples/MODULE.bazel).

```
interop/
├── BUILD.bazel
└── full.c
```

<<< @/../examples/interop/full.c{c}

```starlark
cc_test(
    name = "full",
    srcs = ["full.c"],
    deps = [
        "@blas//:single",
        "@lapack//:single",
        "@lapacke//:single",
    ],
)
```

```bash
bazel test //interop:full --test_output=all
```

```
OK
    3.00     0.33     0.67
    6.00     2.00     0.50
   10.00     3.67    -0.50
```
