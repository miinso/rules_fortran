# rules_fortran integration tests

These exercise rules_fortran as an **external consumer**: each test spins up a
scratch workspace whose `MODULE.bazel` `local_path_override`s onto this repo,
then drives a nested `bazel` invocation over a small Fortran project.

Run them like any other target:

```sh
bazel test //test/integration/...
```

They require a copy of Bazel to run the nested build. It is retrieved from your
`PATH` (like `which bazel`); if `bazel-real` is found it is used instead (this
assumes `bazel` is the standard shell wrapper). The found binary must be a
standalone Bazel executable, not a wrapper, since it is copied into the scratch
workspace and invoked directly. bzlmod is required.

This replaces the old top-level `e2e/` module: instead of a sibling module that
CI had to `cd` into and build separately, the same "external consumer" coverage
now lives in the main Bazel test graph.

Adapted from the equivalent scaffolding in
[bazelbuild/rules_cc](https://github.com/bazelbuild/rules_cc/tree/main/tests/integration).
