"""Unit tests for the macOS SDK and minimum OS flags."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//fortran:defs.bzl", "fortran_binary", "fortran_library")
load("//test/unit:common.bzl", "assert_argv_contains")

_MACOS_ONLY = ["@platforms//os:macos"]

def _actions(env, mnemonic):
    return [a for a in analysistest.target_actions(env) if a.mnemonic == mnemonic]

def _assert_sdk_and_min_os(env, action, min_os):
    argv = action.argv
    assert_argv_contains(env, action, "-mmacosx-version-min=" + min_os)
    asserts.true(env, "-isysroot" in argv, "Expected -isysroot in {}".format(argv))
    if "-isysroot" in argv:
        sdk = argv[argv.index("-isysroot") + 1]
        asserts.true(env, sdk.startswith("/"), "Expected an absolute sdk path, got {}".format(sdk))
    asserts.equals(env, [], [a for a in argv if "syslibroot" in a], "Expected no hard-coded -syslibroot")

def _library_flags_test_impl(ctx):
    """Test that the module pass and each compile get the sdk and the minimum os."""
    env = analysistest.begin(ctx)
    for mnemonic in ["FortranModules", "FortranCompile"]:
        actions = _actions(env, mnemonic)
        asserts.true(env, len(actions) > 0, "Expected a {} action".format(mnemonic))
        for action in actions:
            _assert_sdk_and_min_os(env, action, "11.0")
    return analysistest.end(env)

library_flags_test = analysistest.make(
    _library_flags_test_impl,
    config_settings = {"//command_line_option:macos_minimum_os": "11.0"},
)

def _link_flags_test_impl(ctx):
    """Test that the link gets the sdk and the minimum os."""
    env = analysistest.begin(ctx)
    actions = _actions(env, "FortranLink")
    asserts.equals(env, 1, len(actions), "Expected one link action")
    _assert_sdk_and_min_os(env, actions[0], "11.0")
    return analysistest.end(env)

link_flags_test = analysistest.make(
    _link_flags_test_impl,
    config_settings = {"//command_line_option:macos_minimum_os": "11.0"},
)

def macos_test_suite(name):
    """Test suite for the macOS SDK and minimum OS flags.

    Args:
      name: name of the test suite.
    """

    # Scenario: a two-source library on macos
    # Given --macos_minimum_os=11.0
    # When the library is analyzed
    # Then its module pass and every compile get -isysroot <sdk> and -mmacosx-version-min=11.0
    fortran_library(
        name = "two_sources",
        srcs = ["user.f90", "kinds.f90"],
        tags = ["manual"],
    )
    library_flags_test(
        name = "library_flags_test",
        target_under_test = ":two_sources",
        target_compatible_with = _MACOS_ONLY,
    )

    # Scenario: a binary on macos
    # Given --macos_minimum_os=11.0
    # When the binary is analyzed
    # Then the link gets -isysroot <sdk> and -mmacosx-version-min=11.0, and no -syslibroot
    fortran_binary(
        name = "hello",
        srcs = ["hello.f90"],
        tags = ["manual"],
    )
    link_flags_test(
        name = "link_flags_test",
        target_under_test = ":hello",
        target_compatible_with = _MACOS_ONLY,
    )

    # Scenario: fortran and c built side by side
    # Given a fortran_binary and a cc_library built with default flags
    # When the minimum os and sdk recorded in each are read
    # Then they are the same, so linking them together gives no ld version warnings
    cc_library(
        name = "c_side",
        srcs = ["c_side.c"],
        tags = ["manual"],
    )
    sh_test(
        name = "build_version_test",
        srcs = ["build_version_test.sh"],
        args = ["$(rootpath :hello)", "$(rootpaths :c_side)"],
        data = [":hello", ":c_side"],
        target_compatible_with = _MACOS_ONLY,
    )

    native.test_suite(
        name = name,
        tests = [
            ":build_version_test",
            ":library_flags_test",
            ":link_flags_test",
        ],
    )
