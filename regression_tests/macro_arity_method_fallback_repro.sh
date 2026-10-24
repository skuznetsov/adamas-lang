#!/usr/bin/env bash
# A call that cannot cover a macro's mandatory parameters does not match that
# macro (Crystal `Macro#matches?`) and resolves as an ordinary method instead.
# The prelude declares both `def spawn(*, name, same_thread, &block)` and
# `macro spawn(call, *, name, same_thread, &block)` whose body ends in
# `spawn do {{call}} end`; expanding the macro for that block-only call
# recursed until the compiler stack overflowed (signal 10) on prelude hello.
# A call that does match must still expand, and a mismatched call with no
# method to fall back to must be rejected as original Crystal does.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-arity-method-fallback.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/block_call_binds_def.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def sp(*, name : Int32? = nil, &)
  yield
end

macro sp(call, *, name = nil, &block)
  sp do
    {{call}}
  end
end

LibC.exit(sp { 7 })
CR

cat > "$WORK_DIR/matching_calls_expand.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def sp(*, name : Int32? = nil, &)
  yield
end

macro sp(call, *, name = nil, &block)
  sp do
    {{call}}
  end
end

macro nm(a, b)
  {{a}} &+ {{b}}
end

struct Int32
  @[::Primitive(:binary)]
  def &+(other : Int32) : self
  end
end

# `sp(3)` still matches the macro; the expansion's block call then binds the
# def. `nm(10, b: 20)` covers its second mandatory parameter by name.
LibC.exit(sp(3) &+ nm(10, b: 20))
CR

cat > "$WORK_DIR/mismatch_without_method.cr" <<'CR'
macro need_one(call)
  {{call}}
end

need_one
CR

POSITIVE_CASES=(block_call_binds_def:7 matching_calls_expand:33)
NEGATIVE_CASE=mismatch_without_method
NEGATIVE_DIAGNOSTIC="need_one"

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
      ! grep -qF "wrong number of arguments for macro '$NEGATIVE_DIAGNOSTIC'" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
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
  printf '%d macro arity case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'macro arity method-fallback cases passed\n'
