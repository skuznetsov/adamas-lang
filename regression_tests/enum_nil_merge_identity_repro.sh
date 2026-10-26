#!/usr/bin/env bash
# Enum values are lowered through their base-integer carrier and keep their
# enum identity in a side table. A merge of an enum with nil (`b ? E::B : nil`,
# an if without else, a local assigned in one branch) built its union from the
# carrier, `Nil | Int32`, so the value no longer matched an `E?` restriction.
# Stage 2 failed in lexer.cr's number_kind with "no overload matches
# Token#initialize for argument types (..., NumberKind | Int32, Bool)".
# A merge of an enum with an integer or another enum must stay rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-nil-merge.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum NK
  A
  B
  C
end

enum Other
  X
  Y
end

struct T
  def initialize(@k : NK? = nil, @e : Bool = false)
  end

  def k
    @k
  end
end

class L
  def suffix : NK?
    nil
  end

  def fallback : NK
    NK::C
  end

  def sel(b : Bool)
    return nil unless b
    yield
  end

  def pick(b : Bool)
HEAD
    printf '%s\n' "$body"
    cat <<'TAIL'
    T.new(k: k, e: b)
  end
end

# NK::B scores 20; nil and NK::C score 22. A carrier-typed union fails is_a?.
def code(k : NK?) : Int32
  if k.is_a?(NK)
    k.value == 1 ? 20 : 22
  else
    22
  end
end

l = L.new
LibC.exit(code(l.pick(true).k) &+ code(l.pick(false).k))
TAIL
  } > "$WORK_DIR/$name.cr"
}

write_case ternary_nil "    k = b ? NK::B : nil"
write_case if_without_else "    k = if b
          NK::B
        end"
write_case if_else_nil "    k = if b
          NK::B
        else
          nil
        end"
write_case unless_else "    k = unless b
          nil
        else
          NK::B
        end"
write_case case_without_else "    k = case
        when b then NK::B
        end"
write_case local_one_branch "    if b
      k = NK::B
    end"
write_case yield_return "    k = sel(b) { NK::B }"
# Shape of lexer.cr's number_kind.
write_case lexer_or_assign "    k = suffix
    k ||= begin
      if b
        if b
          NK::B
        else
          nil
        end
      end || fallback
    end"
# Negative: NK | Int32 is not NK?.
write_case enum_int_rejected "    k = b ? NK::B : 5"
# Negative: NK | Other is not NK?.
write_case two_enums_rejected "    k = b ? NK::B : Other::Y"

POSITIVE=(ternary_nil if_without_else if_else_nil unless_else case_without_else local_one_branch
  yield_return lexer_or_assign)
NEGATIVE=(enum_int_rejected two_enums_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected a no overload matches error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d enum nil merge case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Enum nil merge cases passed\n'
