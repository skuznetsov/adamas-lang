#!/usr/bin/env bash
# The lexer stopped a comment before `{%`/`{{` that follows `}` so a macro
# body parser would still see `{% end %}` (`# {{ x }}{% end %}`). It did so
# in ordinary code too, where the rest of the line became tokens: the
# compiler's own comment `(typical pattern: #{close}{% end %})` in lexer.cr
# failed with "unexpected RParen" once initial parser errors became fatal.
# The break now applies only inside a `macro` body or an open
# `{% if/unless/for/begin/verbatim %}` body, as in original Crystal. Each
# case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/comment-macro-marker.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
CR

cat > "$WORK_DIR/plain_code.cr" <<'CR'
def f : Int32
  # pattern: #{close}{% end %}) and {{ x }}{% end %})
  42
end

LibC.exit(f)
CR

cat > "$WORK_DIR/after_macro_if.cr" <<'CR'
{% if true %}{% end %}
# pattern: #{close}{% end %})
LibC.exit(42)
CR

cat > "$WORK_DIR/macro_control_body.cr" <<'CR'
{% if true %}# {{ 1 }}{% end %}
LibC.exit(42)
CR

cat > "$WORK_DIR/macro_def_body.cr" <<'CR'
macro m(x)
  {% if true %}# {{ x }}{% end %}
  LibC.exit({{ x }})
end

m(42)
CR

CASES=(plain_code after_macro_if macro_control_body macro_def_body)

for name in "${CASES[@]}"; do
  cat "$WORK_DIR/header.cr" "$WORK_DIR/$name.cr" > "$WORK_DIR/$name.full.cr"
  mv "$WORK_DIR/$name.full.cr" "$WORK_DIR/$name.cr"
done

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
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
fi

failures=0

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|unexpected\|invalid memory' "$log" || tail -1 "$log")"
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

if [[ "$failures" -ne 0 ]]; then
  printf '%d comment macro marker case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'comment macro marker cases passed\n'
