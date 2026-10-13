#!/usr/bin/env bash
# An unannotated method whose name ends in `?` was hard-typed Bool before its
# body was lowered, so the body value was coerced to Bool and never
# re-inferred. Stdlib `to_i64?` is `to_i64(...) { nil }` (returns Int64 | Nil);
# with the Bool signature `.nil?` folded to `false`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/predicate_name_return.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun getpid : Int32
end

def a32?(bad : Bool)
  a32(bad) { nil }
end

def a32(bad : Bool, &)
  return yield if bad
  5_i64
end

def small?(x : Int32)
  x < 3
end

def count_down?(x : Int32) : Bool
  return false if x <= 0
  count_down?(x - 1) || x == 1
end

LibC.exit(1) unless a32?(LibC.getpid > 3).nil?
LibC.exit(2) if a32?(LibC.getpid < 0).nil?
LibC.exit(3) unless a32?(LibC.getpid < 0) == 5_i64
LibC.exit(4) unless small?(1)
LibC.exit(5) if small?(LibC.getpid)
LibC.exit(6) unless count_down?(3)
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
exit 1 unless "abc".to_i64?.nil?
exit 2 unless "42".to_i64? == 42_i64
exit 3 unless "x1".to_i32?.nil?
exit 4 unless "7".to_u64? == 7_u64
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
echo predicate_name_inferred_return_repro_ok
