#!/usr/bin/env bash
# get_function_return_type fell back to the base-name return cache
# (@function_base_return_types["String#to_u64"]) for an arg-dependent
# specialization (`String#to_u64$UInt64...`) of an unannotated def with an
# untyped/free-type param. The sibling specialization's return type (Int32 | Nil
# from to_i32?) leaked, so `x.to_u64?` stopped being UInt64 | Nil and a
# non-numeric string produced a non-nil value.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spec_base_return_cache.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/pl.cr" <<'CR'
x = ARGV.size > 5 ? "12" : "Foo.new(7)"
a = x.to_i32?
b = x.to_u64?
exit 1 unless a.nil?
exit 2 unless b.nil?
exit 3 unless "12".to_u64? == 12_u64
exit 0
CR
cat >"$WORK_DIR/v1.cr" <<'CR'
class S
  def initialize(@bad : Bool)
  end

  def a32?
    a32 { nil }
  end

  def a32(&)
    return yield if @bad
    5_u32.to_i64
  end
end

s = S.new(ARGV.size < 5)
exit 1 unless s.a32?.nil?
exit 0
CR
for name in pl v1; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo specialization_base_return_cache_repro_ok
