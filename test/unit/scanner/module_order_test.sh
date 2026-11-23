#!/usr/bin/env bash
# runs the module scanner directly on small cases: errors, limits, the order file
set -uo pipefail

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
set +e

scanner="$(rlocation "$1")"
[ -x "$scanner" ] || { echo "scanner not found: $1" >&2; exit 1; }
cd "$TEST_TMPDIR" || exit 1

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
text() { tr -d '\015' < "$1"; }  # the scanner writes crlf on windows

# writes a params file for the sources (and `file`/`include`/`option` lines) given
params() {
  local dir=$1; shift
  { echo "order $dir/order"; echo "empty $dir/empty.f90"
    for a in "$@"; do echo "$a"; done; } > "$dir/params"
}

# Scenario: a long chain of modules
# Given 3000 sources, each using the next one's module
# When the scanner runs (with a small stack where the shell can set one)
# Then the last module of the chain comes first in the order file
mkdir -p chain
n=3000
srcs=()
for ((i = 0; i < n; i++)); do
  f=$(printf 'chain/m%05d.f90' "$i")
  if ((i + 1 < n)); then
    printf 'module m%05d\n  use m%05d\nend module\n' "$i" $((i + 1)) > "$f"
  else
    printf 'module m%05d\nend module\n' "$i" > "$f"
  fi
  srcs+=("src $f")
done
params chain "${srcs[@]}"
( ulimit -s 256 2>/dev/null; "$scanner" chain/params ) || fail "chain: scanner failed"
[ "$(text chain/order | sed -n 1p)" = "\"chain/m02999.f90\"" ] || fail "chain: first is $(text chain/order | sed -n 1p)"
[ "$(wc -l < chain/order | tr -d ' ')" = "$n" ] || fail "chain: expected $n lines"

# Scenario: one statement over many lines
# Given a fixed-form DATA statement continued over 20000 lines, then a USE
# When the scanner runs (with a small stack where the shell can set one)
# Then it reads the USE after it
mkdir -p data
{ printf '      MODULE BIGDATA\n      USE DATAKINDS\n      REAL X(20001)\n      DATA X /1.0\n'
  for ((i = 0; i < 20000; i++)); do printf '     &, 1.0\n'; done
  printf '     &/\n      END MODULE\n'; } > data/big.f
printf '      MODULE DATAKINDS\n      END MODULE\n' > data/kinds.f
params data "src data/big.f" "src data/kinds.f"
( ulimit -s 256 2>/dev/null; "$scanner" data/params ) || fail "data: scanner failed"
[ "$(text data/order)" = "$(printf '%s\n' '"data/kinds.f"' '"data/big.f"')" ] || fail "data: order was $(text data/order)"

# Scenario: a real cycle
# Given two sources whose modules use each other
# When the scanner runs
# Then it fails and names both files in the cycle
mkdir -p cycle
printf 'module ya\n  use yb\nend module\n' > cycle/a.f90
printf 'module yb\n  use ya\nend module\n' > cycle/b.f90
params cycle "src cycle/a.f90" "src cycle/b.f90"
out=$("$scanner" cycle/params 2>&1) && fail "cycle: scanner succeeded"
case "$out" in
  *"cycle: cycle/a.f90 -> cycle/b.f90 -> cycle/a.f90"*) ;;
  *) fail "cycle: message was: $out" ;;
esac

# Scenario: one module defined twice
# Given two sources that define module dup, one of them through an include
# When the scanner runs
# Then it fails and names both places
mkdir -p dup
printf 'module dup\nend module\n' > dup/a.f90
printf 'module dup\nend module\n' > dup/dup.inc
printf "include 'dup.inc'\n" > dup/b.f90
params dup "file dup/dup.inc" "src dup/a.f90" "src dup/b.f90"
out=$("$scanner" dup/params 2>&1) && fail "dup: scanner succeeded"
case "$out" in
  *"module 'dup' is defined by both dup/a.f90 and dup/b.f90 (in dup/dup.inc)"*) ;;
  *) fail "dup: message was: $out" ;;
esac

# Scenario: an include file that is not declared
# Given a source including a file that exists but is not in the params
# When the scanner runs
# Then the file is not read, so the scan stays limited to declared inputs
mkdir -p undeclared
printf 'module hidden\nend module\n' > undeclared/hidden.inc
printf "include 'hidden.inc'\nmodule shown\nend module\n" > undeclared/a.f90
printf 'module other\nend module\n' > undeclared/b.f90
params undeclared "src undeclared/a.f90" "src undeclared/b.f90" "dump undeclared/dump"
"$scanner" undeclared/params || fail "undeclared: scanner failed"
grep -q "^P hidden" undeclared/dump && fail "undeclared: read an undeclared file"
grep -q "^P shown" undeclared/dump || fail "undeclared: missed module shown"

# Scenario: no source defines a module
# Given two sources with subroutines only
# When the scanner runs
# Then the order file lists only the placeholder, which is valid code
mkdir -p nomod
printf 'subroutine x\nend subroutine\n' > nomod/x.f90
printf 'subroutine y\nend subroutine\n' > nomod/y.f90
params nomod "src nomod/x.f90" "src nomod/y.f90"
"$scanner" nomod/params || fail "nomod: scanner failed"
[ "$(text nomod/order)" = "\"nomod/empty.f90\"" ] || fail "nomod: order was $(text nomod/order)"
grep -q "^subroutine rules_fortran_module_pass_placeholder" nomod/empty.f90 || fail "nomod: placeholder has no code"

# Scenario: paths that a response file could misread
# Given sources whose paths hold a blank or a double quote (not on windows), or start with -
# When the scanner runs
# Then each is written quoted and escaped, and the - one gets ./ in front
mkdir -p -- "odd dir" -dash
printf 'module o1\nend module\n' > "odd dir/a.f90"
printf 'module o2\nend module\n' > -dash/b.f90
odd=("src odd dir/a.f90" "src -dash/b.f90")
expected=$(printf '%s\n' '"odd dir/a.f90"' '"./-dash/b.f90"')
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *)
    mkdir -p 'q"dir'
    printf 'module o3\nend module\n' > 'q"dir/c.f90'
    odd+=('src q"dir/c.f90')
    expected=$(printf '%s\n' "$expected" '"q\"dir/c.f90"')
    ;;
esac
params . "${odd[@]}"
"$scanner" params || fail "odd: scanner failed"
[ "$(text order)" = "$expected" ] || fail "odd: order was $(text order)"

if ((failures > 0)); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
