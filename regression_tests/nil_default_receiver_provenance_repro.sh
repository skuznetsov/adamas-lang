#!/usr/bin/env bash
# Preserve Nil as the omitted literal default; never invent an Object receiver.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nil-default-provenance.XXXXXX")"
cleanup() {
  local status=$?
  for name in default_body callsite_orders module_forward reassigned buffered_error; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/default_body.cr" <<'CRYSTAL'
class DiagnosticMessage
  def render(message : String, *args, exception = nil, backtrace = nil)
    if exception
      message = exception.message || message
    else
      backtrace.try(&.each { |line| message += line })
    end
    message
  end
end
puts DiagnosticMessage.new.render("default-message")
CRYSTAL
cat >"$WORK_DIR/default_body.expected" <<'EXPECTED'
default-message
EXPECTED
: >"$WORK_DIR/default_body.stderr.expected"

cat >"$WORK_DIR/callsite_orders.cr" <<'CRYSTAL'
class DefaultBacktrace
  def render(message : String, backtrace = nil)
    if backtrace
      backtrace.each { |line| message += line }
    end
    message
  end
end
first = DefaultBacktrace.new
puts first.render("omitted")
puts first.render("explicit", ["/one", "/two"])
puts first.render("nil", nil)
class ReverseBacktrace
  def render(message : String, backtrace = nil)
    if backtrace
      backtrace.each { |line| message += line }
    end
    message
  end
end
second = ReverseBacktrace.new
puts second.render("explicit-first", ["/three"])
puts second.render("omitted-second")
puts second.render("nil-last", nil)
CRYSTAL
cat >"$WORK_DIR/callsite_orders.expected" <<'EXPECTED'
omitted
explicit/one/two
nil
explicit-first/three
omitted-second
nil-last
EXPECTED
: >"$WORK_DIR/callsite_orders.stderr.expected"

cat >"$WORK_DIR/module_forward.cr" <<'CRYSTAL'
module ForwardBacktrace
  def self.render(message : String, backtrace : Array(String)? = nil)
    if backtrace
      backtrace.each { |line| message += line }
    end
    message
  end
  def self.forward(message : String, backtrace = nil)
    render(message, backtrace)
  end
end
puts ForwardBacktrace.forward("omitted")
puts ForwardBacktrace.forward("explicit", ["/forwarded"])
puts ForwardBacktrace.forward("nil", nil)
CRYSTAL
cat >"$WORK_DIR/module_forward.expected" <<'EXPECTED'
omitted
explicit/forwarded
nil
EXPECTED
: >"$WORK_DIR/module_forward.stderr.expected"

cat >"$WORK_DIR/reassigned.cr" <<'CRYSTAL'
def default_reassigned(message : String, backtrace = nil)
  backtrace ||= ["/local"]
  backtrace.each { |line| message += line }
  message
end
puts default_reassigned("omitted")
puts default_reassigned("explicit", ["/actual"])
puts default_reassigned("nil", nil)
CRYSTAL
cat >"$WORK_DIR/reassigned.expected" <<'EXPECTED'
omitted/local
explicit/actual
nil/local
EXPECTED
: >"$WORK_DIR/reassigned.stderr.expected"

cat >"$WORK_DIR/buffered_error.cr" <<'CRYSTAL'
require "crystal/print_buffered"
Crystal.print_error_buffered("plain-error")
puts "after-error"
CRYSTAL
cat >"$WORK_DIR/buffered_error.expected" <<'EXPECTED'
after-error
EXPECTED
cat >"$WORK_DIR/buffered_error.stderr.expected" <<'EXPECTED'
plain-error
EXPECTED

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

for name in default_body callsite_orders module_forward reassigned buffered_error; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[nil-default-provenance]: five original-first fixtures agree"
