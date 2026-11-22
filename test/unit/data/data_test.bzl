"""Unit tests for the data attribute."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//:defs.bzl", "fortran_binary", "fortran_library", "fortran_test")

def _data_in_runfiles_test_impl(ctx):
    """Test that the data file is in the target's runfiles."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    runfiles = [f.short_path for f in target[DefaultInfo].default_runfiles.files.to_list()]
    asserts.true(
        env,
        "test/unit/data/input.txt" in runfiles,
        "Expected input.txt in runfiles, got {}".format(runfiles),
    )

    return analysistest.end(env)

data_in_runfiles_test = analysistest.make(_data_in_runfiles_test_impl)

def data_test_suite(name):
    """Test suite for the data attribute.

    Args:
      name: name of the test suite.
    """

    # Scenario: a binary carries its data files
    # Given a fortran_binary with a file in data
    # When its runfiles are collected
    # Then the file is among them
    fortran_binary(
        name = "bin_with_data",
        srcs = ["main.f90"],
        data = ["input.txt"],
        tags = ["manual"],
    )

    data_in_runfiles_test(
        name = "binary_data_in_runfiles_test",
        target_under_test = ":bin_with_data",
    )

    # Scenario: a test carries its data files
    # Given a fortran_test with a file in data
    # When its runfiles are collected
    # Then the file is among them
    fortran_test(
        name = "test_with_data",
        srcs = ["main.f90"],
        data = ["input.txt"],
        tags = ["manual"],
    )

    data_in_runfiles_test(
        name = "test_data_in_runfiles_test",
        target_under_test = ":test_with_data",
    )

    # Scenario: a library's data files reach the binary that links it
    # Given a fortran_library with a file in data
    # And a binary that depends on the library through a second library
    # When the binary's runfiles are collected
    # Then the file is among them
    fortran_library(
        name = "lib_with_data",
        srcs = ["lib.f90"],
        data = ["input.txt"],
        tags = ["manual"],
    )

    fortran_library(
        name = "lib_over_data",
        deps = [":lib_with_data"],
        tags = ["manual"],
    )

    fortran_binary(
        name = "bin_over_lib_with_data",
        srcs = ["main.f90"],
        deps = [":lib_over_data"],
        tags = ["manual"],
    )

    data_in_runfiles_test(
        name = "library_data_in_runfiles_test",
        target_under_test = ":bin_over_lib_with_data",
    )

    # Scenario: a test reads its data file at run time
    # Given a fortran_test with a file in data
    # When the test opens the file by its workspace-relative path
    # Then it reads the expected value
    # windows has no runfiles tree unless --enable_runfiles is set, so skip there
    fortran_test(
        name = "reads_data_test",
        srcs = ["reads_data.f90"],
        data = ["input.txt"],
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )

    native.test_suite(
        name = name,
        tests = [
            ":binary_data_in_runfiles_test",
            ":test_data_in_runfiles_test",
            ":library_data_in_runfiles_test",
            ":reads_data_test",
        ],
    )
