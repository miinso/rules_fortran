# Basic

Source: [`examples/basic/`](https://github.com/miinso/rules_fortran/tree/master/examples/basic)

Hello world, libraries with module dependencies, and include files.

## 1.A. Hello World

```
basic/
├── BUILD.bazel
└── hello.f90
```

<<< @/../examples/basic/hello.f90{fortran}

```starlark
fortran_test(
    name = "hello",
    srcs = ["hello.f90"],
)
```

```bash
bazel test //basic:hello --test_output=all
```

```
Hello from Fortran with rules_fortran!
```

## 1.B. Libraries and Modules

```
basic/
├── BUILD.bazel
├── main.f90
├── math_module.f90
├── statistics.f90
└── io_module.f90
```

<<< @/../examples/basic/math_module.f90{fortran}

<<< @/../examples/basic/statistics.f90{fortran}

<<< @/../examples/basic/main.f90{fortran}

```starlark
fortran_library(
    name = "math_lib",
    srcs = [
        "math_module.f90",
        "statistics.f90",
    ],
)

fortran_library(
    name = "io_lib",
    srcs = ["io_module.f90"],
)

fortran_test(
    name = "app",
    srcs = ["main.f90"],
    deps = [
        ":io_lib",
        ":math_lib",
    ],
)
```

```bash
bazel test //basic:app --test_output=all
```

```
 Factorial of 5 = 120
 Fibonacci of 5 = 5
 GCD(48, 18) = 6
 Mean: 5.5
 Std Dev: 2.8722813
 Scientific app completed!
```

## 1.C. Include Files

```
basic/
├── BUILD.bazel
├── include/
│   └── constants.inc
└── use_include.f90
```

<<< @/../examples/basic/include/constants.inc{fortran}

<<< @/../examples/basic/use_include.f90{fortran}

```starlark
fortran_test(
    name = "constants",
    srcs = ["use_include.f90"],
    hdrs = ["include/constants.inc"],
    includes = ["include"],
)
```

```bash
bazel test //basic:constants --test_output=all
```

```
PI = 3.1415927
E = 2.7182817
MAX_ITERATIONS = 1000
PASSED
```
