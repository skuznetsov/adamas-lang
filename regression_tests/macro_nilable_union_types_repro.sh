#!/usr/bin/env bash
# Macro `T.union_types` split only `|` unions, so a nilable type argument
# written `R?` produced the single member "R?" instead of `R | Nil`. The
# predicate `T.union_types.any? { |t| t == Nil }` was then false, and the
# stdlib Atomic/Box predicate `all? { |t| t == Nil || t < Reference }`
# rejected `R?`. The explicit_union and non_nilable cases guard the existing
# `|` split and the absence of an invented Nil member.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-nilable-union-types.XXXXXX")"
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

class R
end

class A(T)
  def has_nil : Int32
    {% if T.union_types.any? { |t| t == Nil } %} 1 {% else %} 2 {% end %}
  end

  def atomic_like : Int32
    {% if T.union_types.all? { |t| t == Nil || t < Reference } && T != Nil %} 1 {% else %} 2 {% end %}
  end
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case nilable_has_nil '
LibC.exit(A(R?).new.has_nil)'
write_case nilable_atomic '
LibC.exit(A(Int32).new.atomic_like + A(R).new.atomic_like * 10 + A(R?).new.atomic_like * 100)'
write_case nilable_value_atomic '
LibC.exit(A(Int32?).new.atomic_like)'
write_case explicit_union '
LibC.exit(A(R | Nil).new.has_nil)'
write_case non_nilable '
LibC.exit(A(R).new.has_nil)'

CASES=(nilable_has_nil:1 nilable_atomic:112 nilable_value_atomic:2 explicit_union:1 non_nilable:2)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
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
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d macro nilable union_types case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'macro nilable union_types cases passed\n'
