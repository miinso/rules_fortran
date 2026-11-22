"""A fortran_binary without the module scanner, to build the scanner itself.

fortran_library, fortran_binary and fortran_test depend on
//fortran/private/tools:module_order. That tool is a Fortran program, so
building it with fortran_binary would make it depend on itself. This rule is
the same implementation minus that one attribute; it compiles each source on
its own, which is all a single-source tool needs.
"""

load(":executable.bzl", "EXECUTABLE_ATTRS", "fortran_executable_impl")

def _fortran_bootstrap_binary_impl(ctx):
    return fortran_executable_impl(ctx, mnemonic = "FortranLink", kind = "binary")

fortran_bootstrap_binary = rule(
    implementation = _fortran_bootstrap_binary_impl,
    doc = "Internal. Builds the Fortran tools the other rules depend on.",
    attrs = EXECUTABLE_ATTRS,
    executable = True,
    toolchains = ["@rules_fortran//fortran:toolchain_type"],
)
