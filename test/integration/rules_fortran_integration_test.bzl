"""Integration test rule for rules_fortran.

Wraps a shell test that runs a nested Bazel invocation against rules_fortran
as an external consumer (see test_launcher.sh).
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def rules_fortran_integration_test(
        name,
        test_script,
        data = [],
        env = {},
        **kwargs):
    """Integration test for rules_fortran.

    Args:
        name: The name of the test.
        test_script: The shell script for the test.
        data: (optional) Additional data dependencies required for the test.
        env: (optional) Additional environment variables to pass to the test.
        **kwargs: Additional arguments to pass to the test target.
    """

    bazel_bin = "@local_bazel//:bazel"

    test_env = {
        "TEST_RUNNER": "$(rlocationpath %s)" % test_script,
        "BAZEL_BINARY": "$(rlocationpath %s)" % bazel_bin,
    }
    test_env.update(env)

    sh_test(
        name = name,
        srcs = [
            "//test/integration:test_launcher.sh",
        ],
        data = [
            bazel_bin,
            test_script,
            "//test:test_utils_sh",
            "//:srcs",
            "@rules_shell//shell/runfiles",
        ] + data,
        env = test_env,
        **kwargs
    )
