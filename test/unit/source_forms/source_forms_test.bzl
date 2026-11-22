"""Unit tests for how a source's extension picks source form and preprocessing."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//:defs.bzl", "fortran_library")
load("//test/unit:common.bzl", "assert_argv_contains", "assert_argv_contains_not")

# extension -> (source form flag, preprocessed)
_EXTENSIONS = {
    "F": ("-ffixed-form", True),
    "F03": ("-ffree-form", True),
    "F08": ("-ffree-form", True),
    "F90": ("-ffree-form", True),
    "F95": ("-ffree-form", True),
    "f": ("-ffixed-form", False),
    "f03": ("-ffree-form", False),
    "f08": ("-ffree-form", False),
    "f90": ("-ffree-form", False),
    "f95": ("-ffree-form", False),
}

_OTHER_FORM = {
    "-ffixed-form": "-ffree-form",
    "-ffree-form": "-ffixed-form",
}

def _source_form_test_impl(ctx):
    """Test that the compile action carries the form and preprocessing flags for the extension."""
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    compile_actions = [a for a in actions if a.mnemonic == "FortranCompile"]
    asserts.equals(env, 1, len(compile_actions), "Expected exactly one FortranCompile action")
    compile_action = compile_actions[0]

    assert_argv_contains(env, compile_action, ctx.attr.form)
    assert_argv_contains_not(env, compile_action, _OTHER_FORM[ctx.attr.form])

    if ctx.attr.preprocessed:
        assert_argv_contains(env, compile_action, "-cpp")
    else:
        assert_argv_contains_not(env, compile_action, "-cpp")

    return analysistest.end(env)

source_form_test = analysistest.make(
    _source_form_test_impl,
    attrs = {
        "form": attr.string(),
        "preprocessed": attr.bool(),
    },
)

def source_forms_test_suite(name):
    """Test suite for source form and preprocessing selection.

    Args:
      name: name of the test suite.
    """
    tests = []
    libraries = []

    for extension, (form, preprocessed) in _EXTENSIONS.items():
        # upper/ and lower/ keep F90 and f90 apart on case-insensitive filesystems
        case = "upper" if preprocessed else "lower"
        label = "{}_{}".format(case, extension.lower())

        # Scenario: the extension picks source form and preprocessing
        # Given a source with this extension
        # When it is compiled
        # Then .f and .F are fixed form and the rest are free form
        # And only uppercase extensions are preprocessed
        write_file(
            name = "src_" + label,
            out = "{}/src.{}".format(case, extension),
            # leading blanks make this valid in both fixed and free form
            content = [
                "      subroutine form_" + label,
                "      end",
                "",
            ],
        )

        fortran_library(
            name = "lib_" + label,
            srcs = [":src_" + label],
            tags = ["manual"],
        )
        libraries.append(":lib_" + label)

        source_form_test(
            name = label + "_source_form_test",
            target_under_test = ":lib_" + label,
            form = form,
            preprocessed = preprocessed,
        )
        tests.append(":" + label + "_source_form_test")

    # Scenario: every supported extension really compiles
    # Given one library per extension
    # When they are built
    # Then the compiler accepts the flags chosen for each
    build_test(
        name = "all_extensions_build_test",
        targets = libraries,
    )
    tests.append(":all_extensions_build_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
