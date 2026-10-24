#!/usr/bin/env bash
# A member call on a local variable is an instance call, even while the
# local is typeof-bound to a type name. Constructor argument inference runs
# with typeof bindings, and the type-literal receiver path printed `entry` as
# `H::Entry(Int32, Int32)`: `entry.hash` was inferred as the class call
# `H::Entry.hash`, i.e. the untyped Object#hash (UInt64), instead of the
# `getter hash` for `@hash : UInt32`. Prelude hello hits this in
# Hash#update_linear_scan (`Entry(K, V).new(entry.hash, entry.key, value)`).
# Class calls on real type literals must keep resolving, and an undefined
# method on the local must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-receiver-not-type-literal.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  def hash
    7_u64
  end

  macro getter(*names)
    {% for name in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end
end

def which(x : UInt32) : Int32
  32
end

def which(x : UInt64) : Int32
  64
end

module Seeds
  def self.seed : UInt32
    5_u32
  end
end

class H(K, V)
  def initialize
    @e = Entry(K, V).new(3_u32, 1, 2)
  end

  def each_entry_with_index(&)
    yield @e, 0
  end

  struct Entry(K, V)
    getter key, value, hash

    def initialize(@hash : UInt32, @key : K, @value : V)
    end
  end
CR

write_case() {
  local name="$1" body="$2" exit_expr="$3"
  { cat "$WORK_DIR/header.cr"; printf '%s\nend\n\nLibC.exit(%s)\n' "$body" "$exit_expr"; } > "$WORK_DIR/$name.cr"
}

write_case block_param_getter '
  def scan(key, value, hash) : Int32
    each_entry_with_index do |entry, index|
      return which(Entry(K, V).new(entry.hash, entry.key, value).hash)
    end
    0
  end' 'H(Int32, Int32).new.scan(1, 2, 9_u32)'
write_case plain_local_getter '
  def scan(value) : Int32
    entry = @e
    which(Entry(K, V).new(entry.hash, entry.key, value).hash)
  end' 'H(Int32, Int32).new.scan(2)'
write_case type_literal_class_call '
  def scan(value) : Int32
    entry = @e
    Entry(K, V).new(Seeds.seed, entry.key, value).hash.to_i32!
  end' 'H(Int32, Int32).new.scan(2)'
write_case undefined_local_method '
  def scan(value) : Int32
    entry = @e
    which(Entry(K, V).new(entry.missing_hash, entry.key, value).hash)
  end' 'H(Int32, Int32).new.scan(2)'

POSITIVE_CASES=(block_param_getter:32 plain_local_getter:32 type_literal_class_call:5)
NEGATIVE_CASE=undefined_local_method
NEGATIVE_DIAGNOSTIC="undefined method 'missing_hash'"

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$NEGATIVE_CASE.cr" -o "$WORK_DIR/$NEGATIVE_CASE.orig" > "$WORK_DIR/$NEGATIVE_CASE.orig.log" 2>&1 ||
      ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
    exit 2
  fi
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

log="$WORK_DIR/$NEGATIVE_CASE.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$NEGATIVE_CASE.cr" \
  -o "$WORK_DIR/$NEGATIVE_CASE.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
    [[ ! -e "$WORK_DIR/$NEGATIVE_CASE.adamas" ]]; then
  printf 'PASS negative %s\n' "$NEGATIVE_CASE"
else
  printf 'FAIL negative %s (exit %s): %s\n' "$NEGATIVE_CASE" "$(exit_code_of "$log")" \
    "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d local receiver case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'local receiver cases passed\n'
