#!/usr/bin/env bash
# Keep writes to captured locals across inline try/tap lexical scopes.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline-capture-locals.XXXXXX")"
cleanup() {
  local status=$?
  for name in direct_try direct_tap nullable_try proc_capture return_flows nested_blocks; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/direct_try.cr" <<'CRYSTAL'
message = "trace"
["/one", "/two"].try(&.each { |line| message += line })
puts message
message = "before"
1.try { |item| message = "after/#{item}" }
puts message
CRYSTAL
cat >"$WORK_DIR/direct_try.expected" <<'EXPECTED'
trace/one/two
after/1
EXPECTED
: >"$WORK_DIR/direct_try.stderr.expected"

cat >"$WORK_DIR/direct_tap.cr" <<'CRYSTAL'
message = "before"
result = 1.tap { |item| message = "after/#{item}" }
puts message
puts result
nil.tap { message = "tap/nil" }
nil.try { message = "unreachable" }
puts message
CRYSTAL
cat >"$WORK_DIR/direct_tap.expected" <<'EXPECTED'
after/1
1
tap/nil
EXPECTED
: >"$WORK_DIR/direct_tap.stderr.expected"

cat >"$WORK_DIR/nullable_try.cr" <<'CRYSTAL'
def capture(value : Int32?)
  message = "before"
  result = value.try do |item|
    message = "after/#{item}"
    item + 10
  end
  puts message
  puts result || -1
end
capture(3)
capture(nil)
CRYSTAL
cat >"$WORK_DIR/nullable_try.expected" <<'EXPECTED'
after/3
13
before
-1
EXPECTED
: >"$WORK_DIR/nullable_try.stderr.expected"

cat >"$WORK_DIR/proc_capture.cr" <<'CRYSTAL'
def sum(values : Array(Int32)?)
  total = 5
  result = values.try(&.each { |item| total += item })
  puts total
  puts result.nil?
end
sum([2, 3])
sum(nil)
message = "tap"
[1, 2].tap(&.each { |item| message += "/#{item}" })
puts message
CRYSTAL
cat >"$WORK_DIR/proc_capture.expected" <<'EXPECTED'
10
true
5
true
tap/1/2
EXPECTED
: >"$WORK_DIR/proc_capture.stderr.expected"

cat >"$WORK_DIR/return_flows.cr" <<'CRYSTAL'
def capture_or_return(value : Int32?)
  message = "before"
  value.try do |item|
    message = "body/#{item}"
    return "returned/#{item}"
  end
  message
end
puts capture_or_return(3)
puts capture_or_return(nil)
CRYSTAL
cat >"$WORK_DIR/return_flows.expected" <<'EXPECTED'
returned/3
before
EXPECTED
: >"$WORK_DIR/return_flows.stderr.expected"

cat >"$WORK_DIR/nested_blocks.cr" <<'CRYSTAL'
def nested_capture(value : Int32?)
  message = "before"
  value.try do |item|
    2.tap do |inner|
      message = "nested/#{item}/#{inner}"
    end
  end
  puts message
end
nested_capture(3)
nested_capture(nil)
message = "outer"
[1, 2].each do |item|
  item.try { |inner| message += "/#{inner}" }
end
puts message
CRYSTAL
cat >"$WORK_DIR/nested_blocks.expected" <<'EXPECTED'
nested/3/2
before
outer/1/2
EXPECTED
: >"$WORK_DIR/nested_blocks.stderr.expected"

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
      --no-debug -o "$output" >"$log" 2>&1; then
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

for name in direct_try direct_tap nullable_try proc_capture return_flows nested_blocks; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in direct_try direct_tap nullable_try proc_capture return_flows nested_blocks; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[inline-capture-locals]: six original-first fixtures agree"
