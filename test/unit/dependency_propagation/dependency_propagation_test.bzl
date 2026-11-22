"""Unit tests for dependency propagation in fortran_library."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//fortran:defs.bzl", "fortran_library")
load("//fortran/private:providers.bzl", "FortranInfo")

def _archive_names(target):
    # basenames of the static archives the target hands to a linker (via CcInfo)
    return [
        library.static_library.basename
        for linker_input in target[CcInfo].linking_context.linker_inputs.to_list()
        for library in linker_input.libraries
        if library.static_library != None
    ]

def _transitive_deps_propagate_test_impl(ctx):
    """Test that dependencies propagate transitively through the build graph.

    lib_a <- lib_b <- lib_c
    lib_c should have access to all libraries from lib_a and lib_b.
    """
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # archives of lib_a, lib_b, and lib_c itself
    names = _archive_names(target)
    for expected in ["liblib_a.a", "liblib_b.a", "liblib_c.a"]:
        asserts.true(env, expected in names, "Expected {} among {}".format(expected, names))

    return analysistest.end(env)

transitive_deps_propagate_test = analysistest.make(
    _transitive_deps_propagate_test_impl,
)

def _diamond_deps_deduplicate_test_impl(ctx):
    """Test that diamond dependencies are deduplicated.

    lib_d depends on lib_b and lib_c, both of which depend on lib_a.
    lib_a should not appear twice in lib_d's transitive deps.
    """

    # Picture:
    #     lib_d
    #    /     \
    # lib_b   lib_c
    #    \     /
    #     lib_a

    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check for duplicates by comparing list length to set length
    lib_paths = _archive_names(target)
    unique_paths = {path: True for path in lib_paths}
    asserts.true(env, "libdiamond_base.a" in lib_paths, "Expected libdiamond_base.a among {}".format(lib_paths))

    asserts.equals(
        env,
        len(lib_paths),
        len(unique_paths),
        "Diamond dependencies should be deduplicated (found {} libs, {} unique)".format(
            len(lib_paths),
            len(unique_paths),
        ),
    )

    # NOTE: dedup is guaranteed but the order (which comes first lib_b or lib_c) might not be

    return analysistest.end(env)

diamond_deps_deduplicate_test = analysistest.make(
    _diamond_deps_deduplicate_test_impl,
)

def _no_srcs_library_propagates_deps_test_impl(ctx):
    """Test that libraries with no srcs still propagate dependencies.

    This is the 'aggregator library' pattern - a library that just bundles deps.
    """
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Should still provide FortranInfo
    asserts.true(
        env,
        FortranInfo in target,
        "Library with no srcs must still provide FortranInfo",
    )

    # Should still provide CcInfo
    asserts.true(
        env,
        CcInfo in target,
        "Library with no srcs must still provide CcInfo",
    )

    # Should have libraries from deps even though it has no srcs
    names = _archive_names(target)
    for expected in ["liblib_a.a", "liblib_b.a"]:
        asserts.true(env, expected in names, "Library with no srcs should propagate {} (got {})".format(expected, names))

    return analysistest.end(env)

no_srcs_library_propagates_deps_test = analysistest.make(
    _no_srcs_library_propagates_deps_test_impl,
)

def dependency_propagation_test_suite(name):
    """Test suite for dependency propagation."""

    # Linear chain: lib_a <- lib_b <- lib_c
    fortran_library(
        name = "lib_a",
        srcs = ["lib_a.f90"],
        tags = ["manual"],
    )

    fortran_library(
        name = "lib_b",
        srcs = ["lib_b.f90"],
        deps = [":lib_a"],
        tags = ["manual"],
    )

    fortran_library(
        name = "lib_c",
        srcs = ["lib_c.f90"],
        deps = [":lib_b"],
        tags = ["manual"],
    )

    # Diamond pattern
    fortran_library(
        name = "diamond_base",
        srcs = ["diamond_base.f90"],
        tags = ["manual"],
    )

    fortran_library(
        name = "diamond_left",
        srcs = ["diamond_left.f90"],
        deps = [":diamond_base"],
        tags = ["manual"],
    )

    fortran_library(
        name = "diamond_right",
        srcs = ["diamond_right.f90"],
        deps = [":diamond_base"],
        tags = ["manual"],
    )

    fortran_library(
        name = "diamond_top",
        srcs = ["diamond_top.f90"],
        deps = [":diamond_left", ":diamond_right"],
        tags = ["manual"],
    )

    # Aggregator library (no srcs)
    fortran_library(
        name = "aggregator",
        deps = [":lib_a", ":lib_b"],
        tags = ["manual"],
    )

    # Create tests
    transitive_deps_propagate_test(
        name = "transitive_deps_propagate_test",
        target_under_test = ":lib_c",
    )

    diamond_deps_deduplicate_test(
        name = "diamond_deps_deduplicate_test",
        target_under_test = ":diamond_top",
    )

    no_srcs_library_propagates_deps_test(
        name = "no_srcs_library_propagates_deps_test",
        target_under_test = ":aggregator",
    )

    # Bundle into test suite
    native.test_suite(
        name = name,
        tests = [
            ":transitive_deps_propagate_test",
            ":diamond_deps_deduplicate_test",
            ":no_srcs_library_propagates_deps_test",
        ],
    )
