#!/usr/bin/env bash
# Regression: `$N` capture globals lowered to an unpopulated `$N` class var,
# so `$1` after a successful `=~` was null and IO#puts segfaulted. S2 relies on
# `$1` in llvm_backend (`callee_name =~ /Array\$L(Int32|UInt32)\$R\$Hsum$/`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/regex_capture_global_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDERR ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
name = "Array$LUInt32$R$Hsum"
if name =~ /Array\$L(Int32|UInt32)\$R\$Hsum$/
  STDERR.puts $1
else
  STDERR.puts "nomatch"
end
if "key=val" =~ /(\w+)=(\w+)/
  STDERR.puts $2
  STDERR.puts $1
  STDERR.puts $0
end
if "x9" =~ /x(\d)/
  STDERR.puts $1.to_i + 1
end
STDERR.flush
CR
check c1 'UInt32
val
key
key=val
10'

if [ "$status" -ne 0 ]; then
  echo "FAIL: regex capture globals broken" >&2
  exit 1
fi
echo "PASS: regex capture globals OK"
