# C/Fortran interop

Bidirectional interop between C and Fortran.

```
bazel test //interop:all --test_output=all
```

## fortran_calls_c

Fortran calling a C function via `iso_c_binding`.

```
 PASS: c_add_doubles(2.0, 3.0) = 5.0
```

## c_calls_fortran

C calling a Fortran function with `bind(C)`.

```
PASS: fortran_square(5.0) = 25.0
```

## c_calls_fortran_runtime

C calling Fortran subroutines that use runtime features (I/O, intrinsics, arrays, strings).

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

## full

LAPACKE client in C -- LU factorization of a 3x3 matrix.

```
OK
    3.00     0.33     0.67
    6.00     2.00     0.50
   10.00     3.67    -0.50
```
