# rules_fortran integration tests

These exercise rules_fortran as an **external consumer**: each test spins up a
scratch workspace whose `MODULE.bazel` `local_path_override`s onto this repo,
then drives a nested `bazel` invocation over a small Fortran project.

Run them like any other target:

```sh
bazel test //test/integration:basic_test
```

The nested build requires Bazel on `PATH`. The repository rule prefers
`bazel-real` when available and otherwise uses `bazel`. When the outer build is
run through Bazelisk, Bazelisk puts its selected Bazel executable first on the
child `PATH`, so the nested build uses the same Bazel version as the outer build.
bzlmod is required.

Adapted from the equivalent scaffolding in
[bazelbuild/rules_cc](https://github.com/bazelbuild/rules_cc/tree/main/tests/integration).
