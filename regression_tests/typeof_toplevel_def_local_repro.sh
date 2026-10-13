#!/usr/bin/env bash
# `y = h; typeof(y)` at top level printed Void: lower_typeof inferred only
# from the AST, which cannot see a top-level local bound to a def-call
# result. The lowered local already carries the type.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeof_toplevel_def_local_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def f
  return 1
end

def h
  "s"
end

x = f
y = h
STDERR.puts "x=#{typeof(x)}"
STDERR.puts "y=#{typeof(y)}"
STDERR.puts "h=#{typeof(h)}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
x=Int32
y=String
h=String
OUT
grep -oE '^[a-z]=[A-Za-z0-9]+' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: typeof of a top-level local bound to a def result" >&2
  exit 1
fi
echo "PASS: typeof sees top-level def-result locals"
