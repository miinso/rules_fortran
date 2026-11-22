"""Unit tests for what the executable rules put on the link line."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//fortran:defs.bzl", "fortran_binary", "fortran_library", "fortran_test")

_SHARED_LIB_EXTENSIONS = ["so", "dll", "dylib"]

_NOT_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

def _link_argv(env):
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic in ["FortranLink", "FortranLinkTest"]]
    asserts.equals(env, 1, len(actions), "Expected one link action")
    return actions[0].argv

def _cc_objects(argv, lib_name):
    # rules_cc puts a cc_library's objects under _objs/<name>/
    return [arg for arg in argv if "/_objs/{}/".format(lib_name) in arg]

def _cc_archive_without_objects_test_impl(ctx):
    """Test that a plain cc_library dep is linked as its archive only."""
    env = analysistest.begin(ctx)
    argv = _link_argv(env)

    asserts.equals(env, [], _cc_objects(argv, "plain_c"), "cc objects must not be passed next to their archive")
    asserts.true(
        env,
        len([arg for arg in argv if "plain_c" in arg]) == 1,
        "Expected the plain_c archive exactly once in {}".format(argv),
    )

    return analysistest.end(env)

cc_archive_without_objects_test = analysistest.make(_cc_archive_without_objects_test_impl)

def _alwayslink_objects_linked_test_impl(ctx):
    """Test that an alwayslink cc_library dep has every object on the link line."""
    env = analysistest.begin(ctx)
    argv = _link_argv(env)

    asserts.equals(env, 1, len(_cc_objects(argv, "always_c")), "Expected the always_c object in {}".format(argv))

    return analysistest.end(env)

alwayslink_objects_linked_test = analysistest.make(_alwayslink_objects_linked_test_impl)

def _no_shared_libs_in_runfiles_test_impl(ctx):
    """Test that statically linked deps do not put their shared library in runfiles."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    shared = [
        f.short_path
        for f in target[DefaultInfo].default_runfiles.files.to_list()
        if f.extension in _SHARED_LIB_EXTENSIONS
    ]
    asserts.equals(env, [], shared, "Unexpected shared libraries in runfiles")

    return analysistest.end(env)

no_shared_libs_in_runfiles_test = analysistest.make(_no_shared_libs_in_runfiles_test_impl)

def _fortran_archive_after_cc_dependent_test_impl(ctx):
    """Test that a fortran archive comes after the cc archive that needs it."""
    env = analysistest.begin(ctx)
    argv = _link_argv(env)

    glue = [i for i, arg in enumerate(argv) if "glue_c" in arg]
    base = [i for i, arg in enumerate(argv) if "glue_base" in arg]
    asserts.equals(env, 1, len(glue), "Expected the glue_c archive once in {}".format(argv))
    asserts.equals(env, 1, len(base), "Expected the glue_base archive once in {}".format(argv))
    if len(glue) == 1 and len(base) == 1:
        asserts.true(env, glue[0] < base[0], "glue_c must come before glue_base, which it depends on")

    return analysistest.end(env)

fortran_archive_after_cc_dependent_test = analysistest.make(_fortran_archive_after_cc_dependent_test_impl)

def _dep_runfiles_symlinks_kept_test_impl(ctx):
    """Test that runfiles symlinks of a dep survive into the binary's runfiles."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    paths = [s.path for s in target[DefaultInfo].default_runfiles.symlinks.to_list()]
    asserts.true(env, "link_inputs/alias.txt" in paths, "Expected the dep's runfiles symlink, got {}".format(paths))

    return analysistest.end(env)

dep_runfiles_symlinks_kept_test = analysistest.make(_dep_runfiles_symlinks_kept_test_impl)

def _whole_archive_test_impl(ctx):
    """Test that an alwayslink fortran_library is linked as a whole archive."""
    env = analysistest.begin(ctx)
    argv = _link_argv(env)

    # gnu ld / wasm-ld bracket the archive, macos and windows take it in one flag
    markers = ["--whole-archive", "-force_load", "/WHOLEARCHIVE:"]
    marked = [arg for arg in argv if len([m for m in markers if m in arg]) > 0]
    asserts.true(env, len(marked) > 0, "Expected a whole-archive flag in {}".format(argv))
    asserts.equals(env, 1, len([arg for arg in argv if "libblock_data.a" in arg]), "Expected the archive once")

    return analysistest.end(env)

whole_archive_test = analysistest.make(_whole_archive_test_impl)

def _executable_name_test_impl(ctx):
    """Test that the executable is named for the target platform."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    is_windows = ctx.target_platform_has_constraint(
        ctx.attr._windows_constraint[platform_common.ConstraintValueInfo],
    )
    expected = "bin_with_cc_deps" + (".exe" if is_windows else "")
    asserts.equals(env, expected, target[DefaultInfo].files_to_run.executable.basename)

    return analysistest.end(env)

