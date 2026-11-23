# Fortran Build Concepts

## Why This Exists

Fortran is the backbone of high-performance numerical computing -- LAPACK, BLAS, weather models, physics simulations. Integrating it into modern build systems has been painful.

Existing approaches tend to be Linux-only, GCC-based, or shell out to a system-installed compiler. The Bazel Central Registry has open requests for BLAS and LAPACK, blocked on the lack of a Fortran ruleset that can build them from source.

rules_fortran ships hermetic LLVM Flang toolchains for 5 platforms, handles module dependency ordering, and provides `CcInfo` for bidirectional C/Fortran interop.

## Fortran vs C/C++

Fortran has different compilation semantics than C/C++, which affects how build systems must handle it.

### Module Files

In C/C++, headers are textual includes processed by the preprocessor. In Fortran, `module` declarations compile to binary `.mod` files containing type signatures, interfaces, and metadata.

```fortran
module math        ! Compiles to math.mod
    implicit none
contains
    function add(a, b) result(c)
        real, intent(in) :: a, b
        real :: c
        c = a + b
    end function add
end module math
```

When another file says `use math`, the compiler reads `math.mod` to verify types and interfaces. This means:

1. **Modules must be compiled before their users** - strict build ordering required
2. **Module files are compiler-specific** - gfortran `.mod` files are incompatible with flang
3. **Module names are case-insensitive** - `USE MATH` and `use math` refer to the same module

### Dependency Ordering

Consider three files:

```
a.f90: module a (no dependencies)
b.f90: module b, uses a
c.f90: program c, uses a and b
```

Valid compilation order: `a.f90` → `b.f90` → `c.f90`

Invalid: `b.f90` first (needs `a.mod`), or `c.f90` first (needs both)

In C/C++, object files can be compiled in any order. In Fortran, sources must be compiled in dependency order.

## How rules_fortran Handles This

### Module Propagation

When one target depends on another, module files are propagated via `FortranInfo`:

```
a.f90: module a
b.f90: module b, uses a
c.f90: program c, uses a and b
```

```starlark
fortran_library(
    name = "a",
    srcs = ["a.f90"],
)

fortran_library(
    name = "b",
    srcs = ["b.f90"],
    deps = [":a"],
)

fortran_binary(
    name = "c",
    srcs = ["c.f90"],
    deps = [":a", ":b"],
)
```

The `deps` attribute makes all modules from dependencies available when compiling.

Unlike C/C++ headers which are just textual includes, Fortran modules are compiled artifacts. The build system must ensure modules are compiled before their users - this is handled automatically through `deps`.

### Modules Inside One Target

Sources of the same target can use each other's modules too, and the order of `srcs` does not matter:

```starlark
fortran_library(
    name = "solver",
    srcs = ["solver.f90", "types.f90"],  # solver.f90 has `use types`
)
```

For a target with more than one source, rules_fortran reads the `module`, `submodule` and `use` statements of each source, sorts the sources, and writes all of the target's module files in one step before compiling each source on its own. Continuation lines, comments and character strings are understood, in both source forms. Files pulled in with `INCLUDE` or `#include` are read as part of the including source when they are listed in `hdrs` (or `srcs`) and found next to it or in `includes`. Two sources of one target that use each other in a cycle, or that define the same module, are reported as an error; one included file that defines a module counts once, however many sources include it.

The preprocessor is not run: sources are read as written, so every branch of an `#if` or `#ifdef` counts. A `use` in an inactive branch still orders the sources, and can be reported as a cycle the compiler would never see. A `module` in an inactive branch still counts as defined, so a stub and a real module under `#ifdef`/`#ifndef` in two files are reported as defined twice. A `use` or module name built by a macro, or an `#include` whose file name comes from one, is not seen. In these cases, put the modules concerned in their own `fortran_library` and depend on it, or pick the sources with `select()`.

In fixed form, blanks inside a keyword or a name on one line (`MOD ULE A`) and text in Hollerith constants (`5Hx; y`) are not understood; write those statements the usual way.

### Prebuilt Libraries

A Fortran library that was built outside of Bazel comes as module files plus an archive or a shared library. `fortran_import` brings both into the build:

```starlark
fortran_import(
    name = "vendor",
    modules = glob(["include/*.mod"]),
    static_library = "lib/libvendor.a",
)

fortran_binary(
    name = "app",
    srcs = ["main.f90"],  # use vendor
    deps = [":vendor"],
)
```

Dependents use it like a `fortran_library`: its modules are visible to them and to whatever depends on them, and its library is linked.

Module files are not portable. A `.mod` file can only be read by the compiler that wrote it, usually only by the same version, so import module files written by the flang the toolchain uses.

### C Interoperability

rules_fortran provides `CcInfo` from `fortran_library`, enabling:

- `cc_binary` / `cc_library` / `cc_test` can depend on `fortran_library`
- `fortran_binary` / `fortran_library` / `fortran_test` can depend on `cc_library`

See the [C/Fortran Interop example](/examples/interop) for details.
