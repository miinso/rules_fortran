"""Implementation of fortran_binary rule."""

load(":executable.bzl", "EXECUTABLE_ATTRS", "fortran_executable_impl")

def _fortran_binary_impl(ctx):
    return fortran_executable_impl(ctx, mnemonic = "FortranLink", kind = "binary")

fortran_binary = rule(
    implementation = _fortran_binary_impl,
    doc = """Compiles and links Fortran sources into an executable.

    This rule compiles Fortran source files and links them with
    dependencies into an executable binary.

    Example:
        fortran_binary(
            name = "myapp",
            srcs = ["main.f90"],
            deps = [":mylib"],
            linkopts = ["-llapack"],
        )
    """,
    attrs = EXECUTABLE_ATTRS,
    executable = True,
    toolchains = ["@rules_fortran//fortran:toolchain_type"],
)
