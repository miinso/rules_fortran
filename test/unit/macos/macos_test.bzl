"""Unit tests for the macOS SDK and minimum OS flags."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//fortran:defs.bzl", "fortran_binary", "fortran_library")
load("//fortran:toolchain.bzl", "fortran_toolchain")
load("//fortran/private:macos.bzl", "macos_min_os_flags")
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

def _min_os_parse_test_impl(ctx):
    """Test reading the minimum macos version off cc command lines."""
    env = unittest.begin(ctx)
    cases = [
        # rules_cc local toolchain
        (["clang", "-mmacosx-version-min=26.5", "-c"], ["-mmacosx-version-min=26.5"]),
        (["-mmacos-version-min=13.0"], ["-mmacosx-version-min=13.0"]),
        # apple_support puts it in the triple
        (["-target", "arm64-apple-macosx15.0", "-c"], ["-mmacosx-version-min=15.0"]),
        (["--target=x86_64-apple-macos11.0"], ["-mmacosx-version-min=11.0"]),
        (["-target", "arm64-apple-macosx15.0.1"], ["-mmacosx-version-min=15.0.1"]),
        # the last one wins
        (["-mmacosx-version-min=26.5", "-target", "arm64-apple-macosx12.0"], ["-mmacosx-version-min=12.0"]),
        (["-target", "arm64-apple-macosx12.0", "-mmacosx-version-min=13.0"], ["-mmacosx-version-min=13.0"]),
        # nothing to read
        (["-target", "arm64-apple-darwin"], []),
        (["-target", "arm64-apple-macosx"], []),
        (["--target=wasm32-unknown-emscripten", "-O2"], []),
        (["-target"], []),
        ([], []),
    ]
    for argv, expected in cases:
        asserts.equals(env, expected, macos_min_os_flags(argv), "argv {}".format(argv))
    return unittest.end(env)

min_os_parse_test = unittest.make(_min_os_parse_test_impl)

def _copts_override_test_impl(ctx):
    """Test that copts / linkopts come after the cc minimum os, so they win."""
    env = analysistest.begin(ctx)
    for mnemonic, flag in [("FortranCompile", "-mmacosx-version-min=12.0"), ("FortranLink", "-mmacosx-version-min=12.0")]:
        for action in _actions(env, mnemonic):
            argv = action.argv
            asserts.true(env, flag in argv and "-mmacosx-version-min=11.0" in argv, "Expected both flags in {}".format(argv))
            if flag in argv and "-mmacosx-version-min=11.0" in argv:
                asserts.true(
                    env,
                    argv.index("-mmacosx-version-min=11.0") < argv.index(flag),
                    "Expected the user flag last in {}".format(argv),
                )
    return analysistest.end(env)

copts_override_test = analysistest.make(
    _copts_override_test_impl,
    config_settings = {"//command_line_option:macos_minimum_os": "11.0"},
)

def _opt_out_test_impl(ctx):
    """Test that macos_minimum_os_from_cc = False adds no minimum os."""
    env = analysistest.begin(ctx)
    for mnemonic in ["FortranCompile", "FortranLink"]:
        for action in _actions(env, mnemonic):
            asserts.equals(env, [], [a for a in action.argv if "version-min" in a], "Expected no minimum os")
    return analysistest.end(env)

opt_out_test = analysistest.make(
    _opt_out_test_impl,
    config_settings = {
        "//command_line_option:extra_toolchains": ["//test/unit/macos:no_min_os_toolchain"],
        "//command_line_option:macos_minimum_os": "11.0",
    },
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

    # Scenario: reading the minimum os off a cc command line
    # Given rules_cc style flags, apple_support style triples, or neither
    # When the minimum os is read
    # Then the last version given wins, and none gives no flag
    min_os_parse_test(name = "min_os_parse_test")

    # Scenario: the user picks a minimum os
    # Given --macos_minimum_os=11.0 and copts / linkopts with -mmacosx-version-min=12.0
    # When the binary is analyzed
    # Then the user flag comes after the toolchain one, so flang uses 12.0
    fortran_binary(
        name = "hello_12",
        srcs = ["hello.f90"],
        copts = ["-mmacosx-version-min=12.0"],
        linkopts = ["-mmacosx-version-min=12.0"],
        tags = ["manual"],
    )
    copts_override_test(
        name = "copts_override_test",
        target_under_test = ":hello_12",
        target_compatible_with = _MACOS_ONLY,
    )

    # Scenario: a compiler without -mmacosx-version-min
    # Given a toolchain with macos_minimum_os_from_cc = False
    # When a binary is analyzed on macos
    # Then no minimum os flag is added
    fortran_toolchain(
        name = "no_min_os_toolchain_impl",
        archiver = "fake_tool.sh",
        compiler = "fake_tool.sh",
        linker = "fake_tool.sh",
        macos_minimum_os_from_cc = False,
        tags = ["manual"],
    )
    native.toolchain(
        name = "no_min_os_toolchain",
        toolchain = ":no_min_os_toolchain_impl",
        toolchain_type = "//fortran:toolchain_type",
        tags = ["manual"],
    )
    opt_out_test(
        name = "opt_out_test",
        target_under_test = ":hello",
        target_compatible_with = _MACOS_ONLY,
    )

    native.test_suite(
        name = name,
        tests = [
            ":build_version_test",
            ":copts_override_test",
            ":min_os_parse_test",
            ":opt_out_test",
            ":library_flags_test",
            ":link_flags_test",
        ],
    )
