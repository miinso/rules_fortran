"""Unit tests for linking behavior."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//fortran:defs.bzl", "fortran_binary", "fortran_library")

# a flag no toolchain adds by itself (linux/macos toolchains already pass
# -lpthread, which made presence checks vacuous there)
_LINKOPT = "-lrules_fortran_test_marker"

def _linkopts_propagate_to_binary_test_impl(ctx):
    """Test that linkopts from library propagate to binary link action."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    link_actions = [a for a in actions if "Link" in a.mnemonic]

    asserts.true(
        env,
        len(link_actions) > 0,
        "Expected at least one link action",
    )

    # Check that linkopts appear in link action
    link_action = link_actions[0]
    action_str = str(link_action.argv)

    has_linkopt = _LINKOPT in action_str

    asserts.true(
        env,
        has_linkopt,
        "Expected linkopts from library to appear in binary link action",
    )

    return analysistest.end(env)

linkopts_propagate_to_binary_test = analysistest.make(
    _linkopts_propagate_to_binary_test_impl,
)

def _linkopts_appear_once_test_impl(ctx):
    """Test that a linkopt reached through several paths is passed to the linker once."""
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    link_actions = [a for a in actions if "Link" in a.mnemonic]
    asserts.true(env, len(link_actions) > 0, "Expected at least one link action")

    count = len([arg for arg in link_actions[0].argv if arg == _LINKOPT])
    asserts.equals(env, 1, count, "Expected {} exactly once in link action".format(_LINKOPT))

    return analysistest.end(env)

linkopts_appear_once_test = analysistest.make(
    _linkopts_appear_once_test_impl,
)

def _linkopts_in_ccinfo_test_impl(ctx):
    """Test that fortran_library linkopts are carried by CcInfo, so cc rules see them too."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    flags = []
    for linker_input in target[CcInfo].linking_context.linker_inputs.to_list():
        flags.extend(linker_input.user_link_flags)

    asserts.true(env, _LINKOPT in flags, "Expected {} in CcInfo user_link_flags".format(_LINKOPT))

    return analysistest.end(env)

linkopts_in_ccinfo_test = analysistest.make(
    _linkopts_in_ccinfo_test_impl,
)

def _transitive_libs_linked_test_impl(ctx):
    """Test that transitive libraries are included in link action."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    link_actions = [a for a in actions if "Link" in a.mnemonic]

    asserts.true(
        env,
        len(link_actions) > 0,
        "Expected at least one link action",
    )

    # Check that transitive library appears in link inputs
    link_action = link_actions[0]
    action_str = str(link_action.argv)

    # Should have references to both direct and transitive libs
    has_lib_refs = "lib" in action_str and ".a" in action_str

    asserts.true(
        env,
        has_lib_refs,
        "Expected transitive libraries in link action",
    )

    return analysistest.end(env)

transitive_libs_linked_test = analysistest.make(
    _transitive_libs_linked_test_impl,
)

def linking_test_suite(name):
    """Test suite for linking behavior."""

    # Library with linkopts
    fortran_library(
        name = "lib_with_linkopts",
        srcs = ["lib.f90"],
        linkopts = [_LINKOPT],
        tags = ["manual"],
    )

    # Binary using library with linkopts
    fortran_binary(
        name = "bin_with_linkopts",
        srcs = ["main.f90"],
        deps = [":lib_with_linkopts"],
        tags = ["manual"],
    )

    # linkopts one level down: bin -> lib -> lib_with_linkopts
    fortran_library(
        name = "lib_over_linkopts",
        srcs = ["base.f90"],
        deps = [":lib_with_linkopts"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_transitive_linkopts",
        srcs = ["main.f90"],
        deps = [":lib_over_linkopts"],
        tags = ["manual"],
    )

    # linkopts behind a no-srcs aggregator
    fortran_library(
        name = "aggregator_over_linkopts",
        deps = [":lib_with_linkopts"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_aggregated_linkopts",
        srcs = ["main.f90"],
        deps = [":aggregator_over_linkopts"],
        tags = ["manual"],
    )

    # linkopts on a no-srcs library itself
    fortran_library(
        name = "linkopts_only",
        linkopts = [_LINKOPT],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_linkopts_only_dep",
        srcs = ["main.f90"],
        deps = [":linkopts_only"],
        tags = ["manual"],
    )

    # same linkopts reached directly and through two libs
    fortran_binary(
        name = "bin_with_diamond_linkopts",
        srcs = ["main.f90"],
        deps = [
            ":lib_over_linkopts",
            ":aggregator_over_linkopts",
            ":lib_with_linkopts",
        ],
        tags = ["manual"],
    )

    # Transitive chain for linking
    fortran_library(
        name = "base_lib",
        srcs = ["base.f90"],
        tags = ["manual"],
    )

    fortran_library(
        name = "middle_lib",
        srcs = ["middle.f90"],
        deps = [":base_lib"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_transitive",
        srcs = ["main.f90"],
        deps = [":middle_lib"],
        tags = ["manual"],
    )

    # Create tests
    linkopts_propagate_to_binary_test(
        name = "linkopts_propagate_to_binary_test",
        target_under_test = ":bin_with_linkopts",
    )

    transitive_libs_linked_test(
        name = "transitive_libs_linked_test",
        target_under_test = ":bin_with_transitive",
    )

    linkopts_propagate_to_binary_test(
        name = "transitive_linkopts_propagate_test",
        target_under_test = ":bin_with_transitive_linkopts",
    )

    linkopts_propagate_to_binary_test(
        name = "aggregated_linkopts_propagate_test",
        target_under_test = ":bin_with_aggregated_linkopts",
    )

    linkopts_propagate_to_binary_test(
        name = "linkopts_only_dep_propagate_test",
        target_under_test = ":bin_with_linkopts_only_dep",
    )

    linkopts_appear_once_test(
        name = "direct_linkopts_appear_once_test",
        target_under_test = ":bin_with_linkopts",
    )

    linkopts_appear_once_test(
        name = "diamond_linkopts_appear_once_test",
        target_under_test = ":bin_with_diamond_linkopts",
    )

    linkopts_in_ccinfo_test(
        name = "linkopts_in_ccinfo_test",
        target_under_test = ":lib_with_linkopts",
    )

    linkopts_in_ccinfo_test(
        name = "linkopts_only_in_ccinfo_test",
        target_under_test = ":linkopts_only",
    )

    # Bundle into test suite
    native.test_suite(
        name = name,
        tests = [
            ":transitive_linkopts_propagate_test",
            ":aggregated_linkopts_propagate_test",
            ":linkopts_only_dep_propagate_test",
            ":direct_linkopts_appear_once_test",
            ":diamond_linkopts_appear_once_test",
            ":linkopts_in_ccinfo_test",
            ":linkopts_only_in_ccinfo_test",
            ":linkopts_propagate_to_binary_test",
            ":transitive_libs_linked_test",
        ],
    )
