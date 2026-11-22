"""Unit tests for sources of one target that use each other's modules."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//fortran:defs.bzl", "FortranInfo", "fortran_library", "fortran_test")

def _count(env, mnemonic):
    return len([a for a in analysistest.target_actions(env) if a.mnemonic == mnemonic])

def _module_pass_actions_test_impl(ctx):
    """Test that a target with several sources orders and builds its modules once."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(env, 1, _count(env, "FortranModuleOrder"), "Expected one scan of the sources")
    asserts.equals(env, 1, _count(env, "FortranModules"), "Expected one module pass")
    asserts.equals(env, 3, _count(env, "FortranCompile"), "Expected one compile per source")

    modules = target[FortranInfo].transitive_modules.to_list()
    asserts.equals(env, 1, len(modules), "Dependents should get one module directory for the whole target")

    return analysistest.end(env)

module_pass_actions_test = analysistest.make(_module_pass_actions_test_impl)

def _no_module_pass_for_one_source_test_impl(ctx):
    """Test that a single-source target is compiled directly."""
    env = analysistest.begin(ctx)

    asserts.equals(env, 0, _count(env, "FortranModuleOrder"), "A single source needs no ordering")
    asserts.equals(env, 0, _count(env, "FortranModules"), "A single source needs no module pass")
    asserts.equals(env, 1, _count(env, "FortranCompile"))

    return analysistest.end(env)

no_module_pass_for_one_source_test = analysistest.make(_no_module_pass_for_one_source_test_impl)

def intra_target_modules_test_suite(name):
    """Test suite for modules shared between the sources of one target.

    Args:
      name: name of the test suite.
    """

    # srcs listed against their dependency order on purpose
    fortran_library(
        name = "solver",
        srcs = [
            "solver_sub.f90",
            "solver.f90",
            "types.f90",
        ],
        tags = ["manual"],
    )

    # Scenario: a library's sources use each other's modules
    # Given a fortran_library with a module, a module that uses it and a submodule
    # And the sources listed in the reverse of their dependency order
    # When a program linking the library is built and run
    # Then it compiles and returns the value computed through all three
    fortran_test(
        name = "library_sources_use_each_other_test",
        srcs = ["main.f90"],
        deps = [":solver"],
    )

    # Scenario: a program and its modules in one target
    # Given a fortran_test whose srcs hold the program and every module it uses
    # When it is built and run
    # Then the program sees the modules of its sibling sources
    fortran_test(
        name = "program_and_modules_in_one_target_test",
        srcs = [
            "main.f90",
            "solver_sub.f90",
            "solver.f90",
            "types.f90",
        ],
    )

    # Scenario: fixed form, free form and preprocessed sources together
    # Given a target mixing a .f source, a .F90 module with a define and a .f90 module
    # And each using a module from one of the others
    # When it is built and run
    # Then every source is read in its own form and the define reaches the .F90 module
    fortran_test(
        name = "mixed_source_forms_use_each_other_test",
        srcs = [
            "mixed_main.f90",
            "legacy.f",
            "scaled.F90",
            "types.f90",
        ],
        defines = ["SCALE=3"],
    )

    # Scenario: modules of a target are built once, up front
    # Given a fortran_library with three sources
    # When its actions are created
    # Then there is one scan, one module pass and one compile per source
    # And dependents receive a single module directory
    module_pass_actions_test(
        name = "module_pass_actions_test",
        target_under_test = ":solver",
    )

    fortran_library(
        name = "single",
        srcs = ["single.f90"],
        tags = ["manual"],
    )

    # Scenario: a single source skips the module pass
    # Given a fortran_library with one source
    # When its actions are created
    # Then there is no scan and no module pass, only the compile
    no_module_pass_for_one_source_test(
        name = "no_module_pass_for_one_source_test",
        target_under_test = ":single",
    )

    native.test_suite(
        name = name,
        tests = [
            ":library_sources_use_each_other_test",
            ":mixed_source_forms_use_each_other_test",
            ":module_pass_actions_test",
            ":no_module_pass_for_one_source_test",
            ":program_and_modules_in_one_target_test",
        ],
    )
