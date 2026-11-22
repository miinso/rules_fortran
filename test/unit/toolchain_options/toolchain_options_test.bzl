"""Unit tests for fortran_toolchain options, using toolchains whose tools are never run."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:defs.bzl", "fortran_binary", "fortran_library")
load("//fortran:toolchain.bzl", "fortran_toolchain", "fortran_toolchain_alias")
load(
    "//test/unit:common.bzl",
    "assert_argv_contains",
    "assert_argv_contains_not",
    "assert_argv_contains_prefix",
    "assert_argv_contains_prefix_not",
)

_PACKAGE = "//test/unit/toolchain_options"

def _with_toolchain(name):
    return {"//command_line_option:extra_toolchains": [_PACKAGE + ":" + name]}

def _actions(env, mnemonic):
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == mnemonic]
    asserts.equals(env, 1, len(actions), "Expected exactly one {} action".format(mnemonic))
    return actions[0]

def _custom_compile_flags_test_impl(ctx):
    """Test that toolchain compile settings reach the compile action."""
    env = analysistest.begin(ctx)
    compile_action = _actions(env, "FortranCompile")

    assert_argv_contains(env, compile_action, "-custom-compile")
    assert_argv_contains(env, compile_action, "-fpp")
    assert_argv_contains_not(env, compile_action, "-cpp")
    assert_argv_contains(env, compile_action, "-DFROM_TOOLCHAIN")
    assert_argv_contains_prefix(env, compile_action, "-module=")
    assert_argv_contains_prefix_not(env, compile_action, "-J")

    return analysistest.end(env)

custom_compile_flags_test = analysistest.make(
    _custom_compile_flags_test_impl,
    config_settings = _with_toolchain("custom_toolchain"),
)

def _custom_link_flags_test_impl(ctx):
    """Test that toolchain linker_flags reach the link action."""
    env = analysistest.begin(ctx)
    assert_argv_contains(env, _actions(env, "FortranLink"), "-custom-link")
    return analysistest.end(env)

custom_link_flags_test = analysistest.make(
    _custom_link_flags_test_impl,
    config_settings = _with_toolchain("custom_toolchain"),
)

def _toolchain_alias_test_impl(ctx):
    """Test that fortran_toolchain_alias exposes the resolved toolchain's files."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "fake_tool.sh" in files, "Expected fake_tool.sh in {}".format(files))

    return analysistest.end(env)

toolchain_alias_test = analysistest.make(
    _toolchain_alias_test_impl,
    config_settings = _with_toolchain("custom_toolchain"),
)

def toolchain_options_test_suite(name):
    """Test suite for fortran_toolchain options.

    Args:
      name: name of the test suite.
    """

    # a toolchain with every option set away from its default, and no runtime libraries
    fortran_toolchain(
        name = "custom_toolchain_impl",
        archiver = "fake_tool.sh",
        compiler = "fake_tool.sh",
        compiler_flags = ["-custom-compile"],
        linker = "fake_tool.sh",
        linker_flags = ["-custom-link"],
        module_flag_format = "-module={}",
        preprocessor_flag = "-fpp",
        preprocessor_flags = ["-DFROM_TOOLCHAIN"],
        tags = ["manual"],
    )

    native.toolchain(
        name = "custom_toolchain",
        toolchain = ":custom_toolchain_impl",
        toolchain_type = "//fortran:toolchain_type",
        tags = ["manual"],
    )

    fortran_library(
        name = "dep",
        srcs = ["dep.f90"],
        tags = ["manual"],
    )

    fortran_library(
        name = "preprocessed_lib",
        srcs = ["preprocessed.F90"],
        deps = [":dep"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin",
        srcs = ["main.f90"],
        tags = ["manual"],
    )

    fortran_toolchain_alias(
        name = "current_toolchain",
        tags = ["manual"],
    )

    # Scenario: toolchain compile settings reach the compiler
    # Given a toolchain with its own compiler flags, preprocessor flag and module flag format
    # When a preprocessed source is compiled with it
    # Then the compile line uses those and not the defaults
    custom_compile_flags_test(
        name = "custom_compile_flags_test",
        target_under_test = ":preprocessed_lib",
    )

    # Scenario: toolchain link flags reach the linker
    # Given a toolchain with linker_flags
    # When a binary is linked with it
    # Then the link line carries them
    custom_link_flags_test(
        name = "custom_link_flags_test",
        target_under_test = ":bin",
    )

    # Scenario: the toolchain alias follows toolchain resolution
    # Given a fortran_toolchain_alias
    # When a custom toolchain is selected
    # Then the alias exposes that toolchain's tools
    toolchain_alias_test(
        name = "toolchain_alias_test",
        target_under_test = ":current_toolchain",
    )

    native.test_suite(
        name = name,
        tests = [
            ":custom_compile_flags_test",
            ":custom_link_flags_test",
            ":toolchain_alias_test",
        ],
    )
