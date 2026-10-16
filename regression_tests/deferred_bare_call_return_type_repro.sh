#!/usr/bin/env bash
# Discover pending bare-call results before caller typing; evaluate each call once.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deferred-bare-result.XXXXXX")"
cleanup() {
  local status=$?
  for name in rescue self class module top main; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/rescue.cr" <<'CRYSTAL'
class EffectControls
  private def fail_string(value : String)
    raise value
  end
  private def fail_string(value : Int32)
    value + 1
  end
  private def wrapper(value : String)
    fail_string(value)
  end
  private def conditional(flag : Bool)
    if flag
      fail_string("missing")
    else
      "returned"
    end
  end
  private def rescuing
    begin
      fail_string("caught")
    rescue
      "rescued"
    end
  end
  private def nil_return
    nil
  end
  private def consume(value : String)
    value
  end
  def guard(flag : Bool)
    value = flag ? "guarded" : nil
    unless value
      wrapper("missing")
    end
    consume(value)
  end
  def controls
    puts fail_string(7)
    puts conditional(false)
    puts rescuing
    puts nil_return.nil?
    puts "continued"
  end
end
subject = EffectControls.new
puts subject.guard(true)
subject.controls
CRYSTAL
printf 'guarded\n8\nreturned\nrescued\ntrue\ncontinued\n' >"$WORK_DIR/rescue.expected"

cat >"$WORK_DIR/self.cr" <<'CRYSTAL'
class BareSelf
  private def fail
    raise "caught"
  end
  private def value(text : String = "rescued-self")
    puts "effect-self"
    begin
      fail
    rescue
      text
    end
  end
  private def consume(text : String)
    puts text
  end
  def run
    consume(value)
  end
end
BareSelf.new.run
CRYSTAL
printf 'effect-self\nrescued-self\n' >"$WORK_DIR/self.expected"

cat >"$WORK_DIR/class.cr" <<'CRYSTAL'
class BareClass
  private def self.fail
    raise "caught"
  end
  private def self.value
    puts "effect-class"
    begin
      fail
    rescue
      "rescued-class"
    end
  end
  private def self.consume(text : String)
    puts text
  end
  def self.run
    consume(value)
  end
end
BareClass.run
CRYSTAL
printf 'effect-class\nrescued-class\n' >"$WORK_DIR/class.expected"

cat >"$WORK_DIR/module.cr" <<'CRYSTAL'
module BareModule
  private def self.fail
    raise "caught"
  end
  private def self.value
    puts "effect-module"
    begin
      fail
    rescue
      "rescued-module"
    end
  end
  def self.run
    text = value
    puts text
  end
end
BareModule.run
CRYSTAL
printf 'effect-module\nrescued-module\n' >"$WORK_DIR/module.expected"

cat >"$WORK_DIR/top.cr" <<'CRYSTAL'
def fail
  raise "caught"
end
def value(text : String = "rescued-top")
  puts "effect-top"
  begin
    fail
  rescue
    text
  end
end
def consume(text : String)
  puts text
end
consume(value)
CRYSTAL
printf 'effect-top\nrescued-top\n' >"$WORK_DIR/top.expected"

cat >"$WORK_DIR/main.cr" <<'CRYSTAL'
def fail
  raise "caught"
end
def main
  puts "effect-main"
  begin
    fail
  rescue
    "rescued-main"
  end
end
puts main
CRYSTAL
printf 'effect-main\nrescued-main\n' >"$WORK_DIR/main.expected"

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
}

for name in rescue self class module top main; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate values and effect counts agree"
done
echo "PASS[deferred-bare-result]: six original-first fixtures agree"
