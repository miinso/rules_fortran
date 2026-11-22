"""Implementation of fortran_test rule."""

load(":executable.bzl", "EXECUTABLE_ATTRS", "TEST_ONLY_ATTRS", "fortran_executable_impl")

def _fortran_test_impl(ctx):
    return fortran_executable_impl(ctx, mnemonic = "FortranLinkTest", kind = "test")

fortran_test = rule(
    implementation = _fortran_test_impl,
    doc = """Compiles and links Fortran sources into a test executable.

    This rule is similar to fortran_binary but is used for test targets.
    The resulting executable will be run as part of `bazel test`.

    Example:
        fortran_test(
            name = "mytest",
            srcs = ["test.f90"],
            deps = [":mylib"],
        )
    """,
    attrs = EXECUTABLE_ATTRS | TEST_ONLY_ATTRS,
    test = True,
    toolchains = ["@rules_fortran//fortran:toolchain_type"],
)
