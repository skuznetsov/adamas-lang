#!/usr/bin/env bash
# A block def whose body only delegates to a yielding macro (stdlib
# `String#to_u64(&)` -> `gen_to_u64`) was invisible to the block-return
# dependency predicates, so block_call_return_contract_for returned nil and
# every block callsite shared one `_block` symbol. The `{ nil }` caller
# (to_u64?) stamped it Nil | UInt64, and `to_u64 { 99_u64 }` read a wrong value.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yielding_macro_block_shape.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class S
  def initialize(@x : Int32)
  end

  def conv(base : Int32 = 10, strict : Bool = true) : UInt64
    conv(base, strict) { 7_u64 }
  end

  def conv?(base : Int32 = 10, strict : Bool = true) : UInt64?
    conv(base, strict) { nil }
  end

  def conv(base : Int32 = 10, strict : Bool = true, &block)
    gen_c UInt64
  end

  private macro gen_c(klass)
    return yield if @x == 0
    {{klass}}.new(5_u64)
  end
end

a = S.new(0).conv?
LibC.exit(1) unless a.nil?
c = S.new(0).conv { 99_u64 }
LibC.exit(2) unless c == 99_u64
b = S.new(0).conv
LibC.exit(4) unless b == 7_u64
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
x = ARGV.size > 5 ? "12" : "Foo"
exit 1 unless x.to_u64?.nil?
exit 2 unless x.to_u64 { 99_u64 } == 99_u64
exit 3 unless x.to_i32 { -1 } == -1
exit 4 unless "12".to_u64 { 99_u64 } == 12_u64
exit 0
CR
for name in np pl; do
  flags=()
  [[ "$name" == np ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo yielding_macro_block_return_shape_repro_ok
