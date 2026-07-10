# Setup runfiles and the test directory and then run the provided test script.

[ -z "$TEST_SRCDIR" ] && { echo "TEST_SRCDIR not set!" >&2; exit 1; }

export TEST_log=$TEST_TMPDIR/log

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
    source "$0.runfiles/$f" 2>/dev/null || \
    source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
    source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
    { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

source "$(rlocation rules_fortran/test/test_utils.sh)"

# Set environment vars for Windows
if is_windows; then
  export MSYS_NO_PATHCONV=1
fi

# Put bazel on PATH
bazel_binary="$(rlocation "$BAZEL_BINARY")"
bazel_bin_dir="$TEST_TMPDIR/bazel"
if is_windows; then
    bazel_bin_dir="$(cygpath -u "$bazel_bin_dir")"
fi
mkdir -p "$bazel_bin_dir"
cp "$bazel_binary" "$bazel_bin_dir/bazel"
export PATH="$bazel_bin_dir:$PATH"

rules_fortran_module="$(rlocation rules_fortran/MODULE.bazel)"
rules_fortran_dir="$(dirname "$rules_fortran_module")"

# Create a scratch workspace
scratch_workspace="$TEST_TMPDIR/scratch"
mkdir -p "$scratch_workspace"
cd "$scratch_workspace"

# Make rules_fortran available
cat > MODULE.bazel << EOF
module(name = "test_module")

bazel_dep(name = "rules_fortran", version = "0.0.0")
local_path_override(
    module_name = "rules_fortran",
    path = "$rules_fortran_dir"
)
EOF

test_runner_path="$(rlocation "$TEST_RUNNER")" || (echo >&2 "FAILED TO LOAD TEST RUNNER" && exit 1)
test_runner_cmd=( "${test_runner_path}" )

echo "$test_runner_cmd"
"${test_runner_cmd[@]}"
