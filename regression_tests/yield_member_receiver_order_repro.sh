#!/usr/bin/env bash
# Parse member calls on the yielded result without reordering block effects.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yield-member-receiver.XXXXXX")"
cleanup() {
  local status=$?
  for name in nested forms explicit_result argument_call; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/nested.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

def document(&)
  C.putchar(65)
  yield.tap { C.putchar(67) }
end

def bridge(&)
  document do
    yield 66
  end
end

bridge do |value|
  C.putchar(value)
end
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/nested.expected" <<'EXPECTED'
ABC
EXPECTED
: >"$WORK_DIR/nested.stderr.expected"

cat >"$WORK_DIR/forms.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

def spaced(&)
  C.putchar(65)
  yield .tap { C.putchar(67) }
end

def continued(&)
  C.putchar(65)
  yield
    .tap { C.putchar(67) }
end

def do_form(&)
  C.putchar(65)
  yield.tap do
    C.putchar(67)
  end
end

spaced { C.putchar(66) }
continued { C.putchar(66) }
do_form { C.putchar(66) }
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/forms.expected" <<'EXPECTED'
ABCABCABC
EXPECTED
: >"$WORK_DIR/forms.stderr.expected"

cat >"$WORK_DIR/explicit_result.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

def explicit_empty(&)
  C.putchar(65)
  yield().tap { C.putchar(67) }
end

def explicit_value(&)
  C.putchar(65)
  yield(66).tap { C.putchar(67) }
end

def grouped(&)
  C.putchar(65)
  (yield).tap { C.putchar(67) }
end

def retain_result(&)
  yield.tap { C.putchar(67) }
end

explicit_empty { C.putchar(66) }
explicit_value { |value| C.putchar(value) }
grouped { C.putchar(66) }
result = retain_result do
  C.putchar(66)
  65
end
C.putchar(result)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/explicit_result.expected" <<'EXPECTED'
ABCABCABCBCA
EXPECTED
: >"$WORK_DIR/explicit_result.stderr.expected"

cat >"$WORK_DIR/argument_call.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

def actual_argument(&)
  C.putchar(65)
  yield C.putchar(66).tap { C.putchar(67) }
end

actual_argument { |value| C.putchar(value + 2) }
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/argument_call.expected" <<'EXPECTED'
ABCD
EXPECTED
: >"$WORK_DIR/argument_call.stderr.expected"

compile_run() {
  local name="$1" mode="$2" compiler="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log" cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug --no-prelude -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$WORK_DIR/$mode-$name.run.log" >"$WORK_DIR/$mode-$name.stderr"
  diff -u "$WORK_DIR/$name.stderr.expected" "$WORK_DIR/$mode-$name.stderr"
}

# Certify every fixture against the original before testing the candidate.
for name in nested forms explicit_result argument_call; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in nested forms explicit_result argument_call; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[yield-member-receiver]: four original-first fixtures agree"
