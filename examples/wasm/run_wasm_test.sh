#!/usr/bin/env bash
# run wasm_cc_binary output via node
set -euo pipefail

# find .js from rootpaths args
for arg in "$@"; do
  case "$arg" in *.js) JS="${arg#./}"; break;; esac
done
[ -z "${JS:-}" ] && { echo "no .js in: $*" >&2; exit 1; }

# hermetic node: NODE holds an rlocationpath set from BUILD; fall back to PATH node
NODE_BIN=""
if [ -n "${NODE:-}" ]; then
  for N in "${RUNFILES_DIR:-.}/$NODE" "$NODE"; do
    [ -f "$N" ] && NODE_BIN="$N" && break
  done
  if [ -z "$NODE_BIN" ] && [ -n "${RUNFILES_MANIFEST_FILE:-}" ] && [ -f "$RUNFILES_MANIFEST_FILE" ]; then
    NODE_BIN=$(grep "^$NODE " "$RUNFILES_MANIFEST_FILE" | cut -d' ' -f2- || true)
  fi
fi
NODE_BIN="${NODE_BIN:-node}"

# try symlink tree (linux)
for R in \
  "${RUNFILES_DIR:-.}/_main/$JS" \
  "${RUNFILES_DIR:-.}/$JS" \
  "$JS"; do
  [ -f "$R" ] && exec "$NODE_BIN" "$R"
done

# manifest lookup (windows)
if [ -n "${RUNFILES_MANIFEST_FILE:-}" ] && [ -f "$RUNFILES_MANIFEST_FILE" ]; then
  R=$(grep "^_main/$JS " "$RUNFILES_MANIFEST_FILE" | cut -d' ' -f2-)
  [ -n "$R" ] && [ -f "$R" ] && exec "$NODE_BIN" "$R"
fi

echo "js not found: $JS" >&2
exit 1