executable_name_test = analysistest.make(
    _executable_name_test_impl,
    attrs = {"_windows_constraint": attr.label(default = Label("@platforms//os:windows"))},
)

def _symlink_dep_impl(ctx):
    # a linkable dep with nothing to link, whose runfiles hold a symlink
    return [
        CcInfo(),
        DefaultInfo(runfiles = ctx.runfiles(symlinks = {"link_inputs/alias.txt": ctx.file.target})),
    ]

_symlink_dep = rule(
    implementation = _symlink_dep_impl,
    attrs = {"target": attr.label(allow_single_file = True)},
)

def link_inputs_test_suite(name):
    """Test suite for link inputs.

    Args:
      name: name of the test suite.
    """

    cc_library(
        name = "plain_c",
        srcs = ["plain.c"],
        tags = ["manual"],
    )

    cc_library(
        name = "always_c",
        srcs = ["always.c"],
        alwayslink = True,
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_cc_deps",
        srcs = ["main.f90"],
        deps = [":plain_c", ":always_c"],
        tags = ["manual"],
    )

    # Scenario: a c library is linked once
    # Given a fortran_binary that depends on a plain cc_library
    # When the link line is built
    # Then the library's archive is on it
    # And the library's objects are not
    cc_archive_without_objects_test(
        name = "cc_archive_without_objects_test",
        target_under_test = ":bin_with_cc_deps",
    )

    # Scenario: alwayslink is honored
    # Given a fortran_binary that depends on a cc_library with alwayslink
    # When the link line is built
    # Then the library's objects are on it, referenced or not
    alwayslink_objects_linked_test(
        name = "alwayslink_objects_linked_test",
        target_under_test = ":bin_with_cc_deps",
    )

    # Scenario: static deps ship no shared library
    # Given a fortran_binary whose cc deps are linked statically
    # When its runfiles are collected
    # Then no shared library is among them
    no_shared_libs_in_runfiles_test(
        name = "no_shared_libs_in_runfiles_test",
        target_under_test = ":bin_with_cc_deps",
    )

    # Scenario: the executable is named for its platform
    # Given a fortran_binary
    # When it is built for windows
    # Then its file ends in .exe
    # And on any other platform it has no extension
    executable_name_test(
        name = "executable_name_test",
        target_under_test = ":bin_with_cc_deps",
    )

    fortran_library(
        name = "glue_base",
        srcs = ["base.f90"],
        tags = ["manual"],
    )

    cc_library(
        name = "glue_c",
        srcs = ["glue.c"],
        deps = [":glue_base"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_glue",
        srcs = ["glue_main.f90"],
        deps = [":glue_c", ":glue_base"],
        tags = ["manual"],
    )

    # Scenario: archives keep dependency order
    # Given c code that calls a fortran routine
    # And a fortran_binary that depends on both
    # When the link line is built
    # Then the c archive comes before the fortran archive it needs
    fortran_archive_after_cc_dependent_test(
        name = "fortran_archive_after_cc_dependent_test",
        target_under_test = ":bin_with_glue",
    )

    # Scenario: c glue that calls fortran links and runs
    # Given c code that calls a fortran routine the main program never names
    # When a fortran_test depending on both is built and run
    # Then it links with a single-pass linker and returns the fortran value
    fortran_test(
        name = "glue_calls_fortran_test",
        srcs = ["glue_main.f90"],
        deps = [":glue_c", ":glue_base"],
    )

    fortran_library(
        name = "block_data",
        srcs = ["block_data.f90"],
        alwayslink = True,
        tags = ["manual"],
    )

    # Scenario: a whole-archive link works on every platform
    # Given a fortran_library with alwayslink that only holds a BLOCK DATA unit
    # And a program that reads the COMMON block but never names that unit
    # When the program is built and run
    # Then the platform's linker accepts the whole-archive flag
    # And the COMMON block holds the initialized value
    fortran_test(
        name = "block_data_is_linked_test",
        srcs = ["block_data_main.f90"],
        deps = [":block_data"],
    )

    fortran_library(
        name = "unreferenced",
        srcs = ["unreferenced.f90"],
        alwayslink = True,
        tags = ["manual"],
    )

    cc_library(
        name = "weak_probe",
        srcs = ["weak_probe.c"],
        tags = ["manual"],
        target_compatible_with = ["@platforms//os:linux"],
    )

    # Scenario: alwayslink keeps an object nothing references
    # Given a fortran_library with alwayslink whose routine is only weakly referenced
    # When a program is built and run
    # Then the routine is in the binary and returns its value
    # (linux only: msvc has no weak references, and macos rejects undefined weak ones)
    fortran_test(
        name = "alwayslink_keeps_unreferenced_test",
        srcs = ["weak_probe_main.f90"],
        target_compatible_with = ["@platforms//os:linux"],
        deps = [":weak_probe", ":unreferenced"],
    )

    # Scenario: an alwayslink fortran library is linked whole
    # Given a fortran_test that depends on a fortran_library with alwayslink
    # When the link line is built
    # Then the archive is passed with the platform's whole-archive flag
    whole_archive_test(
        name = "whole_archive_test",
        target_under_test = ":block_data_is_linked_test",
    )

    # a library that exists only in shared form
    # macos: a dylib records its own load path, and the loader uses that, not
    # the rpath, unless it starts with @rpath. bazel 8+ sets it, 7.x does not
    cc_binary(
        name = "libshared_impl.so",
        srcs = ["shared.c"],
        linkopts = select({
            "@platforms//os:macos": ["-Wl,-install_name,@rpath/libshared_impl.so"],
            "//conditions:default": [],
        }),
        linkshared = True,
        tags = ["manual"],
        target_compatible_with = _NOT_WINDOWS,
    )

    cc_import(
        name = "shared_only",
        shared_library = ":libshared_impl.so",
        tags = ["manual"],
        target_compatible_with = _NOT_WINDOWS,
    )

    # Scenario: a shared-only dependency is found at run time
    # Given a dependency that provides nothing but a shared library
    # When a fortran_test linking it is built and run
    # Then the loader finds the library through the executable's rpath
    # (not on windows: a dll cannot be linked without its import library)
    fortran_test(
        name = "shared_only_dep_runs_test",
        srcs = ["shared_main.f90"],
        target_compatible_with = _NOT_WINDOWS,
        deps = [":shared_only"],
    )

    _symlink_dep(
        name = "symlink_dep",
        target = "payload.txt",
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_with_symlink_dep",
        srcs = ["main.f90"],
        deps = [":symlink_dep"],
        tags = ["manual"],
    )

    # Scenario: runfiles symlinks of deps are kept
    # Given a dep whose runfiles contain a symlink
    # When a fortran_binary depending on it collects runfiles
    # Then the symlink is among them
    dep_runfiles_symlinks_kept_test(
        name = "dep_runfiles_symlinks_kept_test",
        target_under_test = ":bin_with_symlink_dep",
    )

    native.test_suite(
        name = name,
        tests = [
            ":alwayslink_keeps_unreferenced_test",
            ":alwayslink_objects_linked_test",
            ":block_data_is_linked_test",
            ":whole_archive_test",
            ":cc_archive_without_objects_test",
            ":dep_runfiles_symlinks_kept_test",
            ":executable_name_test",
            ":fortran_archive_after_cc_dependent_test",
            ":glue_calls_fortran_test",
            ":no_shared_libs_in_runfiles_test",
            ":shared_only_dep_runs_test",
        ],
    )
