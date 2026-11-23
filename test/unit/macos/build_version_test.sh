#!/usr/bin/env bash
# compares the LC_BUILD_VERSION (minos, sdk) of a fortran binary with a cc_library's objects
set -euo pipefail

bin=$1; shift
archive=""
for f in "$@"; do case "$f" in *.a) archive=$f ;; esac; done
[ -n "$archive" ] || { echo "no cc archive in: $*" >&2; exit 1; }

# prints "minos sdk" of the first LC_BUILD_VERSION in a mach-o file or archive
build_version() {
  otool -l "$1" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="minos"{m=$2} f&&$1=="sdk"{print m, $2; exit}'
}

fortran=$(build_version "$bin")
c=$(build_version "$archive")
echo "fortran binary: $fortran"
echo "cc object:      $c"
[ -n "$fortran" ] && [ "$fortran" = "$c" ] || { echo "FAIL: minos/sdk differ" >&2; exit 1; }
echo "all passed"
