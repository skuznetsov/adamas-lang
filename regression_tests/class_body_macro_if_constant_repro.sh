#!/usr/bin/env bash
# A class or module body `{% if CONST %}` reads the constant's value. Prelude
# hello hits this in Crystal::Iconv, which declares
# `@iconv : LibIconv::IconvT` under `{% if USE_LIBICONV %}` (with
# `private USE_LIBICONV = false` set in a top-level macro if). The class-body
# evaluator could not read the constant, since top-level constants were
# registered only after every class, and an unknown condition registered both
# branches. @iconv took the LibIconv type and `LibC.iconv(@iconv, ...)` was
# rejected. The negative case checks that a method defined only in the false
# branch stays undefined.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class-body-macro-if-constant.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end
CR

# Exit code: K.r (7 or 3) + Mo.r (70 or 30) + method body (700 or 300).
cat > "$WORK_DIR/body.cr" <<'CR'

class K
  {% if USE_X %}
    def self.r : Int32
      7
    end
  {% else %}
    def self.r : Int32
      3
    end
  {% end %}
end

module Mo
  {% if USE_X %}
    def self.r : Int32
      70
    end
  {% else %}
    def self.r : Int32
      30
    end
  {% end %}
end

def body_branch : Int32
  {% if USE_X %} 700 {% else %} 300 {% end %}
end

LibC.exit(K.r + Mo.r + body_branch)
CR

write_case() {
  local name="$1" decl="$2"
  { cat "$WORK_DIR/header.cr"; printf '\n%s\n' "$decl"; cat "$WORK_DIR/body.cr"; } > "$WORK_DIR/$name.cr"
}

write_case private_in_top_macro_if '{% if flag?(:adamas_nonexistent_flag) %}
  private USE_X = true
{% else %}
  private USE_X = false
{% end %}'
write_case public_false 'USE_X = false'
write_case public_true 'USE_X = true'
write_case zero_is_truthy 'USE_X = 0'

cat > "$WORK_DIR/false_branch_method_absent.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

USE_X = false

class K
  {% if USE_X %}
    def self.only_true : Int32
      7
    end
  {% end %}
end

LibC.exit(K.only_true)
CR

# 333 % 256 = 77, 777 % 256 = 9.
POSITIVE_CASES=(private_in_top_macro_if:77 public_false:77 public_true:9 zero_is_truthy:9)
NEGATIVE_CASE=false_branch_method_absent
NEGATIVE_DIAGNOSTIC="undefined method 'only_true'"

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
  printf '%d class body macro-if constant case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'class body macro-if constant cases passed\n'
