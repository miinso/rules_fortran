"""Unit tests for fortran_test: its attributes must behave as they do on fortran_binary."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:defs.bzl", "fortran_test")
load("//test/unit:common.bzl", "assert_argv_contains")

def _test_attrs_reach_actions_test_impl(ctx):
    """Test that fortran_test attributes reach its compile and link actions."""
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    compile_actions = [a for a in actions if a.mnemonic == "FortranCompile"]
    asserts.equals(env, 1, len(compile_actions), "Expected exactly one FortranCompile action")
    assert_argv_contains(env, compile_actions[0], "-O3")
    assert_argv_contains(env, compile_actions[0], "-DEXPECTED_DEFINE")
    assert_argv_contains(env, compile_actions[0], "-Itest/unit/test_rule/include")

    inputs = [f.basename for f in compile_actions[0].inputs.to_list()]
    asserts.true(env, "consts.inc" in inputs, "Expected consts.inc in compile inputs")

    link_actions = [a for a in actions if a.mnemonic == "FortranLinkTest"]
    asserts.equals(env, 1, len(link_actions), "Expected exactly one FortranLinkTest action")
    assert_argv_contains(env, link_actions[0], "-lrules_fortran_test_marker")

    return analysistest.end(env)

test_attrs_reach_actions_test = analysistest.make(_test_attrs_reach_actions_test_impl)

def test_rule_test_suite(name):
    """Test suite for the fortran_test rule.

    Args:
      name: name of the test suite.
    """

    # Scenario: fortran_test attributes reach its actions
    # Given a fortran_test with copts, defines, includes, hdrs and linkopts
    # When its actions are created
    # Then the compile line has the copts, the define and the include path
    # And the header is a compile input
    # And the link line has the linkopts
    fortran_test(
        name = "test_with_attrs",
        srcs = ["main.F90"],
        hdrs = ["include/consts.inc"],
        copts = ["-O3"],
        defines = ["EXPECTED_DEFINE"],
        includes = ["include"],
        linkopts = ["-lrules_fortran_test_marker"],
        tags = ["manual"],
    )

    test_attrs_reach_actions_test(
        name = "test_attrs_reach_actions_test",
        target_under_test = ":test_with_attrs",
    )

    native.test_suite(
        name = name,
        tests = [":test_attrs_reach_actions_test"],
    )
