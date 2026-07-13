#!/usr/bin/env bash

set -euo pipefail

cat > arithmetic.f90 << 'EOF'
module arithmetic
  implicit none
  private

  public :: add

contains

  pure integer function add(a, b) result(value)
    integer, intent(in) :: a
    integer, intent(in) :: b

    value = a + b
  end function add

end module arithmetic
EOF

cat > calculator.f90 << 'EOF'
module calculator
  use arithmetic, only: add
  implicit none
  private

  public :: answer

contains

  pure integer function answer() result(value)
    value = add(20, 22)
  end function answer

end module calculator
EOF

cat > calculator_test.f90 << 'EOF'
program calculator_test
  use calculator, only: answer
  implicit none

  if (answer() /= 42) then
    write (*, *) "FAIL: expected 42, got", answer()
    stop 1
  end if
end program calculator_test
EOF

cat > BUILD.bazel << 'EOF'
load(
    "@rules_fortran//fortran:defs.bzl",
    "fortran_library",
    "fortran_test",
)

fortran_library(
    name = "arithmetic",
    srcs = ["arithmetic.f90"],
)

fortran_library(
    name = "calculator",
    srcs = ["calculator.f90"],
    deps = [":arithmetic"],
)

fortran_test(
    name = "calculator_test",
    srcs = ["calculator_test.f90"],
    deps = [":calculator"],
)
EOF

bazel build //... --verbose_failures
bazel test //... --verbose_failures --test_output=errors
