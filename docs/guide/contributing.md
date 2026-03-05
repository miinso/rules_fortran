# Contributing

## Testing

### Unit Tests

Unit tests validate rule behavior using Bazel's analysis testing framework:

```bash
bazel test //test/unit/...
```

Test coverage includes:
- `fortran_library` and `fortran_binary` rules
- Module propagation via `FortranInfo`
- C/C++ interop via `CcInfo`
- Dependency propagation
- Edge cases and linking

### Integration Tests

The `examples/` directory is a separate Bazel module that imports `rules_fortran`. It serves as integration tests for real-world usage:

```bash
cd examples
bazel test //basic:all //blas:all //omp:all
bazel build //wasm:hello_wasm //wasm:full_wasm //wasm:omp_hello_wasm
```

### Test Coverage

- 27 unit tests (providers, module propagation, interop, edge cases)
- 9 BLAS tests -- from-source Netlib Level 1/2/3, all precisions (s/d/c/z)
- 97 LAPACK tests -- from-source Netlib LIN, EIG, DMD, mixed precision, RFP across all precisions ([5.2M individual test cases](https://github.com/miinso/rules_fortran/issues/20))
- wasm32 runtime tests (hello, LAPACK, OpenMP+pthreads)
- 10-platform CI matrix (5 OS x 2 Bazel versions)

## Running CI Locally

```bash
bazel test //test/... --verbose_failures --test_output=all
```
